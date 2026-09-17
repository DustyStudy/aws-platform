terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }

  # Bucket created by bootstrap/ - see bootstrap/README.md.
  backend "s3" {
    bucket       = "aws-platform-tfstate-dev"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# The kubernetes/helm providers authenticate to the cluster this same apply
# creates - `exec` defers token generation to apply time instead of needing
# a provider-level credential up front, avoiding a chicken-egg problem on
# the very first `terraform apply`.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

locals {
  name_prefix = "platform-dev"
  common_tags = {
    Environment = "dev"
    Project     = "aws-platform"
    ManagedBy   = "terraform"
  }
  azs = ["us-east-1a", "us-east-1b"]
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix             = local.name_prefix
  vpc_cidr                = "10.40.0.0/16"
  azs                     = local.azs
  public_subnet_cidrs     = ["10.40.0.0/24", "10.40.1.0/24"]
  private_subnet_cidrs    = ["10.40.10.0/24", "10.40.11.0/24"]
  data_subnet_cidrs       = ["10.40.20.0/24", "10.40.21.0/24"]
  single_nat_gateway      = true # cost optimization for non-prod
  flow_log_retention_days = 365  # CKV_AWS_338 - even dev keeps rejected-traffic logs >= 1 year
  tags                    = local.common_tags
}

module "eks" {
  source = "../../modules/eks-platform"

  cluster_name       = "${local.name_prefix}-eks"
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_types = ["t3.medium"]
  system_node_min_size       = 1
  system_node_max_size       = 3
  system_node_desired_size   = 1

  karpenter_cpu_limit = "20"

  platform_admin_principal_arns = var.platform_admin_principal_arns

  tags = local.common_tags
}

module "observability" {
  source = "../../modules/observability"

  name_prefix       = local.name_prefix
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  create_grafana_workspace = false # dev doesn't need its own AMG workspace
  alert_email              = var.alert_email

  tags = local.common_tags
}

# --- Tenants -------------------------------------------------------------
# Declarative: adding a team/service here (typically via a PR opened by the
# onboarding workflow, see .github/workflows/onboard-service.yml) is the
# entire "give my service a home on the platform" step.

module "tenant" {
  source   = "../../modules/tenant-namespace"
  for_each = local.teams

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  ecr_kms_key_arn   = aws_kms_key.ecr.arn

  team_name               = each.value.team_name
  service_name            = each.value.service_name
  team_iam_principal_arns = try(each.value.team_iam_principal_arns, [])

  quota_cpu_requests    = try(each.value.quota_cpu_requests, "2")
  quota_cpu_limits      = try(each.value.quota_cpu_limits, "4")
  quota_memory_requests = try(each.value.quota_memory_requests, "4Gi")
  quota_memory_limits   = try(each.value.quota_memory_limits, "8Gi")

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "ecr" {
  description             = "${local.name_prefix} ECR image encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountRoot"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

locals {
  teams = { for t in var.teams : "${t.team_name}-${t.service_name}" => t }
}
