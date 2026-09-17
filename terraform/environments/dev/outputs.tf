output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "amp_workspace_endpoint" {
  value = module.observability.amp_workspace_endpoint
}

output "tenant_ecr_repository_urls" {
  value = { for k, t in module.tenant : k => t.ecr_repository_url }
}

output "tenant_irsa_role_arns" {
  value = { for k, t in module.tenant : k => t.irsa_role_arn }
}
