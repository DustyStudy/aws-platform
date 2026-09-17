# Contributing

This is a personal reference/portfolio repository, but issues and PRs are
welcome - typos, bugs in the Terraform, a policy that's wrong, a workflow
that doesn't actually do what its comment claims.

## Working on the Terraform

```bash
make fmt              # terraform fmt -recursive
make validate ENV=dev # init (no backend) + validate
make lint              # tflint, repo-wide
```

There's no live AWS account behind this repo, so `make plan` will only get
you as far as a provider auth error unless you point it at your own account
and credentials - that's expected. `terraform fmt`, `validate`, and `lint`
don't need any AWS access and are what CI actually gates on for the
security-scan job.

## Policy changes

Changes to `policy/conftest/*.rego` - especially raising a ceiling like
`tenant_quota_ceiling.rego`'s CPU/memory limits - are exactly the kind of
change this repo's design intentionally routes through a normal PR review
(see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)). Explain the "why" in
the PR description, not just the diff.

## Commit style

Short, imperative, prefixed by what changed (`fix:`, `feat:`, `ci:`,
`docs:`) - see the existing git log for the convention.
