# aws-platform

[![Terraform Plan](https://github.com/DustyStudy/aws-platform/actions/workflows/terraform-plan.yml/badge.svg)](https://github.com/DustyStudy/aws-platform/actions/workflows/terraform-plan.yml)
[![Terraform Apply](https://github.com/DustyStudy/aws-platform/actions/workflows/terraform-apply.yml/badge.svg)](https://github.com/DustyStudy/aws-platform/actions/workflows/terraform-apply.yml)
[![Drift Detection](https://github.com/DustyStudy/aws-platform/actions/workflows/drift-detection.yml/badge.svg)](https://github.com/DustyStudy/aws-platform/actions/workflows/drift-detection.yml)
[![Terraform >= 1.10](https://img.shields.io/badge/terraform-%3E%3D1.10-623CE4?logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform)
[![AWS](https://img.shields.io/badge/AWS-EKS%20%C2%B7%20IAM%20%C2%B7%20VPC-FF9900?logo=amazonwebservices&logoColor=white)](https://aws.amazon.com/eks/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A self-service AWS platform for teams running containerized services: one
shared EKS cluster, a golden-path Terraform module that gives a team a
namespace + ECR repo + scoped IAM identity in a single call, policy-as-code
guardrails that can't be bypassed by a single PR, and an OIDC-only CI/CD
trust model with no long-lived AWS credentials anywhere.

Companion to my other `aws-*` repos - this one is the platform-engineering
layer: how many teams share one cluster safely and onboard themselves onto
it, rather than [aws-orgseed](https://github.com/DustyStudy/aws-orgseed)'s
focus (bootstrapping the AWS accounts themselves).

## What's here

```
bootstrap/            # state buckets, GitHub OIDC provider, the 3 CI/CD roles - applied once, locally
terraform/
  modules/
    vpc/               # multi-AZ, public/private/data subnets, flow logs
    eks-platform/       # private-endpoint EKS, IRSA, SSM node access, Karpenter autoscaling
    tenant-namespace/  # the golden path: namespace + quota + network policy + ECR + IRSA role, per service
    observability/     # AWS Managed Prometheus + Grafana, CloudWatch alarms
  environments/
    dev/               # single NAT, small system node group, no Grafana workspace (cost-optimized)
    prod/              # HA NAT, larger system node group, Grafana workspace, tighter alarms
policy/conftest/       # OPA policies enforced in CI: tags, encryption, open security groups, tenant quota ceilings
.github/workflows/
  terraform-plan.yml            # PR gate: fmt/validate/tflint/tfsec/checkov + conftest, plan posted as a PR comment
  terraform-apply.yml           # main: auto-apply to dev, gated manual approval for prod
  drift-detection.yml           # daily scheduled plan, opens/updates an issue if state has drifted
  onboard-service.yml           # reusable workflow_call - an app team's own repo calls this to self-onboard
docs/
  ARCHITECTURE.md     # trust policy shapes, tenant isolation model, state layout
  ONBOARDING.md        # the self-service path, end to end, from an app team's point of view
examples/sample-service-onboarding/  # what the integration looks like from an app team's repo
```

## Design decisions

- **Self-service, but still reviewed.** The reusable onboarding workflow
  doesn't apply Terraform directly with a scoped role - it opens a PR
  against this repo. The same plan/policy gate every other change goes
  through runs against it, and a platform engineer still merges it. See
  [_Why onboarding opens a PR instead of applying directly_](docs/ARCHITECTURE.md#why-onboarding-opens-a-pr-instead-of-applying-directly).
- **No long-lived AWS credentials anywhere.** Every workflow assumes an IAM
  role via GitHub's OIDC provider. Three roles - `plan`, `apply`,
  `tenant-onboard` - each scoped to a different blast radius; the
  onboarding role's trust policy pins `job_workflow_ref` so only the exact
  reusable workflow file (not a caller-controlled workflow) can assume it.
- **Policy gates block the PR, they don't just warn.** tfsec, Checkov, and a
  set of platform-specific OPA policies (`policy/conftest/`) all run with a
  hard failure on a finding - including a policy that caps how much
  CPU/memory a single onboarding PR can request without a platform-team
  conversation first.
- **Tenant isolation is layered, not singular.** Each namespace is isolated
  by network policy (default-deny), IAM (an IRSA role scoped to that one
  `ServiceAccount` and that team's own secrets path), and Kubernetes RBAC
  (`AmazonEKSEditPolicy` scoped to one namespace) at the same time - not
  relying on any single boundary to hold.
- **Compute is pooled, not partitioned.** Tenant workloads share Karpenter
  node pools rather than getting per-tenant node groups; the isolation
  boundaries above are what actually matter, and per-tenant nodes would
  erase most of the point of pooling capacity in the first place.
- **EKS control plane has no public endpoint.** `endpoint_public_access =
  false`; access is via the private endpoint from within the VPC (or a
  bastion/VPN in a real deployment), and human `kubectl` access is granted
  per-principal through EKS access entries, not a shared kubeconfig.
- **Observability is cross-service by default.** AWS Managed Prometheus and
  Grafana give one place to correlate a latency spike across every team's
  service on the cluster, instead of a dashboard per service that nobody
  looks at together.

## Roadmap

- A cost-estimate step (Infracost) commented on onboarding PRs alongside the
  plan, so a team sees the cost of what they're requesting before it merges
- Per-tenant `NodePool`/`EC2NodeClass` overrides for teams with genuinely
  different compute needs (GPU, spot-averse workloads)
- IAM Identity Center group-to-namespace mapping for Grafana dashboards, so
  a team only sees its own service's data by default

## Deploying this

You'd need to run `bootstrap/` once with an operator's own credentials to
create the state buckets and OIDC roles, then wire their outputs into this
repo's Actions variables - see [`bootstrap/README.md`](bootstrap/README.md)
and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the trust policy
shapes. **This repo is intentionally not wired to a real AWS account** - it
exists to show the Terraform, the CI/CD trust model, and the policy gates,
not to run live infrastructure.

## License

[MIT](LICENSE)
