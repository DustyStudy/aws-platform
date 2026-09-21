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

variable "github_subject_format" {
  description = <<-EOT
    Which OIDC `sub` claim format GitHub emits for the repos below.

    "immutable" (default): repo:<owner>@<owner-id>/<repo>@<repo-id>:<suffix> -
    what GitHub emits for repos with use_immutable_subject (the default for
    recently created repos). A trust condition written for the classic form never
    matches it, and nothing errors - the CI roles just can never be assumed. It
    also pins the numeric IDs, so a renamed, deleted or re-created repo cannot
    impersonate the platform repo.

    "classic": repo:<owner>/<repo>:<suffix>.

    Check yours: gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  type        = string
  default     = "immutable"

  validation {
    condition     = contains(["immutable", "classic"], var.github_subject_format)
    error_message = "github_subject_format must be \"immutable\" or \"classic\"."
  }

  validation {
    condition     = var.github_subject_format != "immutable" || (var.github_owner_id != "" && var.platform_repo_id != "")
    error_message = "github_subject_format is \"immutable\", so github_owner_id and platform_repo_id are required: gh api repos/<owner>/<repo> -q '.owner.id, .id' (or set github_subject_format = \"classic\" if use_immutable_subject is false)."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID (gh api repos/<owner>/<repo> -q .owner.id). Required for the immutable subject format."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be numeric."
  }
}

variable "platform_repo_id" {
  description = "Numeric GitHub repository ID of platform_repo (gh api repos/<owner>/<repo> -q .id). Required for the immutable subject format."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.platform_repo_id))
    error_message = "platform_repo_id must be numeric."
  }
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

  validation {
    condition     = var.github_subject_format != "immutable" || alltrue([for r in var.app_team_repos : split("/", r)[0] == split("/", var.platform_repo)[0]])
    error_message = "With the immutable subject format every app_team_repos entry must belong to the same owner as platform_repo (their owner is pinned by github_owner_id)."
  }
}
