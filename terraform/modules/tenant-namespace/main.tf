# ---------------------------------------------------------------------------
# The golden path: everything a team needs to run one service on the shared
# platform, created by a single module call - namespace, quota, network
# isolation, a scoped ECR repo, and a pod-level IAM role via IRSA. No app
# team gets standing access to the VPC, the EKS control plane, or another
# team's resources.
# ---------------------------------------------------------------------------

locals {
  tenant_id = "${var.team_name}-${var.service_name}"
  # One namespace per service (not per team): calling this module twice for
  # the same team's two different services must not collide on a shared
  # namespace resource. Team grouping for cost allocation/RBAC dashboards
  # comes from the "platform.aws-platform.io/team" label, not the name.
  namespace            = "svc-${var.team_name}-${var.service_name}"
  service_account_name = var.service_name
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = local.namespace
    labels = {
      "platform.aws-platform.io/team"       = var.team_name
      "platform.aws-platform.io/service"    = var.service_name
      "platform.aws-platform.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "${local.namespace}-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota_cpu_requests
      "requests.memory" = var.quota_memory_requests
      "limits.cpu"      = var.quota_cpu_limits
      "limits.memory"   = var.quota_memory_limits
      "pods"            = var.quota_max_pods
    }
  }
}

resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "${local.namespace}-limits"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = var.default_container_cpu_limit
        memory = var.default_container_memory_limit
      }
      default_request = {
        cpu    = var.default_container_cpu_request
        memory = var.default_container_memory_request
      }
    }
  }
}

# Default deny, then explicitly allow: same-namespace traffic, ingress from
# the shared ALB controller's namespace, and DNS egress. Anything else -
# including other teams' namespaces - is blocked at the network layer, not
# just by IAM.

resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespace
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_ingress_controller" {
  metadata {
    name      = "allow-ingress-from-alb-controller"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_controller_namespace
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_dns_egress" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_https_egress" {
  metadata {
    name      = "allow-https-egress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}

# --- ECR ---------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = "tenant-${local.tenant_id}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.ecr_kms_key_arn
  }

  tags = merge(var.tags, { Team = var.team_name, Service = var.service_name })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
    ]
  })
}

# --- IRSA - pod-level IAM role scoped to this service's secrets path -----

data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${local.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service" {
  name               = "tenant-${local.tenant_id}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json
  tags               = merge(var.tags, { Team = var.team_name, Service = var.service_name })
}

data "aws_iam_policy_document" "service_permissions" {
  statement {
    sid    = "SecretsManagerOwnPathOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:${var.team_name}/${var.service_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "service" {
  name   = "secrets-access"
  role   = aws_iam_role.service.id
  policy = data.aws_iam_policy_document.service_permissions.json
}

resource "kubernetes_service_account" "this" {
  metadata {
    name      = local.service_account_name
    namespace = kubernetes_namespace.this.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service.arn
    }
  }
}

# --- Namespace-scoped human access ---------------------------------------

resource "aws_eks_access_entry" "team" {
  for_each = toset(var.team_iam_principal_arns)

  cluster_name  = var.cluster_name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "team" {
  for_each = toset(var.team_iam_principal_arns)

  cluster_name  = var.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [local.namespace]
  }
}
