# Severity-tiered alert routing. The point is that severity is decided when the
# alarm is *written* (which topic it publishes to) rather than at 3am by
# whoever is holding the pager:
#
#   sev1 / sev2  -> pager    (a human is woken up)
#   sev3 / sev4  -> tickets  (a human looks at it during working hours)
#
# See docs/incident-response/ for what each severity means and who does what.

locals {
  severities = {
    sev1 = { pages = true }
    sev2 = { pages = true }
    sev3 = { pages = false }
    sev4 = { pages = false }
  }

  # Whether an endpoint is set isn't secret; its value is. Splitting the two
  # keeps the URL out of for_each keys while still allowing a conditional.
  has_pager = nonsensitive(var.pager_endpoint != null)
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:key policy root statement is the standard admin delegation
  #checkov:skip=CKV_AWS_111:key policy root statement is the standard admin delegation
  #checkov:skip=CKV_AWS_356:key policies scope by principal, Resource "*" means "this key"
  statement {
    sid       = "AllowRootAccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch alarms and EventBridge rules publish to these topics, so both
  # services need to be able to use the key to encrypt the message.
  statement {
    sid       = "AllowAlarmPublishers"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "${var.name_prefix} incident alert topics"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = var.tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name_prefix}-incident-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "this" {
  for_each = local.severities

  name              = "${var.name_prefix}-${each.key}"
  kms_master_key_id = aws_kms_key.alerts.arn
  tags              = merge(var.tags, { Severity = each.key })
}

data "aws_iam_policy_document" "topic" {
  for_each = local.severities

  statement {
    sid       = "AllowAlarmsAndEventsToPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  for_each = local.severities

  arn    = aws_sns_topic.this[each.key].arn
  policy = data.aws_iam_policy_document.topic[each.key].json
}

resource "aws_sns_topic_subscription" "pager" {
  for_each = local.has_pager ? toset([for k, v in local.severities : k if v.pages]) : toset([])

  topic_arn = aws_sns_topic.this[each.key].arn
  protocol  = "https"
  endpoint  = var.pager_endpoint

  # A pager outage must not silently swallow the alert: retry, then dead-letter.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pager_dlq.arn
  })
}

resource "aws_sns_topic_subscription" "tickets" {
  for_each = {
    for pair in setproduct([for k, v in local.severities : k if !v.pages], var.ticket_emails) :
    "${pair[0]}:${pair[1]}" => { severity = pair[0], email = pair[1] }
  }

  topic_arn = aws_sns_topic.this[each.value.severity].arn
  protocol  = "email"
  endpoint  = each.value.email
}

# Undeliverable pages land here. An alarm on this queue is the "the pager
# itself is broken" signal - the failure mode that otherwise stays invisible
# until the next real incident.
resource "aws_sqs_queue" "pager_dlq" {
  name                      = "${var.name_prefix}-pager-dlq"
  kms_master_key_id         = aws_kms_key.alerts.arn
  message_retention_seconds = 1209600
  tags                      = var.tags

  # Hard plan-time error (a check block would only warn). Lives on this
  # resource because it always exists, unlike the pager subscriptions.
  lifecycle {
    precondition {
      condition     = !var.require_pager || local.has_pager
      error_message = "require_pager is set but pager_endpoint is null - SEV1/SEV2 alerts would go nowhere."
    }
  }
}

data "aws_iam_policy_document" "dlq" {
  statement {
    sid       = "AllowSnsToDeadLetter"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.pager_dlq.arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for k, v in local.severities : aws_sns_topic.this[k].arn if v.pages]
    }
  }
}

resource "aws_sqs_queue_policy" "pager_dlq" {
  queue_url = aws_sqs_queue.pager_dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}

resource "aws_cloudwatch_metric_alarm" "pager_delivery_failed" {
  alarm_name          = "${var.name_prefix}-pager-delivery-failed"
  alarm_description   = "SNS could not deliver a SEV1/SEV2 page. The pager integration is broken - treat as SEV2 and check the endpoint/integration key. See docs/incident-response/runbooks/pager-delivery-failed.md"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.pager_dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # Cannot page via the thing that is broken - route to the ticket-tier topic
  # (email) instead so the failure is at least visible.
  alarm_actions = [aws_sns_topic.this["sev3"].arn]
  tags          = var.tags
}
