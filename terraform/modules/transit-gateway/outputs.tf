output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  value = aws_ec2_transit_gateway.this.arn
}

output "route_table_ids" {
  description = "Map of route table name -> TGW route table ID."
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}

output "vpc_attachment_ids" {
  description = "Map of attachment key -> TGW VPC attachment ID."
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}
