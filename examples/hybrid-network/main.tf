# Reference composition: a hub-and-spoke network with on-prem connectivity.
#
#   on-prem --(Direct Connect, primary)--+
#                                        +-- Transit Gateway -- spokes (prod, dev)
#   on-prem --(Site-to-Site VPN, backup)-+                  \-- shared-services VPC (DNS)
#
# Not applied by CI - it needs a real Direct Connect connection and a real
# customer gateway IP. It exists so `terraform validate` proves the modules'
# inputs and outputs actually fit together.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.65"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name = "hybrid"
  azs  = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
}

# --- Address plan -------------------------------------------------------------
module "ipam" {
  source = "../../terraform/modules/ipam"

  name_prefix       = local.name
  operating_regions = [var.aws_region]
  top_level_cidr    = "10.0.0.0/8"
  regional_pools = {
    primary = { region = var.aws_region, cidr = "10.0.0.0/12" }
  }
  share_with_principals = var.org_arns
}

# --- Alert routing --------------------------------------------------------------
module "incident_routing" {
  source = "../../terraform/modules/incident-routing"

  name_prefix    = local.name
  pager_endpoint = var.pager_endpoint
  ticket_emails  = var.ticket_emails
  require_pager  = true
}

# --- VPCs -----------------------------------------------------------------------
module "vpc_prod" {
  source = "../../terraform/modules/vpc"

  name_prefix          = "${local.name}-prod"
  vpc_cidr             = "10.0.0.0/20"
  azs                  = local.azs
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.4.0/22", "10.0.8.0/22", "10.0.12.0/22"]
  data_subnet_cidrs    = ["10.0.3.0/26", "10.0.3.64/26", "10.0.3.128/26"]
}

module "vpc_shared" {
  source = "../../terraform/modules/vpc"

  name_prefix          = "${local.name}-shared"
  vpc_cidr             = "10.0.16.0/22"
  azs                  = local.azs
  public_subnet_cidrs  = ["10.0.16.0/26", "10.0.16.64/26", "10.0.16.128/26"]
  private_subnet_cidrs = ["10.0.17.0/26", "10.0.17.64/26", "10.0.17.128/26"]
  data_subnet_cidrs    = ["10.0.18.0/26", "10.0.18.64/26", "10.0.18.128/26"]
}

# --- Hub --------------------------------------------------------------------------
module "tgw" {
  source = "../../terraform/modules/transit-gateway"

  name_prefix = local.name

  vpc_attachments = {
    prod = {
      vpc_id       = module.vpc_prod.vpc_id
      subnet_ids   = module.vpc_prod.private_subnet_ids
      route_table  = "spokes"
      propagate_to = ["hybrid", "shared"] # on-prem and shared-services can reach prod
    }
    shared = {
      vpc_id       = module.vpc_shared.vpc_id
      subnet_ids   = module.vpc_shared.private_subnet_ids
      route_table  = "shared"
      propagate_to = ["spokes", "hybrid"]
    }
  }

  share_with_principals = var.org_arns
}

# --- On-prem connectivity -----------------------------------------------------------
module "direct_connect" {
  source = "../../terraform/modules/direct-connect"

  name_prefix                 = local.name
  connection_id               = var.dx_connection_id
  transit_gateway_id          = module.tgw.transit_gateway_id
  association_route_table_id  = module.tgw.route_table_ids["hybrid"]
  propagation_route_table_ids = { spokes = module.tgw.route_table_ids["spokes"], shared = module.tgw.route_table_ids["shared"] }
  allowed_prefixes            = ["10.0.0.0/12"]

  virtual_interfaces = {
    primary = { vlan = 100, bgp_asn = var.onprem_asn }
  }

  alarm_actions = [module.incident_routing.topic_arns["sev2"]]
  runbook_url   = "${var.runbook_base_url}/direct-connect-down.md"
}

module "vpn_backup" {
  source = "../../terraform/modules/site-to-site-vpn"

  name_prefix                 = local.name
  transit_gateway_id          = module.tgw.transit_gateway_id
  association_route_table_id  = module.tgw.route_table_ids["hybrid"]
  propagation_route_table_ids = { spokes = module.tgw.route_table_ids["spokes"], shared = module.tgw.route_table_ids["shared"] }

  customer_gateways = {
    dc1 = { ip_address = var.customer_gateway_ip, bgp_asn = var.onprem_asn }
  }
  connections = {
    dc1 = { customer_gateway = "dc1" }
  }

  alarm_actions = [module.incident_routing.topic_arns["sev2"]]
  runbook_url   = "${var.runbook_base_url}/vpn-tunnel-down.md"
}

# --- Hybrid DNS -----------------------------------------------------------------------
module "dns" {
  source = "../../terraform/modules/route53-resolver"

  name_prefix  = local.name
  vpc_id       = module.vpc_shared.vpc_id
  subnet_ids   = module.vpc_shared.private_subnet_ids
  onprem_cidrs = var.onprem_cidrs

  forward_rules = {
    corp = { domain_name = var.onprem_domain, target_ips = var.onprem_dns_ips }
  }
  associate_vpcs              = { shared = module.vpc_shared.vpc_id, prod = module.vpc_prod.vpc_id }
  share_rules_with_principals = var.org_arns
}

# --- Ingress ------------------------------------------------------------------------------
module "alb" {
  source = "../../terraform/modules/load-balancer"

  name_prefix           = "${local.name}-prod"
  vpc_id                = module.vpc_prod.vpc_id
  subnet_ids            = module.vpc_prod.private_subnet_ids
  certificate_arn       = var.certificate_arn
  access_logs_bucket    = var.access_logs_bucket
  allowed_ingress_cidrs = var.onprem_cidrs # internal ALB, reachable from on-prem over the TGW

  target_groups = {
    web = { port = 8080 }
  }

  alarm_actions = [module.incident_routing.topic_arns["sev2"]]
  runbook_url   = "${var.runbook_base_url}/alb-5xx-spike.md"
}
