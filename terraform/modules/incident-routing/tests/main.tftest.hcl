mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name_prefix    = "test"
  pager_endpoint = "https://events.pagerduty.com/integration/KEY/enqueue"
  ticket_emails  = ["tickets@example.com"]
}

run "severity_tiers" {
  command = plan

  assert {
    condition     = length(aws_sns_topic.this) == 4
    error_message = "Expected sev1-sev4 topics."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.pager) == 2
    error_message = "Only sev1 and sev2 should page."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.tickets) == 2
    error_message = "sev3 and sev4 should go to the ticket inbox."
  }
}

run "prod_requires_pager" {
  command = plan

  variables {
    pager_endpoint = null
    require_pager  = true
  }

  expect_failures = [aws_sqs_queue.pager_dlq]
}

run "rejects_plain_http_pager" {
  command = plan

  variables {
    pager_endpoint = "http://example.com/hook"
  }

  expect_failures = [var.pager_endpoint]
}
