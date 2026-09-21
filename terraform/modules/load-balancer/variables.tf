variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "type" {
  description = "application (ALB, L7) or network (NLB, L4)."
  type        = string
  default     = "application"

  validation {
    condition     = contains(["application", "network"], var.type)
    error_message = "type must be \"application\" or \"network\"."
  }
}

variable "internal" {
  description = "Internal load balancers are the default; an internet-facing one has to be asked for."
  type        = bool
  default     = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the LB nodes - at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A load balancer needs subnets in at least two AZs."
  }
}

variable "certificate_arn" {
  description = "ACM certificate for the TLS listener. Required - there is no plaintext-listener option."
  type        = string
}

variable "ssl_policy" {
  description = "TLS 1.3-preferred policy with a TLS 1.2 floor. FIPS-mandated environments should use an ELBSecurityPolicy-TLS13-*-FIPS-* policy."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on 443. Ignored for NLBs (they have no security group unless one is attached)."
  type        = list(string)
  default     = []
}

variable "target_groups" {
  description = "Target groups keyed by short name. The first key (alphabetically) is the listener's default action unless default_target_group is set."
  type = map(object({
    port        = number
    protocol    = optional(string) # defaults: HTTP for ALB, TCP for NLB
    target_type = optional(string, "ip")
    health_check = optional(object({
      path                = optional(string, "/healthz")
      matcher             = optional(string, "200-299")
      interval            = optional(number, 15)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 2)
    }), {})
  }))
}

variable "default_target_group" {
  description = "Key in target_groups the listener forwards to by default. null = first key."
  type        = string
  default     = null
}

variable "target_security_groups" {
  description = "Security groups of the targets, as name => SG ID (static keys, apply-time IDs are fine). The ALB is allowed egress to them on each target group's port, and nothing else."
  type        = map(string)
  default     = {}
}

variable "access_logs_bucket" {
  description = "S3 bucket for access logs (must already grant the regional ELB log-delivery principal PutObject). Required: access logs are the first thing asked for in a 5xx incident."
  type        = string
}

variable "access_logs_prefix" {
  type    = string
  default = null
}

variable "associate_waf" {
  description = "Associate waf_acl_arn with the ALB. A separate flag so the ACL ARN can be an apply-time value."
  type        = bool
  default     = false
}

variable "waf_acl_arn" {
  description = "WAFv2 web ACL to associate (ALB only). Used when associate_waf is true."
  type        = string
  default     = null
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "idle_timeout" {
  type    = number
  default = 60
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
