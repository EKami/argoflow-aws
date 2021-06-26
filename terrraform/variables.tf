variable "cluster_name" {
  description = "unique name of the eks cluster"
  type    = string
}

variable "aws_region" {
 description = "Name of aws region to use"
 type    = string
}

variable "k8s_version" {
  description = "kubernetes version"
  default = "1.20"
  type    = string
}

variable "kubeconfig_output" {
  description = "Where to write the kubeconfig"
  type = string
}

variable "hosted_dns_name" {
  description = "The dns name, var.domain_name will be added to it"
  type = string
}

variable "domain_name" {
  description = "The domain name for the kubeflow server"
  type        = string
  default     = "kubeflow"
}

variable "base_github_repo" {
  description = "Used for the IAM policies, could be useful if you want to use your own fork, for example: https://raw.githubusercontent.com/{var.base_github_repo}/docs/iam_policies/cluster-autoscaler.json"
  type        = string
  default     = "argoflow/argoflow-aws/master"
}

variable "db_instance_type" {
  description = "The db that contains data for cachedb/mlpipeline/metadb/katib/mlflow"
  type        = string
  default     = "db.t3.small"
}

variable "argoflow_state_bucket_name" {
  description = "The name of the bucket that stores the MLFlow and Kubeflow pipeline artifacts"
  default = "argoflow-state-bucket"
}

variable "repo_url" {
  description = "The repo url where this project is located, used by argocd to pull the apps"
  type = string
}

variable "target_revision" {
  description = "Branch to use to pull the argocd apps"
  type = string
}