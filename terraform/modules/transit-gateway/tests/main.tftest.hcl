mock_provider "aws" {}

variables {
  name_prefix = "test"
}

run "segmented_attachments" {
  command = plan

  variables {
    vpc_attachments = {
      prod = { vpc_id = "vpc-1", subnet_ids = ["subnet-1"], route_table = "spokes", propagate_to = ["hybrid"] }
      dev  = { vpc_id = "vpc-2", subnet_ids = ["subnet-2"], route_table = "spokes" }
    }
  }

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable"
    error_message = "TGW must not use the default route table."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_association.this) == 2
    error_message = "Each attachment needs an explicit association."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.this) == 1
    error_message = "Only the attachment with propagate_to should propagate."
  }
}

run "rejects_unknown_route_table" {
  command = plan

  variables {
    vpc_attachments = {
      bad = { vpc_id = "vpc-1", subnet_ids = ["subnet-1"], route_table = "nope" }
    }
  }

  expect_failures = [var.vpc_attachments]
}

run "rejects_public_asn" {
  command = plan

  variables {
    amazon_side_asn = 7224
  }

  expect_failures = [var.amazon_side_asn]
}
