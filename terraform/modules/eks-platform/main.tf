data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------

resource "aws_kms_key" "cluster" {
  description             = "${var.cluster_name} EKS secrets + control plane log encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 365 # CKV_AWS_338 - control plane audit logs kept >= 1 year
  kms_key_id        = aws_kms_key.cluster.arn
}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

resource "aws_security_group" "cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  description = "EKS control plane and node communication"

  # checkov:skip=CKV_AWS_382: the control plane and every node need outbound
  # HTTPS to AWS APIs (STS, ECR, EC2), the pod ENIs it manages, and whatever
  # ClusterIP/NodePort services route through it - there's no fixed CIDR/port
  # set to scope this to short of replicating the AWS-managed EKS SG's own
  # rule, which uses the same shape.
  # tfsec:ignore:aws-ec2-no-public-egress-sgr: see the CKV_AWS_382 note above.
  egress {
    description = "All outbound - control plane needs AWS API + node/pod reachability, not a fixed CIDR/port set"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-cluster-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # checkov:skip=CKV_AWS_39: the public endpoint is off unless the caller
  # opts in with endpoint_public_access, and a variable validation refuses
  # that without an explicit public_access_cidrs allowlist.
  # checkov:skip=CKV_AWS_38: same - the allowlist is the caller's, validated
  # non-empty; an operator can scope it to runner/VPN egress IPs.
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------
# IRSA - OIDC provider for the cluster, so pods can assume scoped IAM roles
# instead of inheriting the node's instance profile.
# ---------------------------------------------------------------------------

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# System node group - small, tainted, runs only core add-ons (CoreDNS, the
# AWS Load Balancer Controller, Karpenter itself). Everything else runs on
# Karpenter-provisioned capacity (see karpenter.tf).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", # SSM Session Manager access, no SSH keys/bastion
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.system_node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = var.system_node_min_size
    max_size     = var.system_node_max_size
    desired_size = var.system_node_desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "platform-system" = "true"
  }

  taint {
    key    = "platform-system"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# Core add-ons, managed by EKS instead of the self-managed copies a new cluster
# starts with:
#   - vpc-cni with the network policy agent enabled. Without it the VPC CNI
#     accepts NetworkPolicy objects but never enforces them, so the tenant
#     module's default-deny policies would be decoration.
#   - coredns tolerating the system node taint. Every node the cluster starts
#     with is tainted platform-system, and Karpenter (which launches the
#     untainted capacity) needs DNS to reach AWS APIs - an untolerated CoreDNS
#     would leave both waiting on each other forever.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    tolerations = [
      { key = "CriticalAddonsOnly", operator = "Exists" },
      { key = "platform-system", operator = "Equal", value = "true", effect = "NoSchedule" },
    ]
  })

  tags = var.tags

  # CoreDNS only goes ACTIVE once its pods are running, which needs nodes.
  depends_on = [aws_eks_node_group.system]
}

# ---------------------------------------------------------------------------
# EKS access entries - human/team access is granted per-namespace via
# access policy associations, not via cluster-admin kubeconfig sharing.
# The bootstrap creator (CI's apply role) gets cluster-admin implicitly via
# bootstrap_cluster_creator_admin_permissions above.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "platform_admins" {
  for_each = toset(var.platform_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "platform_admins" {
  for_each = toset(var.platform_admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.platform_admins]
}

# Read-only principals (CI's plan/drift role). AmazonEKSAdminViewPolicy rather
# than AmazonEKSViewPolicy because terraform plan refreshes helm releases, and
# Helm stores release state in Secrets that the plain view policy can't read.
resource "aws_eks_access_entry" "viewers" {
  for_each = toset(var.cluster_viewer_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "viewers" {
  for_each = toset(var.cluster_viewer_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.viewers]
}
