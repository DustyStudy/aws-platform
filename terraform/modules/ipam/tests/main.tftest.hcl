mock_provider "aws" {}

variables {
  name_prefix       = "test"
  operating_regions = ["us-east-1", "us-west-2"]
  top_level_cidr    = "10.0.0.0/8"
  regional_pools = {
    use1 = { region = "us-east-1", cidr = "10.0.0.0/12" }
    usw2 = { region = "us-west-2", cidr = "10.16.0.0/12" }
  }
}

run "regional_pools_from_supernet" {
  command = plan

  assert {
    condition     = length(aws_vpc_ipam_pool.regional) == 2
    error_message = "Expected one pool per region."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["use1"].allocation_default_netmask_length == 20
    error_message = "Default VPC allocation should be a /20."
  }
}

run "rejects_pool_outside_operating_regions" {
  command = plan

  variables {
    regional_pools = {
      eu = { region = "eu-west-1", cidr = "10.32.0.0/12" }
    }
  }

  expect_failures = [var.regional_pools]
}

run "rejects_inverted_allocation_bounds" {
  command = plan

  variables {
    regional_pools = {
      use1 = { region = "us-east-1", cidr = "10.0.0.0/12", allocation_min = 24, allocation_default = 20, allocation_max = 16 }
    }
  }

  expect_failures = [var.regional_pools]
}
