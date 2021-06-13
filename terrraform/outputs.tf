output "cluster_id" {
  description = "EKS cluster ID."
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.eks.cluster_security_group_id
}

output "kubectl_config" {
  description = "kubectl config as generated by the module."
  value       = module.eks.kubeconfig
}

output "config_map_aws_auth" {
  description = "A kubernetes configuration to authenticate to this EKS cluster."
  value       = module.eks.config_map_aws_auth
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = var.cluster_name
}

output "worker_iam" {
  description = "The worker IAM role name"
  value = module.eks.worker_iam_role_name
}

output "cluster_autoscaler_arn" {
  description = "The cluster_autoscaler policy ARN"
  value = aws_iam_policy.cluster-autoscaler-policy.arn
}

output "loadbalancer_controller_arn" {
  description = "The loadbalancer_controller policy ARN"
  value = aws_iam_policy.load-balancer-policy.arn
}

output "external_dns_arn" {
  description = "The external_dns policy ARN"
  value = aws_iam_policy.ext_dns.arn
}