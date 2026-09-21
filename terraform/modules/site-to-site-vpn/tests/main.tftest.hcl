mock_provider "aws" {}

variables {
  name_prefix                 = "test"
  transit_gateway_id          = "tgw-123"
  association_route_table_id  = "tgw-rtb-hybrid"
  propagation_route_table_ids = { spokes = "tgw-rtb-spokes", shared = "tgw-rtb-shared" }
  customer_gateways = {
    dc1 = { ip_address = "203.0.113.10", bgp_asn = 65010 }
  }
  connections = {
    dc1 = { customer_gateway = "dc1" }
  }
}

run "pins_ikev2_and_bgp" {
  command = plan

  assert {
    condition     = aws_vpn_connection.this["dc1"].static_routes_only == false
    error_message = "VPN must use BGP, not static routes."
  }

  assert {
    condition     = aws_vpn_connection.this["dc1"].tunnel1_ike_versions == toset(["ikev2"]) && aws_vpn_connection.this["dc1"].tunnel2_ike_versions == toset(["ikev2"])
    error_message = "Both tunnels must be IKEv2 only."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.this) == 2
    error_message = "Expected one propagation per (connection, route table)."
  }
}

run "rejects_bad_cgw_ip" {
  command = plan

  variables {
    customer_gateways = {
      dc1 = { ip_address = "not-an-ip", bgp_asn = 65010 }
    }
  }

  expect_failures = [var.customer_gateways]
}
