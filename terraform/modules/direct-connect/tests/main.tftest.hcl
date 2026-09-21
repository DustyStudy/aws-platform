mock_provider "aws" {}

variables {
  name_prefix                 = "test"
  connection_id               = "dxcon-abc123"
  transit_gateway_id          = "tgw-123"
  association_route_table_id  = "tgw-rtb-hybrid"
  propagation_route_table_ids = { spokes = "tgw-rtb-spokes" }
  allowed_prefixes            = ["10.0.0.0/8"]
  virtual_interfaces = {
    a = { vlan = 100, bgp_asn = 65010 }
  }
}

run "builds_transit_vif" {
  command = plan

  assert {
    condition     = aws_dx_transit_virtual_interface.this["a"].mtu == 8500
    error_message = "Transit VIF should default to jumbo MTU 8500."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.connection_down.treat_missing_data == "breaching"
    error_message = "A silent connection must be treated as down."
  }
}

run "rejects_bad_mtu" {
  command = plan

  variables {
    virtual_interfaces = {
      a = { vlan = 100, bgp_asn = 65010, mtu = 9001 }
    }
  }

  expect_failures = [var.virtual_interfaces]
}

run "rejects_too_many_prefixes" {
  command = plan

  variables {
    allowed_prefixes = [for i in range(21) : "10.${i}.0.0/16"]
  }

  expect_failures = [var.allowed_prefixes]
}
