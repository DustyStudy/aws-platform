# Plans the whole composition against a mocked provider. Unlike each module's
# own tests (which pass literal IDs), here every VPC / TGW / route-table ID is
# *unknown until apply*, exactly as in a real first deploy. That is what catches
# for_each/count arguments built from values that can't be known at plan time.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

variables {
  pager_endpoint      = "https://events.pagerduty.com/integration/KEY/enqueue"
  ticket_emails       = ["tickets@example.com"]
  dx_connection_id    = "dxcon-abc123"
  customer_gateway_ip = "203.0.113.10"
  onprem_cidrs        = ["192.168.0.0/16"]
  onprem_dns_ips      = ["192.168.1.10", "192.168.2.10"]
  certificate_arn     = "arn:aws:acm:us-east-1:111122223333:certificate/abc"
  access_logs_bucket  = "lb-logs"
  org_arns            = ["arn:aws:organizations::111122223333:organization/o-abc123"]
}

run "first_deploy_plans_with_unknown_ids" {
  command = plan

  assert {
    condition     = length(module.tgw.route_table_ids) == 3 && length(module.incident_routing.topic_arns) == 4
    error_message = "Composition should plan cleanly with all three TGW route tables and four severity topics."
  }
}
