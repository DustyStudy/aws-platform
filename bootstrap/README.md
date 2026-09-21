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
  -var="platform_repo=your-github-org/aws-platform" \
  -var="github_owner_id=<owner-id>" \
  -var="platform_repo_id=<repo-id>"
```

**The two IDs matter.** GitHub emits the OIDC `sub` claim as
`repo:<owner>@<owner-id>/<repo>@<repo-id>:<suffix>` for repos with
`use_immutable_subject` (the default for recently created repos), not the classic
`repo:<owner>/<repo>:<suffix>`. A trust condition written for the wrong form never
matches - nothing errors, the CI roles just can never be assumed. Look them up:

```bash
gh api repos/<owner>/<repo>/actions/oidc/customization/sub   # use_immutable_subject: true?
gh api repos/<owner>/<repo> -q '.owner.id, .id'               # owner ID, repo ID
```

`github_subject_format` defaults to `immutable` and refuses to plan without the IDs;
set it to `classic` only if `use_immutable_subject` is `false`. Pinning the exact IDs
also means a renamed, deleted or re-created repo can't impersonate the platform repo.
(App-team repos are matched by *owner* ID, since their repo IDs aren't known here;
`tenant-onboard`'s `job_workflow_ref` condition is what narrows who can call it.)

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
