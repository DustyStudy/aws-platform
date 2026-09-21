output "dx_gateway_id" {
  value = aws_dx_gateway.this.id
}

output "virtual_interface_ids" {
  value = { for k, v in aws_dx_transit_virtual_interface.this : k => v.id }
}

output "transit_gateway_attachment_id" {
  description = "The DX gateway's attachment on the TGW."
  value       = data.aws_ec2_transit_gateway_dx_gateway_attachment.this.id
}
