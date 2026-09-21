# Direct Connect gateway -> Transit VIF -> Transit Gateway. The DX gateway is
# what makes one physical connection reachable from every VPC behind the TGW
# (and from other regions' TGWs) rather than one VPC at a time.

resource "aws_dx_gateway" "this" {
  name            = "${var.name_prefix}-dxgw"
  amazon_side_asn = var.amazon_side_asn
}

resource "aws_dx_transit_virtual_interface" "this" {
  for_each = var.virtual_interfaces

  connection_id  = var.connection_id
  dx_gateway_id  = aws_dx_gateway.this.id
  name           = "${var.name_prefix}-transit-vif-${each.key}"
  vlan           = each.value.vlan
  address_family = each.value.address_family
  bgp_asn        = each.value.bgp_asn
  mtu            = each.value.mtu

  amazon_address   = each.value.amazon_address
  customer_address = each.value.customer_address
  bgp_auth_key     = each.value.bgp_auth_key

  tags = var.tags

  # A transit VIF can't be created until the gateway exists and, on destroy,
  # must go before the gateway does; the implicit dependency covers both.
}

resource "aws_dx_gateway_association" "tgw" {
  dx_gateway_id         = aws_dx_gateway.this.id
  associated_gateway_id = var.transit_gateway_id

  allowed_prefixes = var.allowed_prefixes
}

# The DX attachment is created by AWS once the gateway association is active;
# it has to be discovered rather than declared.
data "aws_ec2_transit_gateway_dx_gateway_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  dx_gateway_id      = aws_dx_gateway.this.id

  depends_on = [aws_dx_gateway_association.tgw]
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.this.id
  transit_gateway_route_table_id = var.association_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.propagation_route_table_ids

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_dx_gateway_attachment.this.id
  transit_gateway_route_table_id = each.value
}

# ConnectionState: 1 = up, 0 = down. Missing data counts as breaching - a
# connection that stops reporting is not a healthy one.
resource "aws_cloudwatch_metric_alarm" "connection_down" {
  alarm_name          = "${var.name_prefix}-dx-${var.connection_id}-down"
  alarm_description   = "Direct Connect connection ${var.connection_id} is down. Traffic should be failing over to VPN. Runbook: ${var.runbook_url}"
  namespace           = "AWS/DX"
  metric_name         = "ConnectionState"
  dimensions          = { ConnectionId = var.connection_id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}
