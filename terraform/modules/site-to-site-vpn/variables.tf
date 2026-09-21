variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "transit_gateway_id" {
  description = "TGW the VPN attachments terminate on."
  type        = string
}

variable "association_route_table_id" {
  description = "TGW route table each VPN attachment associates with (typically the 'hybrid' table)."
  type        = string
}

variable "propagation_route_table_ids" {
  description = <<-EOT
    TGW route tables that learn on-prem prefixes over BGP from these VPNs, as
    name => route table ID. Keys must be static strings (they identify the
    Terraform resources); the IDs may be apply-time values such as
    module.tgw.route_table_ids["spokes"].
  EOT
  type        = map(string)
  default     = {}
}

variable "customer_gateways" {
  description = "On-prem VPN devices, keyed by short name. bgp_asn must differ from the TGW's amazon_side_asn."
  type = map(object({
    ip_address = string
    bgp_asn    = number
  }))

  validation {
    condition     = alltrue([for k, v in var.customer_gateways : can(cidrhost("${v.ip_address}/32", 0))])
    error_message = "customer_gateways[*].ip_address must be a valid IPv4 address."
  }
}

variable "connections" {
  description = <<-EOT
    One entry per Site-to-Site VPN connection (each gives two tunnels).
    Pre-shared keys are left to AWS to generate unless supplied; either way they
    land in state (marked sensitive), so the state bucket must be encrypted and
    tightly scoped - which the bootstrap/ stack already does.
  EOT
  type = map(object({
    customer_gateway    = string # key in customer_gateways
    tunnel1_inside_cidr = optional(string)
    tunnel2_inside_cidr = optional(string)
  }))
}

variable "log_retention_days" {
  type    = number
  default = 365 # CKV_AWS_338
}

variable "log_kms_key_arn" {
  description = "KMS key for the tunnel log group. null = CloudWatch-managed encryption."
  type        = string
  default     = null
}

variable "alarm_actions" {
  description = "SNS topic ARNs notified when a tunnel goes down (see the incident-routing module)."
  type        = list(string)
  default     = []
}

variable "runbook_url" {
  description = "Link included in the alarm description so whoever is paged lands on the runbook, not a search box."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
