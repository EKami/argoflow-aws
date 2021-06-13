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
  default = "1.19"
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