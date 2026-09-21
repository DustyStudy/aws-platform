mock_provider "aws" {}

variables {
  name_prefix           = "test"
  vpc_id                = "vpc-1"
  subnet_ids            = ["subnet-a", "subnet-b"]
  certificate_arn       = "arn:aws:acm:us-east-1:111122223333:certificate/abc"
  access_logs_bucket    = "lb-logs"
  allowed_ingress_cidrs = ["10.0.0.0/8"]
  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
  target_security_groups = { app = "sg-app" }
}

run "alb_is_hardened_by_default" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == true
    error_message = "Load balancers must be internal unless explicitly opened."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true && aws_lb.this.enable_deletion_protection == true
    error_message = "ALB must drop invalid headers and have deletion protection on."
  }

  assert {
    condition     = aws_lb_listener.http_redirect[0].default_action[0].type == "redirect"
    error_message = "Port 80 must only redirect."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.to_targets) == 2
    error_message = "ALB egress should be one rule per (target SG x target group port)."
  }
}

run "nlb_has_no_alb_only_resources" {
  command = plan

  variables {
    type = "network"
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_lb_listener.http_redirect) == 0
    error_message = "NLB should not create the ALB security group or HTTP redirect."
  }

  assert {
    condition     = aws_lb_listener.tls.protocol == "TLS"
    error_message = "NLB listener must be TLS."
  }
}

run "rejects_bad_type" {
  command = plan

  variables {
    type = "gateway"
  }

  expect_failures = [var.type]
}
