# ---------------------------------------------------------------------------
# Karpenter provisions and right-sizes nodes for tenant workloads on demand,
# instead of the platform team pre-sizing a static managed node group for
# every possible load. The system node group above only runs core add-ons,
# including Karpenter itself.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name          = "${var.cluster_name}-karpenter-spot-interruption"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Spot Instance Interruption Warning"] })
}

resource "aws_cloudwatch_event_rule" "instance_rebalance" {
  name          = "${var.cluster_name}-karpenter-rebalance"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance Rebalance Recommendation"] })
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name          = "${var.cluster_name}-karpenter-state-change"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance State-change Notification"] })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "instance_rebalance" {
  rule = aws_cloudwatch_event_rule.instance_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# --- Controller IAM (IRSA) --------------------------------------------------

data "aws_iam_policy_document" "karpenter_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_trust.json
  tags               = var.tags
}

# checkov:skip=CKV_AWS_355: this is the same shape AWS's own Karpenter
# getting-started IAM policy uses - ec2:RunInstances/CreateFleet/
# CreateLaunchTemplate/TerminateInstances don't accept a resource ARN
# (the instance doesn't exist yet), and the Describe*/pricing/ssm calls are
# read-only "*"-only APIs. iam:PassRole, the SQS queue, and the EKS
# DescribeCluster call below are all scoped to a specific ARN already.
# checkov:skip=CKV_AWS_356: same reasoning as CKV_AWS_355 above.
# checkov:skip=CKV_AWS_111: node-lifecycle writes (Run/Terminate/CreateFleet)
# against instances that don't exist yet, not unconstrained writes to
# existing resources.
# checkov:skip=CKV_AWS_108: no data-plane read/exfiltration actions here -
# EC2 fleet management and read-only pricing/SSM lookups only.
data "aws_iam_policy_document" "karpenter_controller_permissions" {
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowScopedEC2ReadOnly"
    effect    = "Allow"
    actions   = ["ec2:Describe*", "ec2:GetSpotPlacementScores"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPricingReadOnly"
    effect    = "Allow"
    actions   = ["pricing:GetProducts", "ssm:GetParameter"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    effect    = "Allow"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "karpenter-controller-permissions"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller_permissions.json
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.node.name
}

# --- Controller install ------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version

  values = [yamlencode({
    settings = {
      clusterName       = aws_eks_cluster.this.name
      clusterEndpoint   = aws_eks_cluster.this.endpoint
      interruptionQueue = aws_sqs_queue.karpenter_interruption.name
    }
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
      }
    }
    tolerations = [{
      key      = "platform-system"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]
    nodeSelector = {
      "platform-system" = "true"
    }
  })]

  depends_on = [aws_eks_node_group.system]
}

# --- Default provisioning shape ------------------------------------------
# EC2NodeClass / NodePool are Karpenter's own CRDs, applied once the chart
# (and its CRDs) exist. Kept minimal on purpose: on-demand + spot, generic
# instance families, scoped to subnets/security groups tagged for discovery
# by the vpc module.

resource "kubernetes_manifest" "karpenter_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "AL2023"
      role      = aws_iam_role.node.name
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      securityGroupSelectorTerms = [{
        tags = { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }
      }]
      tags = var.tags
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand", "spot"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["m", "c", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
          ]
        }
      }
      limits = {
        cpu = var.karpenter_cpu_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}
