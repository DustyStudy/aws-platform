# Onboarding a service to the platform

This is the path an application team follows to get a namespace, an ECR
repository, and a scoped IAM role for a new service - without ever needing
standing access to this repo's Terraform state.

## 1. Add the onboarding call to your repo

In your own service repo, add a workflow that calls the reusable
`onboard-service.yml` workflow published by this repo. See
[`examples/sample-service-onboarding`](../examples/sample-service-onboarding)
for a full example.

```yaml
# .github/workflows/onboard.yml, in your service's repo
name: Request platform onboarding
on:
  workflow_dispatch: {}

jobs:
  onboard:
    uses: your-github-org/aws-platform/.github/workflows/onboard-service.yml@main
    with:
      environment: dev
      team_name: payments
      service_name: invoice-api
      team_iam_principal_arns: '["arn:aws:iam::111111111111:role/team-payments"]'
    secrets:
      PLATFORM_REPO_TOKEN: ${{ secrets.PLATFORM_REPO_TOKEN }}
```

`PLATFORM_REPO_TOKEN` is a fine-grained PAT scoped to `contents:write` +
`pull-requests:write` on `aws-platform` only - ask the platform team for one
scoped to your repo.

## 2. Run it

`workflow_dispatch` (or push, if you'd rather trigger it from a manifest
file changing) runs the workflow, which:

1. Checks out `aws-platform`.
2. Adds or updates your team/service entry in
   `terraform/environments/<environment>/teams.auto.tfvars.json`.
3. Opens a PR against `aws-platform` with that change.

You do not get write access to `aws-platform`'s Terraform state at any
point in this flow.

## 3. The PR goes through the normal gate

`terraform-plan.yml` runs against the PR like any other: `terraform fmt`,
`validate`, `tflint`, `tfsec`, Checkov, and the conftest policy gate -
including `tenant_quota_ceiling.rego`, which caps how much CPU/memory you
can request without a platform-team conversation first. The plan is posted
as a PR comment so you can see exactly what will be created before anyone
approves it.

## 4. A platform engineer merges it

Merging triggers `terraform-apply.yml`. For `dev` this applies automatically;
for `prod` it additionally waits on the `prod` GitHub Environment's
required-reviewer gate.

## 5. You get your service's identity back

Once applied, the environment's Terraform outputs include your service's
ECR repository URL and IRSA role ARN
(`tenant_ecr_repository_urls["<team>-<service>"]`,
`tenant_irsa_role_arns["<team>-<service>"]`). Wire those into your own
service repo's deploy workflow: push images to the ECR repo, deploy a Helm
chart/manifest into your `svc-<team>-<service>` namespace using a
`ServiceAccount` named `<service_name>` (already annotated with the IRSA
role by the `tenant-namespace` module).

From here, your service's own CI/CD is entirely your repo's concern - the
platform's job ends at "you have a namespace, a place to push images, and an
IAM identity that can read your own secrets."
