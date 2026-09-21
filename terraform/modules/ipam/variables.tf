variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "operating_regions" {
  description = "Regions IPAM manages. Must include every region in regional_pools."
  type        = list(string)
}

variable "top_level_cidr" {
  description = "The org-wide supernet, e.g. 10.0.0.0/8. Every regional pool is carved from it, so overlaps between regions/accounts are impossible by construction."
  type        = string

  validation {
    condition     = can(cidrhost(var.top_level_cidr, 0))
    error_message = "top_level_cidr must be a valid CIDR."
  }
}

variable "regional_pools" {
  description = <<-EOT
    One pool per region, keyed by short name. `cidr` must sit inside
    top_level_cidr. VPCs created against a pool get a netmask between
    allocation_min/max (default allocation_default), so a team can't claim a /8
    by accident.
  EOT
  type = map(object({
    region             = string
    cidr               = string
    allocation_default = optional(number, 20)
    allocation_min     = optional(number, 16)
    allocation_max     = optional(number, 24)
  }))

  validation {
    condition     = alltrue([for k, v in var.regional_pools : contains(var.operating_regions, v.region)])
    error_message = "Every regional pool's region must be listed in operating_regions."
  }

  validation {
    condition     = alltrue([for k, v in var.regional_pools : v.allocation_min <= v.allocation_default && v.allocation_default <= v.allocation_max])
    error_message = "allocation_min <= allocation_default <= allocation_max must hold (larger number = smaller network)."
  }
}

variable "share_with_principals" {
  description = "Org / OU ARNs the regional pools are shared with via RAM so member accounts can create VPCs from them."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
