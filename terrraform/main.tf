terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.45.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.1.0"
    }

    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }

    kubernetes = {  
      source  = "hashicorp/kubernetes"
      version = "2.3.2"
    }

    kubectl = {
      source = "gavinbunney/kubectl"
      version = "1.11.1"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region                  = var.aws_region
}

# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
module "eks" {
  source                  = "terraform-aws-modules/eks/aws"
  version                 = "17.1.0"
  cluster_name            = var.cluster_name
  cluster_version         = var.k8s_version
  subnets                 = module.vpc.private_subnets
  write_kubeconfig        = true
  kubeconfig_output_path  = var.kubeconfig_output

  # Needed for aws-autoscaler
  enable_irsa = true

  tags = {
      "k8s.io/cluster-autoscaler/enabled": "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}": "owned"
  }

  vpc_id = module.vpc.vpc_id

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  # node_groups are amazon eks managed nodes and worker_groups are self managed nodes
  # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/895
  node_groups = {
    # https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/node_groups
    cpu_nodes = {
      # TODO should set desired capacity to 0 when possible
      desired_capacity = 1
      max_capacity     = 6
      min_capacity     = 1
      create_launch_template = true
      worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]

      # https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt
      instance_types  = ["t3.large"]
      additional_tags = {
        description = "Kubeflow standard resources"
      }
    },
    gpu_nodes = {
      desired_capacity = 1
      max_capacity     = 4
      # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1324
      min_capacity     = 1
      create_launch_template = true
      worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
      # Add taints to let only kubeflow users use these nodes
      kubelet_extra_args = "--node-labels=role=private --register-with-taints=nodes_type=ml_node:NoSchedule"

      instance_types = ["g4dn.xlarge"]
      additional_tags = {
        description = "Kubeflow AI nodes"
      }
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

# Kubernetes provider
# https://learn.hashicorp.com/terraform/kubernetes/provision-eks-cluster#optional-configure-terraform-kubernetes-provider
# To learn how to schedule deployments and services using the provider, go here: https://learn.hashicorp.com/terraform/kubernetes/deploy-nginx-kubernetes

# The Kubernetes provider is included in this file so the EKS module can complete successfully. Otherwise, it throws an error when creating `kubernetes_config_map.aws_auth`.
# You should **not** schedule deployments and services in this workspace. This keeps workspaces modular (one for provision EKS, another for scheduling Kubernetes resources) as per best practices.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.cluster.name]
  }
}

provider "kubectl" {
  # Redundant, find a way to merge with the one above
  apply_retry_count      = 15
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  load_config_file       = false

  exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
  }
}

# State bucket
resource "aws_s3_bucket" "argoflow_state_bucket" {
  bucket = var.argoflow_state_bucket_name
  acl = "private"

  tags = {
    Name = "Argoflow state bucket"
  }
}

# Oauth2-Proxy cache
resource "aws_elasticache_cluster" "oauth_cache" {
  cluster_id           = "oauth-cache"
  engine               = "redis"
  node_type            = "cache.t2.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.x"
  port                 = 6379
}