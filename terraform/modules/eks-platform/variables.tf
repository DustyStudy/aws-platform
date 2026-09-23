variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep it in standard support - extended support bills the control plane at 6x - and within karpenter_chart_version's compatibility range."
  type        = string
  default     = "1.35"
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
  description = "CIDRs allowed to reach the public API endpoint when endpoint_public_access = true. Must be set explicitly - an empty list would make EKS default to 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
    error_message = "endpoint_public_access = true requires an explicit public_access_cidrs allowlist (EKS treats an empty list as 0.0.0.0/0)."
  }
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
  description = "Karpenter Helm chart version. Must support kubernetes_version (Karpenter >= 1.9 for Kubernetes 1.35) - see Karpenter's compatibility matrix."
  type        = string
  default     = "1.14.0"
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

variable "cluster_viewer_principal_arns" {
  description = "IAM principals granted cluster-wide read-only access (AmazonEKSAdminViewPolicy) - CI's plan/drift role, so terraform plan can refresh in-cluster resources."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
