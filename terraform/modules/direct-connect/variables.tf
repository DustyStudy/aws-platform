variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "connection_id" {
  description = <<-EOT
    ID of an existing Direct Connect connection (dxcon-...). The physical
    circuit is ordered through the AWS console / a partner and accepted
    out-of-band - it is not something Terraform can create - so this module
    starts from the connection and builds everything logical on top of it.
  EOT
  type        = string
}

variable "amazon_side_asn" {
  description = "ASN of the Direct Connect gateway. Must differ from the TGW ASN and the on-prem ASN."
  type        = number
  default     = 64513
}

variable "transit_gateway_id" {
  type = string
}

variable "association_route_table_id" {
  description = "TGW route table the DX attachment associates with (typically 'hybrid')."
  type        = string
}

variable "propagation_route_table_ids" {
  description = "TGW route tables that learn on-prem prefixes over the DX BGP session, as name => ID. Keys must be static; IDs may be apply-time values."
  type        = map(string)
  default     = {}
}

variable "allowed_prefixes" {
  description = "CIDRs the DX gateway advertises to on-prem. Transit VIFs allow at most 20 prefixes."
  type        = list(string)

  validation {
    condition     = length(var.allowed_prefixes) > 0 && length(var.allowed_prefixes) <= 20
    error_message = "allowed_prefixes must contain 1-20 CIDRs."
  }
}

variable "virtual_interfaces" {
  description = <<-EOT
    Transit VIFs, keyed by short name. Provision two on separate connections /
    locations for a resilient design; the module works with either.
    bgp_auth_key is optional - AWS generates one when null.
  EOT
  type = map(object({
    vlan             = number
    address_family   = optional(string, "ipv4")
    bgp_asn          = number
    amazon_address   = optional(string)
    customer_address = optional(string)
    bgp_auth_key     = optional(string)
    mtu              = optional(number, 8500)
  }))

  validation {
    condition     = alltrue([for k, v in var.virtual_interfaces : contains([1500, 8500], v.mtu)])
    error_message = "Transit VIF MTU must be 1500 or 8500."
  }
}

variable "alarm_actions" {
  type    = list(string)
  default = []
}

variable "runbook_url" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
