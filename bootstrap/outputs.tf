output "tfstate_bucket_names" {
  description = "State bucket name per environment - feed into each environment's backend block."
  value       = { for env, b in aws_s3_bucket.tfstate : env => b.id }
}

output "tfstate_kms_key_arn" {
  value = aws_kms_key.tfstate.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}

output "tenant_onboard_role_arn" {
  value = aws_iam_role.tenant_onboard.arn
}
