# Central IP address management. Overlapping CIDRs are what make a Transit
# Gateway or VPN unusable later ("we can't route to that VPC, it has the same
# range as on-prem"), and retro-fixing one means rebuilding the VPC. IPAM makes
# the allocation a tracked, enforced step instead of a spreadsheet.

resource "aws_vpc_ipam" "this" {
  description = "${var.name_prefix} IPAM"
  tier        = "advanced" # required for cross-account / org-wide management

  dynamic "operating_regions" {
    for_each = toset(var.operating_regions)
    content {
      region_name = operating_regions.value
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ipam" })
}

resource "aws_vpc_ipam_pool" "top" {
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  address_family = "ipv4"
  description    = "${var.name_prefix} top-level pool"

  tags = merge(var.tags, { Name = "${var.name_prefix}-ipam-top" })
}

resource "aws_vpc_ipam_pool_cidr" "top" {
  ipam_pool_id = aws_vpc_ipam_pool.top.id
  cidr         = var.top_level_cidr
}

resource "aws_vpc_ipam_pool" "regional" {
  for_each = var.regional_pools

  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.top.id
  locale              = each.value.region
  address_family      = "ipv4"
  description         = "${var.name_prefix} ${each.key}"

  auto_import                       = false
  allocation_default_netmask_length = each.value.allocation_default
  allocation_min_netmask_length     = each.value.allocation_min
  allocation_max_netmask_length     = each.value.allocation_max

  tags = merge(var.tags, { Name = "${var.name_prefix}-ipam-${each.key}" })

  depends_on = [aws_vpc_ipam_pool_cidr.top]
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = var.regional_pools

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.key].id
  cidr         = each.value.cidr
}

resource "aws_ram_resource_share" "pools" {
  count = length(var.share_with_principals) > 0 ? 1 : 0

  name                      = "${var.name_prefix}-ipam-pools"
  allow_external_principals = false
  tags                      = var.tags
}

resource "aws_ram_resource_association" "pools" {
  for_each = length(var.share_with_principals) > 0 ? aws_vpc_ipam_pool.regional : {}

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.pools[0].arn
}

resource "aws_ram_principal_association" "pools" {
  for_each = toset(var.share_with_principals)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.pools[0].arn
}
