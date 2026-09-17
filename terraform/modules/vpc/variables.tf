variable "name_prefix" {
  description = "Prefix applied to all resource names/tags in this module."
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "data_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cost-optimized, single point of failure). false = one per AZ."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  type    = number
  default = 365 # CKV_AWS_338
}

variable "tags" {
  type    = map(string)
  default = {}
}
