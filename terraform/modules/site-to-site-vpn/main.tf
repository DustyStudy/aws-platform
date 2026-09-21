# Two-tunnel, BGP-based Site-to-Site VPN into a Transit Gateway. Static routing
# is deliberately not offered: BGP is what lets a failed tunnel/device withdraw
# its routes instead of black-holing traffic.

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  bgp_asn    = each.value.bgp_asn
  ip_address = each.value.ip_address
  type       = "ipsec.1"

  tags = merge(var.tags, { Name = "${var.name_prefix}-cgw-${each.key}" })
}

resource "aws_cloudwatch_log_group" "tunnel" {
  for_each = var.connections

  name              = "/aws/vpn/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn
  tags              = var.tags
}

resource "aws_vpn_connection" "this" {
  for_each = var.connections

  customer_gateway_id = aws_customer_gateway.this[each.value.customer_gateway].id
  transit_gateway_id  = var.transit_gateway_id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_inside_cidr = each.value.tunnel1_inside_cidr
  tunnel2_inside_cidr = each.value.tunnel2_inside_cidr

  # IKEv2 + AES-256 + SHA-256 + DH group 14/20 only. AWS defaults still allow
  # IKEv1, AES-128 and SHA-1; pinning the sets makes the negotiated suite
  # auditable instead of "whatever both sides happen to agree on".
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256", "SHA2-384"]
  tunnel1_phase1_dh_group_numbers      = [14, 20]
  tunnel1_phase2_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256", "SHA2-384"]
  tunnel1_phase2_dh_group_numbers      = [14, 20]
  tunnel1_dpd_timeout_action           = "restart"
  tunnel1_startup_action               = "start"

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256", "SHA2-384"]
  tunnel2_phase1_dh_group_numbers      = [14, 20]
  tunnel2_phase2_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256", "SHA2-384"]
  tunnel2_phase2_dh_group_numbers      = [14, 20]
  tunnel2_dpd_timeout_action           = "restart"
  tunnel2_startup_action               = "start"

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel[each.key].arn
      log_output_format = "json"
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel[each.key].arn
      log_output_format = "json"
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpn-${each.key}" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.connections

  transit_gateway_attachment_id  = aws_vpn_connection.this[each.key].transit_gateway_attachment_id
  transit_gateway_route_table_id = var.association_route_table_id
}

locals {
  propagations = merge([
    for k, _ in var.connections : {
      for name, rt in var.propagation_route_table_ids : "${k}:${name}" => { connection = k, route_table_id = rt }
    }
  ]...)
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = local.propagations

  transit_gateway_attachment_id  = aws_vpn_connection.this[each.value.connection].transit_gateway_attachment_id
  transit_gateway_route_table_id = each.value.route_table_id
}

# TunnelState is 1 when up, 0 when down. Alarm on the *minimum* across the
# tunnels of a connection: a single dead tunnel means redundancy is already
# gone, which is what should page - not the total outage that follows.
resource "aws_cloudwatch_metric_alarm" "tunnel_down" {
  for_each = var.connections

  alarm_name          = "${var.name_prefix}-vpn-${each.key}-tunnel-down"
  alarm_description   = "At least one IPsec tunnel on ${each.key} is down - redundancy lost. Runbook: ${var.runbook_url}"
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  dimensions          = { VpnId = aws_vpn_connection.this[each.key].id }
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
