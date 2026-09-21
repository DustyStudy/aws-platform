mock_provider "aws" {}

variables {
  name_prefix    = "test"
  vpc_id         = "vpc-hub"
  subnet_ids     = ["subnet-a", "subnet-b"]
  onprem_cidrs   = ["192.168.0.0/16"]
  associate_vpcs = { hub = "vpc-hub", prod = "vpc-prod" }
  forward_rules = {
    corp = { domain_name = "corp.example.com", target_ips = ["192.168.1.10", "192.168.2.10"] }
  }
}

run "hybrid_dns" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_rule_association.this) == 2
    error_message = "One rule x two VPCs = two associations."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.outbound_udp) == 2
    error_message = "Outbound SG should only allow the two named on-prem resolvers."
  }
}

run "rejects_single_target" {
  command = plan

  variables {
    forward_rules = {
      corp = { domain_name = "corp.example.com", target_ips = ["192.168.1.10"] }
    }
  }

  expect_failures = [var.forward_rules]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-a"]
  }

  expect_failures = [var.subnet_ids]
}
