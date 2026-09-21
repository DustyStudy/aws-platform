variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "pager_endpoint" {
  description = <<-EOT
    HTTPS endpoint that pages a human for SEV1/SEV2 - e.g. a PagerDuty Events
    API v2 CloudWatch integration URL (https://events.pagerduty.com/integration/<key>/enqueue)
    or an Opsgenie/Grafana OnCall equivalent. Treated as a secret: the key is
    embedded in the URL. null = SEV1/SEV2 topics are created with no subscriber
    (fail loud in review, not silently at 3am).
  EOT
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.pager_endpoint == null || can(regex("^https://", var.pager_endpoint))
    error_message = "pager_endpoint must be an https:// URL."
  }
}

variable "ticket_emails" {
  description = "Addresses (a ticketing-system inbox, a team list) for SEV3/SEV4. These never wake anyone up."
  type        = list(string)
  default     = []
}

variable "require_pager" {
  description = "When true, planning fails if pager_endpoint is null. Set this in prod. (A variable validation rather than a check block: check failures are only warnings, and this must be a hard error.)"
  type        = bool
  default     = false

  validation {
    condition     = !var.require_pager || var.pager_endpoint != null
    error_message = "require_pager is set but pager_endpoint is null - SEV1/SEV2 alerts would go nowhere."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
