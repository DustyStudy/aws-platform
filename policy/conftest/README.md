# policy/conftest

OPA/Rego policies enforced as a hard gate in `terraform-plan.yml`, on top of
tfsec and Checkov. Where tfsec/Checkov catch generic misconfigurations,
these encode this platform's own rules - things a generic scanner has no way
to know, like "no team's ResourceQuota may exceed the platform ceiling."

Run locally against a plan:

```bash
cd terraform/environments/dev
terraform init && terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
conftest test plan.json -p ../../../policy/conftest
```

| Policy | Denies |
|---|---|
| `require_tags.rego` | Taggable resources missing `Project` / `Environment` / `ManagedBy` |
| `deny_open_security_groups.rego` | Ingress open to `0.0.0.0/0` on anything other than 80/443 |
| `deny_unencrypted_storage.rego` | ECR repos or S3 buckets not encrypted with a customer-managed KMS key |
| `deny_public_s3.rego` | S3 buckets without a fully-locked-down public access block |
| `tenant_quota_ceiling.rego` | A tenant `ResourceQuota` requesting more than the platform-wide CPU/memory ceiling |

Raising a ceiling (e.g. `tenant_quota_ceiling.rego`) means changing this
directory, which goes through the same PR review as everything else - a
single onboarding PR can't quietly grant itself more than the platform
allows.
