output "vpn_connection_ids" {
  value = { for k, v in aws_vpn_connection.this : k => v.id }
}

output "tunnel_addresses" {
  description = "Outside IPs of both tunnels per connection - what the on-prem device config needs."
  value = {
    for k, v in aws_vpn_connection.this : k => {
      tunnel1 = v.tunnel1_address
      tunnel2 = v.tunnel2_address
    }
  }
}

output "transit_gateway_attachment_ids" {
  value = { for k, v in aws_vpn_connection.this : k => v.transit_gateway_attachment_id }
}

output "customer_gateway_configuration" {
  description = "Vendor-neutral XML config (contains the pre-shared keys)."
  value       = { for k, v in aws_vpn_connection.this : k => v.customer_gateway_configuration }
  sensitive   = true
}
