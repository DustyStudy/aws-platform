output "ipam_id" {
  value = aws_vpc_ipam.this.id
}

output "top_pool_id" {
  value = aws_vpc_ipam_pool.top.id
}

output "regional_pool_ids" {
  description = "Map of pool key -> IPAM pool ID. Pass as ipv4_ipam_pool_id when creating a VPC."
  value       = { for k, v in aws_vpc_ipam_pool.regional : k => v.id }
}
