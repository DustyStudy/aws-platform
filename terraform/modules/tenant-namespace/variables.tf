variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "team_name" {
  description = "Owning team, e.g. \"payments\". Used in the namespace name, ECR repo name, and IAM role name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.team_name))
    error_message = "team_name must be lowercase alphanumeric/hyphens, starting with a letter, 2-21 chars."
  }
}

variable "service_name" {
  description = "Service within the team, e.g. \"invoice-api\". Also used as the Kubernetes ServiceAccount name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service_name))
    error_message = "service_name must be lowercase alphanumeric/hyphens, starting with a letter, 2-31 chars."
  }
}

variable "ingress_controller_namespace" {
  description = "Namespace the AWS Load Balancer Controller runs in, allowed to reach pods in this namespace."
  type        = string
  default     = "kube-system"
}

variable "ecr_kms_key_arn" {
  type = string
}

variable "team_iam_principal_arns" {
  description = "IAM principals (users/roles) granted namespace-scoped EKS access (AmazonEKSEditPolicy) for this service's engineers."
  type        = list(string)
  default     = []
}

# --- Resource ceilings -------------------------------------------------
# These are the platform's defaults for a small service; the policy gate in
# policy/conftest/tenant_quota_ceiling.rego caps how high a caller can push
# them without a platform-team review.

variable "quota_cpu_requests" {
  type = string
  # null (an unset optional attribute from the caller) means "use the
  # default", not "no limit" - a null hard entry is silently dropped.
  nullable = false
  default  = "4"
}

variable "quota_cpu_limits" {
  type = string
  # null (an unset optional attribute from the caller) means "use the
  # default", not "no limit" - a null hard entry is silently dropped.
  nullable = false
  default  = "8"
}

variable "quota_memory_requests" {
  type = string
  # null (an unset optional attribute from the caller) means "use the
  # default", not "no limit" - a null hard entry is silently dropped.
  nullable = false
  default  = "8Gi"
}

variable "quota_memory_limits" {
  type = string
  # null (an unset optional attribute from the caller) means "use the
  # default", not "no limit" - a null hard entry is silently dropped.
  nullable = false
  default  = "16Gi"
}

variable "quota_max_pods" {
  type = string
  # null (an unset optional attribute from the caller) means "use the
  # default", not "no limit" - a null hard entry is silently dropped.
  nullable = false
  default  = "20"
}

variable "default_container_cpu_request" {
  type    = string
  default = "100m"
}

variable "default_container_cpu_limit" {
  type    = string
  default = "500m"
}

variable "default_container_memory_request" {
  type    = string
  default = "256Mi"
}

variable "default_container_memory_limit" {
  type    = string
  default = "512Mi"
}

variable "tags" {
  type    = map(string)
  default = {}
}
