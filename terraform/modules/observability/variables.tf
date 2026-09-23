variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets the managed Prometheus scraper puts its ENIs in - the cluster's private subnets."
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "The EKS cluster security group, attached to the scraper's ENIs so it can reach the API server and nodes."
  type        = string
}

variable "enable_metrics_collection" {
  description = "Create the managed Prometheus scraper and the CloudWatch Observability add-on. Set false if the caller runs its own collectors."
  type        = bool
  default     = true
}

variable "create_grafana_workspace" {
  description = "AWS Managed Grafana workspaces bill hourly per workspace - disabled by default for the dev environment."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address subscribed to platform alerts. Empty string skips the subscription."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
