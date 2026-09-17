# Security

This is a portfolio/reference repository - the Terraform here is not wired
to a live AWS account (see the README), so there's no production deployment
to compromise. That said, the code is meant to be a credible starting point
for a real platform, so security issues in it are worth reporting properly.

## Reporting a vulnerability

If you find a security issue in this repo's Terraform, CI/CD workflows, or
policy definitions - a privilege-escalation path in the IAM trust policies,
a gap in the tenant isolation model, a workflow that could be tricked into
running untrusted code - please open a private report via
[GitHub Security Advisories](https://github.com/DustyStudy/aws-platform/security/advisories/new)
rather than a public issue.

## Scope

In scope: the Terraform modules, the bootstrap IAM trust policies, the
GitHub Actions workflows (including the reusable onboarding workflow's
trust boundary), and the OPA policies in `policy/conftest/`.

Out of scope: anything that would only matter once this were actually
deployed to a real AWS account with real traffic (e.g. rate limiting,
WAF rules) - this repo doesn't run a live service.
