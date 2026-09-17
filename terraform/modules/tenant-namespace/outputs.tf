output "namespace" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.this.name
}

output "irsa_role_arn" {
  value = aws_iam_role.service.arn
}

output "service_account_name" {
  value = kubernetes_service_account.this.metadata[0].name
}
