variable "project_name" {
  description = "Short name used to prefix all bootstrap resources (state buckets, IAM roles)."
  type        = string
  default     = "aws-platform"
}

variable "aws_region" {
  description = "Region the state buckets and OIDC provider live in."
  type        = string
  default     = "us-east-1"
}

variable "environments" {
  description = "Environments to create a state bucket for."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "github_org" {
  description = "GitHub organization or user that owns the platform and app-team repos."
  type        = string
  default     = "your-github-org"
}

variable "platform_repo" {
  description = "Repo (org/name) allowed to assume the plan/apply roles."
  type        = string
  default     = "your-github-org/aws-platform"
}

variable "onboarding_workflow_path" {
  description = <<-EOT
    Path to the reusable onboarding workflow, used to scope the tenant-onboard
    role's trust policy to workflow_ref so only that specific pinned workflow
    (not just any workflow in the repo) can assume it.
  EOT
  type        = string
  default     = ".github/workflows/onboard-service.yml"
}

variable "app_team_repos" {
  description = "App-team repos (org/name) allowed to call the reusable onboarding workflow and, transitively, assume the tenant-onboard role."
  type        = list(string)
  default     = ["your-github-org/*"]
}
