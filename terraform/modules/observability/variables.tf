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

variable "install_adot_collector" {
  description = "Install the ADOT collector via Helm to scrape and remote_write into AMP. Set false if the caller manages the collector separately."
  type        = bool
  default     = true
}

variable "adot_chart_version" {
  description = "Version of the adot-exporter-for-eks-on-ec2 chart (https://aws-observability.github.io/aws-otel-helm-charts)."
  type        = string
  default     = "0.22.0"
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
