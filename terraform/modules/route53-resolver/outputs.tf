output "inbound_endpoint_id" {
  value = try(aws_route53_resolver_endpoint.inbound[0].id, null)
}

output "inbound_ip_addresses" {
  description = "IPs to configure as conditional-forwarder targets on the on-prem DNS servers."
  value       = try(aws_route53_resolver_endpoint.inbound[0].ip_address[*].ip, [])
}

output "outbound_endpoint_id" {
  value = try(aws_route53_resolver_endpoint.outbound[0].id, null)
}

output "forward_rule_ids" {
  value = { for k, v in aws_route53_resolver_rule.forward : k => v.id }
}
