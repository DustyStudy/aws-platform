variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "platform_admin_principal_arns" {
  description = "IAM principals (platform team) granted cluster-admin EKS access."
  type        = list(string)
  default     = []
}

variable "cluster_viewer_principal_arns" {
  description = "IAM principals granted cluster-wide read-only EKS access - set to the bootstrap plan role so CI plans and drift checks can refresh in-cluster resources."
  type        = list(string)
  default     = []
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API's public endpoint. Empty (the default) keeps the endpoint private-only."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "teams" {
  description = <<-EOT
    One entry per service onboarded to the platform. In practice this list
    grows via PRs opened by the reusable onboarding workflow
    (.github/workflows/onboard-service.yml), not by hand - see
    docs/ONBOARDING.md.
  EOT
  type = list(object({
    team_name               = string
    service_name            = string
    team_iam_principal_arns = optional(list(string), [])
    quota_cpu_requests      = optional(string)
    quota_cpu_limits        = optional(string)
    quota_memory_requests   = optional(string)
    quota_memory_limits     = optional(string)
  }))
  default = []
}
