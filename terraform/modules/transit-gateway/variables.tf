variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "amazon_side_asn" {
  description = "Private ASN for the AWS side of BGP sessions. Must not collide with the on-prem ASN."
  type        = number
  default     = 64512

  validation {
    condition     = (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) || (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    error_message = "amazon_side_asn must be a private ASN (64512-65534 or 4200000000-4294967294)."
  }
}

variable "route_tables" {
  description = <<-EOT
    Names of TGW route tables to create. Association/propagation defaults are
    disabled on the TGW itself, so every attachment must name the table it
    associates with - this is what makes segmentation (e.g. prod spokes can't
    reach dev spokes) an explicit choice instead of an accident.
  EOT
  type        = list(string)
  default     = ["spokes", "shared", "hybrid"]
}

variable "vpc_attachments" {
  description = <<-EOT
    VPCs to attach, keyed by a short name. route_table is the TGW route table
    the attachment associates with; propagate_to lists the TGW route tables that
    learn this VPC's CIDR. appliance_mode keeps flows symmetric through an
    inspection VPC.
  EOT
  type = map(object({
    vpc_id         = string
    subnet_ids     = list(string)
    route_table    = string
    propagate_to   = optional(list(string), [])
    appliance_mode = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.vpc_attachments : contains(var.route_tables, v.route_table)])
    error_message = "Every vpc_attachments[*].route_table must be one of var.route_tables."
  }

  validation {
    condition     = alltrue([for k, v in var.vpc_attachments : alltrue([for t in v.propagate_to : contains(var.route_tables, t)])])
    error_message = "Every vpc_attachments[*].propagate_to entry must be one of var.route_tables."
  }
}

variable "static_routes" {
  description = "Static TGW routes (e.g. a default route pointing at an inspection VPC attachment)."
  type = map(object({
    route_table    = string
    cidr           = string
    attachment_key = optional(string) # key in vpc_attachments; unused when blackhole = true
    blackhole      = optional(bool, false)
  }))
  default = {}
}

variable "share_with_principals" {
  description = "Org / OU / account ARNs to share the TGW with via RAM. Empty = not shared."
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Create TGW flow logs to flow_log_bucket_arn. A separate flag so the bucket ARN can be an apply-time value."
  type        = bool
  default     = false
}

variable "flow_log_bucket_arn" {
  description = "S3 bucket ARN for TGW flow logs. Required when enable_flow_logs is true."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
