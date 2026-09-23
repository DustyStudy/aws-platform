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

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name          = "${var.cluster_name}-karpenter-scheduled-change"
  event_pattern = jsonencode({ source = ["aws.health"], "detail-type" = ["AWS Health Event"] })
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule = aws_cloudwatch_event_rule.scheduled_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
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
# RunInstances/CreateFleet/CreateLaunchTemplate act on resources that don't
# exist yet, Terminate is conditioned on the cluster's ownership tag, and
# Describe*/pricing/ListInstanceProfiles are read-only "*"-only APIs - the
# same shape as Karpenter's published policy.
# tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "karpenter_controller_permissions" {
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
    ]
    resources = ["*"]
  }

  # Karpenter only terminates instances / deletes launch templates it tagged as
  # belonging to this cluster - not any instance in the account.
  statement {
    sid       = "AllowScopedDeletion"
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
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
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # AMI resolution for the al2023@latest alias - AWS's public parameters only.
  statement {
    sid       = "AllowAMIParameterRead"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}::parameter/aws/service/*"]
  }

  # The EC2NodeClass references the instance profile below by name, so
  # Karpenter never has to create or modify instance profiles itself - it
  # only needs to read the one it was given.
  # Also the <cluster>_<hash> name Karpenter would generate itself: on
  # EC2NodeClass deletion it checks for (and would clean up) that profile even
  # when the NodeClass names an existing one, and a 403 there leaves the
  # NodeClass stuck terminating.
  statement {
    sid     = "AllowInstanceProfileRead"
    effect  = "Allow"
    actions = ["iam:GetInstanceProfile"]
    resources = [
      aws_iam_instance_profile.karpenter_node.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.cluster_name}_*",
    ]
  }

  statement {
    sid       = "AllowInstanceProfileList"
    effect    = "Allow"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # Karpenter launches spot capacity; the Spot service-linked role has to
  # exist first, and in a fresh account nothing else creates it.
  statement {
    sid       = "AllowSpotServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["spot.amazonaws.com"]
    }
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
    # The chart spreads replicas one per node, and they can only run on the
    # system node group - more replicas than system nodes leaves one Pending.
    replicas = min(2, var.system_node_min_size)
  })]

  # CoreDNS has to be schedulable before the controller can resolve AWS
  # endpoints - see aws_eks_addon.coredns. The rest matters on destroy: the
  # controller has to outlive its IAM permissions and pod networking, because
  # removing karpenter-defaults waits on its EC2NodeClass finalizer, which only
  # a working controller can clear.
  depends_on = [
    aws_eks_node_group.system,
    aws_eks_addon.coredns,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_iam_role_policy.karpenter_controller,
  ]
}

# --- Default provisioning shape ------------------------------------------
# EC2NodeClass / NodePool are Karpenter's own CRDs. They're installed through
# a small local chart rather than kubernetes_manifest: kubernetes_manifest
# needs a reachable API server with the CRDs already registered at *plan*
# time, so a fresh environment's first plan fails before the cluster exists.
# Kept minimal on purpose: on-demand + spot, generic instance families, the
# cluster's own subnets and security group.

resource "helm_release" "karpenter_defaults" {
  name      = "karpenter-defaults"
  namespace = "kube-system"
  chart     = "${path.module}/charts/karpenter-defaults"

  values = [yamlencode({
    clusterName         = var.cluster_name
    instanceProfile     = aws_iam_instance_profile.karpenter_node.name
    securityGroupId     = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
    cpuLimit            = var.karpenter_cpu_limit
    tags                = var.tags
    consolidateAfter    = "5m"
    consolidationPolicy = "WhenEmptyOrUnderutilized"
  })]

  depends_on = [helm_release.karpenter]
}
