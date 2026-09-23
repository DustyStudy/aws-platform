# Architecture

## Layout

```
                          ┌─────────────────────────────────────────────────┐
                          │                  AWS account                    │
                          │                                                 │
 GitHub OIDC   ┌────────┐ │  ┌───────────────────────────────────────────┐  │
 (no static  ─▶│ plan/  │─┼─▶│  VPC (multi-AZ)                            │  │
  AWS keys)    │ apply/ │ │  │   public │ private │ data subnets          │  │
               │ tenant-│ │  │                                            │  │
               │ onboard│ │  │  ┌──────────────────────────────────────┐  │  │
               └────────┘ │  │  │  EKS (private endpoint)               │  │  │
                          │  │  │   system node group  (core add-ons)   │  │  │
                          │  │  │   Karpenter-managed  (tenant workloads)│  │  │
                          │  │  │                                        │  │  │
                          │  │  │   ns: svc-payments-invoice-api         │  │  │
                          │  │  │   ns: svc-scheduling-appointments-api  │  │  │
                          │  │  └──────────────────────────────────────┘  │  │
                          │  └───────────────────────────────────────────┘  │
                          │        │                        │               │
                          │  AWS Managed Prometheus   ECR (per tenant,       │
                          │  + AWS Managed Grafana    KMS-encrypted)         │
                          └─────────────────────────────────────────────────┘
```

## Trust model

Three IAM roles, each assumed only via GitHub OIDC (`sts:AssumeRoleWithWebIdentity`)
- no long-lived AWS access keys exist anywhere in this repo or its CI.

| Role | Assumable from | Can do |
|---|---|---|
| `github-actions-aws-platform-plan` | Any branch/PR in the platform repo | Read-only: `Describe*`/`List*`/`Get*` across the platform's services, `s3:GetObject` on the state buckets, and write access to `*.tflock` lock objects only (so `plan` can take the state lock). Read-only in-cluster access (`AmazonEKSAdminViewPolicy`) via an EKS access entry. Runs `terraform plan` and drift detection. |
| `github-actions-aws-platform-apply` | `main`, or the `dev`/`prod` GitHub Environments | Full read/write on platform resources (EC2/EKS/ECR/IAM roles prefixed `aws-platform-*`/`tenant-*`/KMS/state). Runs `terraform apply`. Prod additionally requires the `prod` Environment's manual-reviewer gate. |
| `github-actions-aws-platform-tenant-onboard` | Only the pinned `onboard-service.yml` reusable workflow (`job_workflow_ref` condition), called from an app-team repo | Read-only lookups used to validate an onboarding request. It does **not** apply Terraform - see below. |

The trust policy shapes (condensed):

```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Principal": { "Federated": "arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com" },
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<owner>@<owner-id>/aws-platform@<repo-id>:*" }
  }
}
```

GitHub emits this immutable `sub` form (numeric owner and repo IDs) for repos with
`use_immutable_subject`, not the classic `repo:<owner>/<repo>:*`; the IDs are pinned
exactly so a renamed or re-created repo can't impersonate the platform repo. See
`bootstrap/README.md`.

`tenant-onboard`'s trust policy additionally pins `job_workflow_ref` to the
exact reusable workflow file + ref, so an app team can call the golden path
but can't fork the workflow file in their own repo to grant themselves more
access.

### The GitHub Environments are part of the trust boundary

When a job declares `environment: prod`, GitHub sets its `sub` claim to
`...:environment:prod` **regardless of which branch it runs from**. The apply
role trusts that claim, so the Environment's own settings are what stop a
feature branch from assuming it:

| Environment | Required setting |
|---|---|
| `prod` | Required reviewers, deployment branches limited to `main` |
| `dev` | Deployment branches limited to `main` |

Without them, any collaborator could push a branch with a workflow that
declares `environment: prod` and get the apply role with no review. Check with
`gh api repos/<owner>/<repo>/environments/prod`.

## Reaching the private API endpoint

The EKS API endpoint is private by default. Terraform manages the in-cluster
layer too (Karpenter, the ADOT collector, tenant namespaces, quotas and
network policies), so whatever runs `terraform plan`/`apply` has to reach the
API server. There are two ways to do that:

- **Self-hosted runners inside the VPC** (or peered/VPN-connected to it). The
  endpoint stays private-only, and this is the production answer.
- **A CIDR-restricted public endpoint** - set `eks_public_access_cidrs`
  (`EKS_PUBLIC_ACCESS_CIDRS` repo variable in CI) to the runners' egress IPs.
  The API still requires IAM authentication plus an EKS access entry. GitHub-hosted
  runners don't have stable egress IPs, which is why this is opt-in and empty
  by default. The module refuses a public endpoint without an explicit
  allowlist.

## Why onboarding opens a PR instead of applying directly

An earlier design gave `tenant-onboard` write access scoped to `tenant-*`
resources and had it apply Terraform directly from the caller's workflow
run. That's a real access-boundary, but it still means an app team's repo
can push infrastructure changes with no human on the platform side ever
looking at the request. Routing through a PR means:

- The same plan/policy gate every other change goes through also runs here
  (fmt, validate, tflint, tfsec, Checkov, conftest - including the
  quota-ceiling policy).
- A platform engineer's merge is the actual authorization to create
  resources, not a scoped IAM policy standing in for one.
- The audit trail is a normal, reviewable git history instead of a stream of
  unattended applies.

The trade-off is latency (a PR needs a reviewer) for a meaningfully smaller
blast radius and a human checkpoint. For a platform with any real number of
tenants, that trade is worth it.

## Tenant isolation

Each `tenant-namespace` module call is isolated three ways simultaneously,
not just one:

1. **Network** - default-deny `NetworkPolicy`, explicit allow-list (own
   namespace, the ALB controller's namespace, DNS, HTTPS egress). Enforced by
   the VPC CNI's network policy agent, which `eks-platform` enables on the
   managed `vpc-cni` add-on. Without it, EKS accepts `NetworkPolicy` objects
   and silently ignores them.
2. **IAM** - an IRSA role trust-scoped to exactly that namespace's
   `ServiceAccount`, permitted to read only `secretsmanager` secrets under
   its own `<team>/<service>/*` path.
3. **Kubernetes RBAC** - the team's engineers get `AmazonEKSEditPolicy`
   scoped to just their namespace via an EKS access entry, not a
   cluster-admin kubeconfig.

Compute isolation is soft by design: workloads share the same Karpenter node
pool rather than getting per-tenant node groups, since the network/IAM/RBAC
boundaries above are what actually matter for a well-behaved multi-tenant
platform, and per-tenant node pools would erase most of the cost benefit of
pooling capacity in the first place. A tenant with genuinely different
compute requirements (GPU, bare-metal, strict physical isolation for
compliance) would get its own `NodePool`/`EC2NodeClass` rather than forcing
that shape onto every tenant.

## State layout

One S3 bucket per environment (`aws-platform-tfstate-dev` /
`-prod`), created once by `bootstrap/`, versioned, KMS-encrypted, TLS-only
bucket policy. Locking uses Terraform's native S3 lock (`use_lockfile =
true`, Terraform ≥ 1.10) - no separate DynamoDB lock table to provision or
pay for.

## Tearing an environment down

Karpenter-launched nodes aren't in Terraform state. Before `terraform destroy`,
delete the `NodePool` and wait for its nodes to drain, otherwise the instances
outlive the subnets and security groups the destroy is trying to remove:

```bash
kubectl delete nodepool default
kubectl wait --for=delete nodeclaims --all --timeout=10m
terraform destroy
```
