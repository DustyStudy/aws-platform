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
| `github-actions-aws-platform-plan` | Any branch/PR in the platform repo | Read-only: `Describe*`/`List*`/`Get*` across the platform's services, plus `s3:GetObject` on the state buckets. Runs `terraform plan`. |
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
    "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:your-github-org/aws-platform:*" }
  }
}
```

`tenant-onboard`'s trust policy additionally pins `job_workflow_ref` to the
exact reusable workflow file + ref, so an app team can call the golden path
but can't fork the workflow file in their own repo to grant themselves more
access.

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
   namespace, the ALB controller's namespace, DNS, HTTPS egress).
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
