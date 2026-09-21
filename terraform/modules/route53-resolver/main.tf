# Hybrid DNS: inbound endpoint lets on-prem resolve AWS private hosted zones,
# outbound endpoint + forward rules let AWS resolve on-prem zones. Rules are
# shareable via RAM so each spoke account doesn't stand up its own endpoints
# (they bill per ENI-hour).

resource "aws_security_group" "inbound" {
  #checkov:skip=CKV2_AWS_5:attached to the resolver endpoint below via security_group_ids; the check can't follow the count index
  count = var.create_inbound ? 1 : 0

  name_prefix = "${var.name_prefix}-r53-inbound-"
  description = "Route 53 Resolver inbound endpoint - DNS from on-prem"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-r53-inbound" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "inbound_udp" {
  for_each = var.create_inbound ? toset(var.onprem_cidrs) : toset([])

  security_group_id = aws_security_group.inbound[0].id
  description       = "DNS/UDP from on-prem"
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_ingress_rule" "inbound_tcp" {
  for_each = var.create_inbound ? toset(var.onprem_cidrs) : toset([])

  security_group_id = aws_security_group.inbound[0].id
  description       = "DNS/TCP from on-prem"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}

resource "aws_security_group" "outbound" {
  #checkov:skip=CKV2_AWS_5:attached to the resolver endpoint below via security_group_ids; the check can't follow the count index
  count = var.create_outbound ? 1 : 0

  name_prefix = "${var.name_prefix}-r53-outbound-"
  description = "Route 53 Resolver outbound endpoint - DNS to on-prem"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-r53-outbound" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  forward_targets = distinct(flatten([for k, v in var.forward_rules : [for ip in v.target_ips : "${ip}/32"]]))
}

resource "aws_vpc_security_group_egress_rule" "outbound_udp" {
  for_each = var.create_outbound ? toset(local.forward_targets) : toset([])

  security_group_id = aws_security_group.outbound[0].id
  description       = "DNS/UDP to on-prem resolver"
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "outbound_tcp" {
  for_each = var.create_outbound ? toset(local.forward_targets) : toset([])

  security_group_id = aws_security_group.outbound[0].id
  description       = "DNS/TCP to on-prem resolver"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.create_inbound ? 1 : 0

  name               = "${var.name_prefix}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.inbound[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.create_outbound ? 1 : 0

  name               = "${var.name_prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.outbound[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = var.tags
}

resource "aws_route53_resolver_rule" "forward" {
  for_each = var.create_outbound ? var.forward_rules : {}

  name                 = "${var.name_prefix}-fwd-${each.key}"
  domain_name          = each.value.domain_name
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = each.value.target_ips
    content {
      ip   = target_ip.value
      port = each.value.target_port
    }
  }

  tags = var.tags
}

locals {
  rule_associations = var.create_outbound ? merge([
    for rk, _ in var.forward_rules : {
      for vk, v in var.associate_vpcs : "${rk}:${vk}" => { rule = rk, vpc_id = v }
    }
  ]...) : {}
}

resource "aws_route53_resolver_rule_association" "this" {
  for_each = local.rule_associations

  resolver_rule_id = aws_route53_resolver_rule.forward[each.value.rule].id
  vpc_id           = each.value.vpc_id
}

resource "aws_ram_resource_share" "rules" {
  count = length(var.share_rules_with_principals) > 0 && var.create_outbound ? 1 : 0

  name                      = "${var.name_prefix}-resolver-rules"
  allow_external_principals = false
  tags                      = var.tags
}

resource "aws_ram_resource_association" "rules" {
  for_each = length(var.share_rules_with_principals) > 0 && var.create_outbound ? aws_route53_resolver_rule.forward : {}

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.rules[0].arn
}

resource "aws_ram_principal_association" "rules" {
  for_each = length(var.share_rules_with_principals) > 0 && var.create_outbound ? toset(var.share_rules_with_principals) : toset([])

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.rules[0].arn
}

# Query logs are the first thing you want when "DNS is broken" - they show
# whether queries are arriving, which rule matched, and what came back.
resource "aws_route53_resolver_query_log_config" "this" {
  count = var.enable_query_logging ? 1 : 0

  name            = "${var.name_prefix}-query-logs"
  destination_arn = var.query_log_destination_arn
  tags            = var.tags
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  for_each = var.enable_query_logging ? var.associate_vpcs : {}

  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this[0].id
  resource_id                  = each.value
}
