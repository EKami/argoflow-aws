# --- Load balancer
data "http" "load-balancer-policy" {
  url = "https://raw.githubusercontent.com/${var.base_github_repo}/docs/iam_policies/aws-loadbalancer-controller.json"
}

resource "aws_iam_policy" "load-balancer-policy" {
  name = "AWSLoadBalancerControllerIAMPolicy"
  description = "AWS LoadBalancer Controller IAM Policy for k8s cluster"
  policy      = data.http.load-balancer-policy.body
}

resource "aws_iam_role_policy_attachment" "aws-load-balancer-controller" {
  policy_arn = aws_iam_policy.load-balancer-policy.arn
  role       = module.eks.worker_iam_role_name
}

# --- Cluster autoscaler
data "http" "cluster-autoscaler-policy" {
  url = "https://raw.githubusercontent.com/${var.base_github_repo}/docs/iam_policies/cluster-autoscaler.json"
}

resource "aws_iam_policy" "cluster-autoscaler-policy" {
  name = "AWSClusterAutoscalerIAMPolicy"
  description = "AWS Cluster Autoscaler IAM Policy for k8s cluster"
  policy      = data.http.cluster-autoscaler-policy.body
}

resource "aws_iam_role_policy_attachment" "cluster-autoscaler" {
  policy_arn = aws_iam_policy.cluster-autoscaler-policy.arn
  role       = module.eks.worker_iam_role_name
}


# --- External DNS
resource "aws_iam_role_policy_attachment" "ext_dns" {
  policy_arn = aws_iam_policy.ext_dns.arn
  role       = module.eks.worker_iam_role_name
}

resource "aws_iam_policy" "ext_dns" {
  name_prefix = "eks-ext-dns-${module.eks.cluster_id}"
  description = "EKS ext-dns for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.ext_dns.json
}

data "aws_iam_policy_document" "ext_dns" {
  statement {
    effect = "Allow"

    actions = [
      "route53:GetChange"
    ]

    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]

    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]

    resources = ["*"]
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "${var.domain_name}.${var.hosted_dns_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cert_val" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.ext-dns-route : record.fqdn]
}

data "aws_route53_zone" "domain" {
  name         = var.hosted_dns_name
  private_zone = false
}

resource "aws_route53_record" "ext-dns-route" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain.zone_id
}

# --- External secrets (Option 1)
resource "aws_iam_policy" "external-secrets" {
  name = "AWSExternalSecretsIAMPolicy"
  description = "AWS external secrets IAM Policy for k8s cluster"
  policy      = data.aws_iam_policy_document.external-secrets.json
}

data "aws_iam_policy_document" "external-secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:GetSecretValue",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:DescribeSecret"
    ]

    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}*"]
  }
}

resource "aws_iam_role_policy_attachment" "external-secrets" {
  policy_arn = aws_iam_policy.external-secrets.arn
  role       = module.eks.worker_iam_role_name
}

# ------------------ ExternalSecret for specific namespaces (only useful for option 2) ------------------
# --- ExternalSecret for Option 2
# Group IAM policies, otherwise we'll reach the "Cannot exceed quota for PoliciesPerRole: 10" error
# resource "aws_iam_policy" "external-secrets-namespaces" {
#   name = "AWSExternalSecretsNamespacesCDIAMPolicy"
#   description = "AWS external namespace secrets IAM Policy for k8s cluster"
#   policy      = data.aws_iam_policy_document.external-secrets-argocd.json
# }

# data "aws_iam_policy_document" "external-secrets-namespaces" {
#   statement {
#     effect = "Allow"

#     actions = [
#       "secretsmanager:ListSecretVersionIds",
#       "secretsmanager:GetSecretValue",
#       "secretsmanager:GetResourcePolicy",
#       "secretsmanager:DescribeSecret"
#     ]

#     resources = [
#       "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/istio-system*",
#       "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/argocd*",
#       "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/kubeflow*",
#       "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/oauth2-proxy*",
#       "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/mlflow*"
#     ]
#   }
# }

# resource "aws_iam_role_policy_attachment" "external-secrets-namespaces" {
#   policy_arn = aws_iam_policy.external-secrets-namespaces.arn
#   role       = module.eks.worker_iam_role_name
# }
