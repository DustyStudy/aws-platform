variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "org_arns" {
  description = "Org / OU ARNs to RAM-share the TGW, IPAM pools and resolver rules with. Empty = not shared."
  type        = list(string)
  default     = []
}

variable "pager_endpoint" {
  type      = string
  sensitive = true
}

variable "ticket_emails" {
  type = list(string)
}

variable "dx_connection_id" {
  description = "Existing Direct Connect connection (dxcon-...)."
  type        = string
}

variable "customer_gateway_ip" {
  description = "Public IP of the on-prem VPN device."
  type        = string
}

variable "onprem_asn" {
  type    = number
  default = 65010
}

variable "onprem_cidrs" {
  type = list(string)
}

variable "onprem_domain" {
  type    = string
  default = "corp.example.com"
}

variable "onprem_dns_ips" {
  type = list(string)
}

variable "certificate_arn" {
  type = string
}

variable "access_logs_bucket" {
  type = string
}

variable "runbook_base_url" {
  type    = string
  default = "https://github.com/DustyStudy/aws-platform/blob/main/docs/incident-response/runbooks"
}
