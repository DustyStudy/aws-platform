variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the API server publicly (CIDR-restricted). Kept false by default - access the private endpoint from within the VPC or over a VPN/bastion in a real deployment."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "system_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "system_node_min_size" {
  type    = number
  default = 2
}

variable "system_node_max_size" {
  type    = number
  default = 4
}

variable "system_node_desired_size" {
  type    = number
  default = 2
}

variable "karpenter_chart_version" {
  type    = string
  default = "1.1.1"
}

variable "karpenter_cpu_limit" {
  description = "Total vCPU ceiling across all Karpenter-provisioned nodes - a coarse cost/blast-radius guardrail at the cluster level."
  type        = string
  default     = "100"
}

variable "platform_admin_principal_arns" {
  description = "IAM principals granted cluster-admin access (platform team). App-team access is scoped per-namespace by the tenant-namespace module instead."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
