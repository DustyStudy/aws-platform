variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC that hosts the resolver endpoints (typically the shared-services / hub VPC)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the endpoint ENIs. Use at least two, in different AZs - a single-AZ resolver is a single point of failure for all DNS."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Resolver endpoints require at least two subnets."
  }
}

variable "onprem_cidrs" {
  description = "On-prem CIDRs allowed to query the inbound endpoint (53/tcp+udp)."
  type        = list(string)
  default     = []
}

variable "create_inbound" {
  description = "Create the inbound endpoint (on-prem resolves AWS private zones)."
  type        = bool
  default     = true
}

variable "create_outbound" {
  description = "Create the outbound endpoint (AWS resolves on-prem zones)."
  type        = bool
  default     = true
}

variable "forward_rules" {
  description = "Conditional-forwarding rules, keyed by short name. Each forwards a domain to on-prem DNS servers."
  type = map(object({
    domain_name = string
    target_ips  = list(string)
    target_port = optional(number, 53)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.forward_rules : length(v.target_ips) >= 2])
    error_message = "Each forward rule needs at least two target IPs so one on-prem DNS server can fail without breaking resolution."
  }
}

variable "associate_vpcs" {
  description = <<-EOT
    VPCs the forward rules (and query logging) apply to, as name => VPC ID.
    Include the endpoint VPC itself. Keys must be static strings; IDs may be
    apply-time values such as module.vpc.vpc_id.
  EOT
  type        = map(string)
  default     = {}
}

variable "share_rules_with_principals" {
  description = "Org / OU / account ARNs to share the forward rules with via RAM, so spoke accounts can associate their own VPCs."
  type        = list(string)
  default     = []
}

variable "enable_query_logging" {
  description = "Create a query log config and associate it with every VPC in associate_vpcs. A separate flag (rather than testing the ARN for null) so the ARN can be an apply-time value."
  type        = bool
  default     = false
}

variable "query_log_destination_arn" {
  description = "CloudWatch log group / S3 bucket / Firehose ARN for resolver query logs. Required when enable_query_logging is true."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
