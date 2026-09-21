# Hub of a hub-and-spoke network. Default route-table association/propagation
# are OFF on purpose: with them on, every attachment lands in one flat route
# table and every VPC can reach every other VPC and the on-prem network.

resource "aws_ec2_transit_gateway" "this" {
  description     = "${var.name_prefix} transit gateway"
  amazon_side_asn = var.amazon_side_asn

  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw" })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = toset(var.route_tables)

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "${var.name_prefix}-tgw-rt-${each.key}" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  appliance_mode_support                          = each.value.appliance_mode ? "enable" : "disable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw-att-${each.key}" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.vpc_attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

locals {
  propagations = merge([
    for k, v in var.vpc_attachments : {
      for t in v.propagate_to : "${k}:${t}" => { attachment = k, route_table = t }
    }
  ]...)
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = local.propagations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

resource "aws_ec2_transit_gateway_route" "static" {
  for_each = var.static_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
  blackhole                      = each.value.blackhole
  transit_gateway_attachment_id  = each.value.blackhole ? null : aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
}

resource "aws_flow_log" "tgw" {
  count = var.enable_flow_logs ? 1 : 0

  transit_gateway_id   = aws_ec2_transit_gateway.this.id
  log_destination_type = "s3"
  log_destination      = var.flow_log_bucket_arn
  traffic_type         = "ALL"

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw-flow-logs" })
}

resource "aws_ram_resource_share" "this" {
  count = length(var.share_with_principals) > 0 ? 1 : 0

  name                      = "${var.name_prefix}-tgw"
  allow_external_principals = false
  tags                      = var.tags
}

resource "aws_ram_resource_association" "tgw" {
  count = length(var.share_with_principals) > 0 ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(var.share_with_principals)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}
