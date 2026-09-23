data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# AWS Managed Prometheus - one workspace per environment, fed by the AWS
# managed scraper (see aws_prometheus_scraper below), so every tenant
# namespace's metrics land in one place without the platform team running and
# patching its own Prometheus deployment.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "observability" {
  description             = "${var.name_prefix} observability log encryption"
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
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
      },
      {
        # CloudWatch alarms publish to the platform-alerts topic, which is
        # encrypted with this key. The AWS-managed alias/aws/sns key can't be
        # used here: its policy doesn't admit cloudwatch.amazonaws.com, so
        # every alarm notification would be dropped.
        Sid       = "CloudWatchAlarmsPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })
}

resource "aws_prometheus_workspace" "this" {
  alias = "${var.name_prefix}-amp"
  tags  = var.tags

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws-platform/${var.name_prefix}/amp"
  kms_key_id        = aws_kms_key.observability.arn
  retention_in_days = 365 # CKV_AWS_338
  tags              = var.tags
}

# --- Metrics collection -------------------------------------------------------
# Neither collector below runs as a pod that needs instance metadata. The
# platform's nodes require IMDSv2 with a hop limit of 1, so pods can't reach
# the node role's credentials, and that also means a pod-network collector
# can't read IMDS. (The ADOT DaemonSet this replaces failed on exactly that and
# dropped every metric.)
#
#   Prometheus -> AMP: the AWS managed scraper. It runs outside the cluster
#                      and reaches the API server through ENIs in the private
#                      subnets. There's nothing in-cluster to patch.
#   Container Insights -> CloudWatch: the amazon-cloudwatch-observability EKS
#                      add-on. Its node metrics are what the node CPU/memory
#                      alarms below evaluate.

resource "aws_prometheus_scraper" "this" {
  count = var.enable_metrics_collection ? 1 : 0

  alias = "${var.name_prefix}-scraper"

  source {
    eks {
      cluster_arn        = var.cluster_arn
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.cluster_security_group_id]
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.this.arn
    }
  }

  scrape_configuration = templatefile("${path.module}/scrape-config.yaml.tftpl", {
    cluster_name = var.cluster_name
  })

  tags = var.tags
}

# No access entry or RBAC here: creating the scraper makes AMP add an access
# entry for its service-linked role with the AWS-managed
# AmazonPrometheusScraperPolicy. EKS refuses to let anyone else create access
# entries for a service-linked role, so declaring one here fails the apply.

# --- Container Insights (CloudWatch agent add-on, IRSA) ----------------------

locals {
  cloudwatch_agent_namespace       = "amazon-cloudwatch"
  cloudwatch_agent_service_account = "cloudwatch-agent"
}

data "aws_iam_policy_document" "cloudwatch_agent_trust" {
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
      values   = ["system:serviceaccount:${local.cloudwatch_agent_namespace}:${local.cloudwatch_agent_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.name_prefix}-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_agent_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Created here rather than by the agent, so it gets the same KMS key and
# retention as every other platform log group.
resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${var.cluster_name}/performance"
  kms_key_id        = aws_kms_key.observability.arn
  retention_in_days = 365 # CKV_AWS_338
  tags              = var.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_metrics_collection ? 1 : 0

  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_agent.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    # Metrics only. Shipping every container's stdout to CloudWatch Logs is a
    # separate cost decision, off by default.
    containerLogs = { enabled = false }
    # The agent is per-node, so it has to run on the tainted system nodes too.
    tolerations = [{ operator = "Exists" }]
  })

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch_agent,
    aws_cloudwatch_log_group.container_insights,
  ]
}

# ---------------------------------------------------------------------------
# AWS Managed Grafana - service-managed permissions, IAM Identity Center
# authentication. SSO enrollment/group mapping is an IAM Identity Center
# concern outside this module's scope; this provisions the workspace and the
# data source read role.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "grafana" {
  name = "${var.name_prefix}-grafana-workspace"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# checkov:skip=CKV_AWS_355: AMP/CloudWatch query and read APIs (QueryMetrics,
# GetSeries, DescribeAlarmsForMetric, GetMetricData, ...) don't support
# resource-level ARN scoping - AWS defines them as "*"-only actions.
# checkov:skip=CKV_AWS_111: same - these are read-only query APIs, not writes.
# tfsec:ignore:aws-iam-no-policy-wildcards: see the CKV_AWS_355 note above.
data "aws_iam_policy_document" "grafana_data_sources" {
  statement {
    sid    = "QueryPrometheus"
    effect = "Allow"
    actions = [
      "aps:QueryMetrics",
      "aps:GetSeries",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "QueryCloudWatch"
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:GetQueryResults",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_data_sources" {
  name   = "read-data-sources"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_data_sources.json
}

resource "aws_grafana_workspace" "this" {
  count = var.create_grafana_workspace ? 1 : 0

  name                     = "${var.name_prefix}-amg"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Platform-level CloudWatch alarms - independent of the AMP/Grafana path, so
# there's a signal even if the observability stack itself is unhealthy.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "platform_alerts" {
  name              = "${var.name_prefix}-platform-alerts"
  kms_master_key_id = aws_kms_key.observability.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.platform_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${var.name_prefix}-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Cluster node CPU utilization above 85% for 15 minutes."
  dimensions          = { ClusterName = var.cluster_name }
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]
  ok_actions          = [aws_sns_topic.platform_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "node_memory_high" {
  alarm_name          = "${var.name_prefix}-node-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Cluster node memory utilization above 85% for 15 minutes."
  dimensions          = { ClusterName = var.cluster_name }
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]
  ok_actions          = [aws_sns_topic.platform_alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_log_metric_filter" "karpenter_provisioning_failure" {
  name           = "${var.name_prefix}-karpenter-provisioning-failure"
  log_group_name = "/aws/eks/${var.cluster_name}/cluster"
  pattern        = "\"failed to provision\""

  metric_transformation {
    name          = "KarpenterProvisioningFailures"
    namespace     = "${var.name_prefix}/platform"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "karpenter_provisioning_failure" {
  alarm_name          = "${var.name_prefix}-karpenter-provisioning-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.karpenter_provisioning_failure.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.karpenter_provisioning_failure.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Karpenter failed to provision nodes for pending workloads."
  alarm_actions       = [aws_sns_topic.platform_alerts.arn]
  treat_missing_data  = "notBreaching"
}
