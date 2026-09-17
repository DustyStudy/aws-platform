# bootstrap

Creates the resources every other stack depends on but can't create for
itself: the Terraform state buckets, the GitHub OIDC trust relationship, and
the three CI/CD roles (`plan`, `apply`, `tenant-onboard`).

This is the one stack in the repo that isn't applied from CI - there's no
role yet for CI to assume. Apply it once, locally, with an operator's own
(temporary, MFA'd) credentials:

```bash
cd bootstrap
terraform init
terraform apply \
  -var="github_org=your-github-org" \
  -var="platform_repo=your-github-org/aws-platform"
```

Then take the outputs and:

1. Put `plan_role_arn` / `apply_role_arn` / `tenant_onboard_role_arn` into the
   platform repo's Actions variables (not secrets - role ARNs aren't
   sensitive, and keeping them as `vars` makes the trust relationship visible
   in the workflow files instead of hidden in a secrets store).
2. Reference `tfstate_bucket_names` in each environment's `backend "s3"`
   block (`terraform/environments/<env>/main.tf`).

From here on, every apply goes through `terraform-plan.yml` /
`terraform-apply.yml` - nobody applies with personal credentials again,
including for changes to this bootstrap stack itself (it gets the same
plan/apply workflow treatment, scoped to `bootstrap/**`).
