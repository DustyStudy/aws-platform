output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id

  # Whatever runs in these subnets (EKS nodes, the Karpenter controller) may
  # still need to reach AWS APIs while it's being torn down - Karpenter has
  # to terminate its own nodes. Tying consumers to the whole egress path
  # (private route -> NAT -> public route -> IGW) makes terraform destroy
  # them before any hop of it.
  depends_on = [
    aws_route.private_nat,
    aws_route_table_association.private,
    aws_nat_gateway.this,
    aws_route.public_internet,
    aws_route_table_association.public,
  ]
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}
