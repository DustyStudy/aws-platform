# Live validation - 2026-09-23

This repo was deployed end to end into a real AWS account, exercised, fixed
where it broke, and torn down. This page records what was run, what failed,
what changed, and the evidence. Every fix is in
[PR #8](https://github.com/DustyStudy/aws-platform/pull/8), one commit per
area.

**Result:** after the fixes, every component below was deployed and verified
live, through the same OIDC roles and GitHub Actions workflows the repo ships.
Before the fixes, a first `terraform apply` could not create an EKS cluster.

## Environment

| | |
|---|---|
| AWS | Member account `2645····3329` ("Dev") of an AWS Organizations org, `us-east-1` |
| Operator | IAM Identity Center `AdministratorAccess` session (bootstrap and teardown only, as `bootstrap/README.md` prescribes) |
| CI | GitHub Actions in this repo, assuming the bootstrap roles via GitHub OIDC (immutable `sub` claim) |
| Tooling | Terraform 1.15.8 locally / 1.10.5 in CI, AWS provider 5.100, kubectl 1.35, conftest 0.70, tfsec 1.28, Checkov, tflint 0.64 |
| Deployed | `bootstrap/` → `terraform/environments/dev` (VPC, EKS 1.35, Karpenter, two tenants, AMP, alarms) + a live harness for the hybrid-networking modules |

Test-only settings, not repo defaults: the dev EKS endpoint was public to
`0.0.0.0/0` so GitHub-hosted runners could reach it (IAM authentication and
access entries still required - see
[ARCHITECTURE.md](ARCHITECTURE.md#reaching-the-private-api-endpoint)), and the
CI apply was dispatched from the PR branch before the `dev`/`prod` Environments
were restricted to `main`.

## What was verified

### Static gates (the PR checks)

| Check | Result |
|---|---|
| `terraform fmt` / `validate` (every root and module) | pass |
| Unit tests (`terraform test`, mocked providers) | 33 pass: 8 modules, `bootstrap/`, and the hybrid example (now run in CI), including 4 new `eks-platform` tests |
| Change-gate unit tests | 18 pass |
| Policy unit tests (`conftest verify`, new) | 7 pass |
| tfsec (now blocking - see defect 9) | 0 findings; remaining wildcards carry an inline justification |
| Checkov | 306 passed, 0 failed |
| tflint | clean |
| conftest against the real dev plan | 12/12 pass |

### Bootstrap and CI trust (live)

| What | How it was checked | Result |
|---|---|---|
| State buckets, KMS key, OIDC provider, 3 roles | `terraform apply` in `bootstrap/` (19 resources) | created |
| Plan role via OIDC | [PR plan run](https://github.com/DustyStudy/aws-platform/actions/runs/35883489240) - `terraform plan` for dev (live state, incl. in-cluster refresh) and prod, conftest on both | pass |
| Plan role takes the S3 state lock and waits for it | same run; the dev plan waited for a concurrent apply's lock instead of failing | pass |
| Apply role via OIDC | [Terraform Apply, dev](https://github.com/DustyStudy/aws-platform/actions/runs/35883481492) - the role rolled out the quota, network policy, SNS and observability fixes to the live cluster | pass (first attempt failed - defect 14) |
| Drift detection | [Drift Detection](https://github.com/DustyStudy/aws-platform/actions/runs/35890963874) against the clean-room environment: dev `No changes. Your infrastructure matches the configuration.`; prod skipped with `prod has no Terraform state (never applied)` | pass (earlier runs failed on defects 20-21; their issues #9-#11 were closed with an explanation) |

### EKS platform (live)

| What | Evidence | Result |
|---|---|---|
| Cluster | EKS 1.35, `ACTIVE`, API auth mode, secrets envelope-encrypted with a CMK | pass |
| Add-ons | `vpc-cni` (network policy on), `coredns`, `kube-proxy`, `amazon-cloudwatch-observability` - all `ACTIVE` | pass |
| System node group | tainted `platform-system`; CoreDNS, Karpenter, CNI and CloudWatch agent all Running on it | pass |
| Node hardening | IMDSv2 required, hop limit 1, on managed and Karpenter nodes | pass |
| Karpenter | pending tenant pods → `NodeClaim` launched a spot `c5.large` in ~50s; consolidation later replaced it with a cheaper `c7i-flex.large`; deleting the `NodePool` drained every Karpenter node | pass |
| Tenant golden path | two tenants → namespaces, quotas, limit ranges, 5 network policies each, immutable KMS-encrypted scan-on-push ECR repos, IRSA roles | pass |

### Tenant isolation (live, after fixes)

Run from `probe` pods inside each tenant namespace:

```
same namespace  (payments probe -> payments web):     200
cross namespace (payments probe -> scheduling web):   BLOCKED (timeout)
cross namespace (scheduling probe -> payments web):   BLOCKED (timeout)
HTTPS egress    (payments probe -> sts.amazonaws.com): 302
plain HTTP egress (payments probe -> example.com:80): BLOCKED (timeout)

payments pod identity: assumed-role/tenant-payments-invoice-api/...
payments reads payments/invoice-api/db:        payments/invoice-api/db
payments reads scheduling/appointments-api/db: AccessDeniedException

pods "greedy" is forbidden: exceeded quota: svc-payments-invoice-api-quota,
  requested: limits.cpu=3,requests.cpu=3, used: limits.cpu=1250m,requests.cpu=600m,
  limited: limits.cpu=4,requests.cpu=2
```

### Observability (live, after fixes)

| What | Before | After |
|---|---|---|
| Series in AMP | 0 | ~69,000 (`cadvisor`, `kubernetes-apiservers`) via the managed scraper |
| Container Insights metric streams for the cluster | 0 | 1,974 (incl. `node_cpu_utilization`, what the node alarms evaluate) |
| Alarm → `platform-alerts` SNS topic | `Failed to execute action ... CloudWatch Alarms does not have authorization to access the SNS topic encryption key.` | `Successfully executed action arn:aws:sns:...:platform-dev-platform-alerts` |

### Hybrid networking modules (live harness)

The `examples/hybrid-network` composition minus Direct Connect (which needs a
physical circuit), applied as a temporary harness (127 resources), verified,
and destroyed.

| Module | Verified | Result |
|---|---|---|
| `transit-gateway` | default association/propagation off; `spokes` table sees only shared-services, `shared` sees only prod, `hybrid` (VPN) sees both | pass |
| `site-to-site-vpn` | BGP (not static), IKEv2 only, AES-256/AES-256-GCM, DH 14/20, tunnel logging on; associated to `hybrid`, propagating to `spokes`/`shared` | pass |
| `site-to-site-vpn` alarm → `incident-routing` | tunnels down (no peer) → `tunnel-down` went to ALARM → delivered through the CMK-encrypted `sev2` topic to a subscriber, runbook link in the message | pass |
| `route53-resolver` | inbound + outbound endpoints `OPERATIONAL` (2 IPs each), forward rule `corp.example.com` → 2 targets, associated with both VPCs | pass |
| `load-balancer` | internal ALB, 443 `ELBSecurityPolicy-TLS13-1-2-2021-06`, 80 redirect-only, access logs on, invalid headers dropped, desync `strictest` | pass |
| `ipam` | top-level pool + regional pool `10.0.0.0/12` provisioned, default netmask /20 | pass |
| `incident-routing` | 4 severity topics on a dedicated CMK, pager DLQ + `pager-delivery-failed` alarm | pass |

## Defects found and fixed

| # | Defect | How it showed up live | Fix |
|---|---|---|---|
| 1 | EKS cluster SG description contained `<->`; EC2 rejects `<`/`>` | first `terraform apply` failed: `InvalidParameterValue: Invalid security group description` - **no cluster could ever be created** | plain-text description |
| 2 | Every initial node is tainted, CoreDNS didn't tolerate it, and Karpenter needs DNS to launch untainted nodes | found in review; would deadlock a fresh cluster | CoreDNS/vpc-cni/kube-proxy as managed add-ons; CoreDNS tolerates the taint (live: CoreDNS `ACTIVE` in 14s) |
| 3 | VPC CNI's network policy agent was off, so `NetworkPolicy` objects were accepted and ignored | tenant "default-deny" would not have been enforced | `enableNetworkPolicy` on the managed `vpc-cni` add-on |
| 4 | `kubernetes_manifest` for NodePool/EC2NodeClass needs the cluster and CRDs at plan time; the NodeClass lacked the required `amiSelectorTerms` and selected a security group tag nothing carried | a first plan can't succeed; Karpenter would find no SG | small local Helm chart; `al2023@latest`, the real cluster SG, the Terraform-managed instance profile, IMDSv2 hop 1 |
| 5 | Kubernetes 1.31 is in extended support (6x control-plane price); Karpenter 1.1.1 can't run anything newer | `describe-cluster-versions` | 1.35 + Karpenter 1.14.0; Karpenter IAM aligned with upstream (scoped deletes, SSM `/aws/service/*`, exact Spot SLR ARN) |
| 6 | Karpenter chart runs 2 replicas, one per node, but only on system nodes - dev has one | one Karpenter pod `Pending` forever | replicas = `min(2, system_node_min_size)` |
| 7 | `try(each.value.quota_cpu_requests, "2")` returns `null` for an unset `optional()` attribute, and the null is silently dropped | live quota was `{"pods":"20"}` only; a 3-CPU pod was admitted | `coalesce(...)` in the environments, `nullable = false` in the module |
| 8 | default-deny covers egress but `allow-same-namespace` only allowed ingress | a tenant's own pods couldn't reach each other (`000`) | allow both directions (live: `200`) |
| 9 | `tfsec-action` passes `--soft-fail` whenever `soft_fail` is non-empty - including `soft_fail: false` | the "blocking" tfsec gate had 27 unreported findings on `main` | drop the input; fix or justify each finding |
| 10 | Quota ceiling policy only checked limits that were present, and only in `Gi` | would pass defect 7's unlimited quota | fail closed on missing limits; parse `m`/`Mi`/`Gi`/`Ti`; unit tests |
| 11 | `platform-alerts` SNS topic used `alias/aws/sns`, which CloudWatch alarms can't use | `Failed to execute action ... does not have authorization to access the SNS topic encryption key` - **no platform alarm could ever notify** | module CMK with a `cloudwatch.amazonaws.com` grant |
| 12 | ADOT chart version `0.19.2` doesn't exist; its values used keys the chart ignores; IRSA trusted the wrong ServiceAccount | chart pinned to a non-existent release | (superseded by 13) |
| 13 | A pod-network collector can't read IMDS on hop-limit-1 nodes | ADOT ran but logged `Failed to get ec2 metadata ... 401` / `Failed to detect cluster name. Drop all metrics`; AMP had 0 series | AWS managed Prometheus scraper + `amazon-cloudwatch-observability` add-on (IRSA); neither needs IMDS from a pod |
| 14 | Terraform declared an EKS access entry for the scraper's service-linked role | CI apply: `The caller is not allowed to modify access entries with a principalArn value of a Service Linked Role` | removed - AMP creates it (with `AmazonPrometheusScraperPolicy`) itself |
| 15 | Plan role had only `s3:GetObject` on state, so `plan` couldn't take the native S3 lock; it and the apply role lacked many read/tag/grant/add-on/SLR permissions a first plan/apply needs | first-plan/first-apply failures | plan role may write `*.tflock` only; apply role gains scoped `kms:CreateGrant` (`GrantIsForAWSResource`), add-on, tagging, and service-linked-role permissions for named services |
| 16 | A PR plan colliding with an apply failed on the lock immediately; matrix `fail-fast` then cancelled the passing prod plan; and the next steps failed on the missing plan file, burying the real error | PR check failures during this test | `-lock-timeout=30m` on plan/apply/drift (a first apply runs ~25m); `fail-fast: false`; post-plan steps only run after a successful plan |
| 17 | The apply role trusts `environment:dev`/`environment:prod`, but `prod` didn't exist and `dev` allowed any branch | any branch declaring `environment: prod` could have assumed the apply role with no reviewer | `prod` created with a required reviewer; both Environments restricted to `main` (documented in ARCHITECTURE.md) |
| 18 | `onboard-service.yml` checked out `your-github-org/aws-platform` | placeholder | points at this repo |
| 19 | Destroy ordering: nothing tied in-cluster resources to the add-ons and IAM they need while being deleted | first `terraform destroy` hung: tenant NetworkPolicies kept the VPC CNI's finalizer and the EC2NodeClass kept Karpenter's, after Terraform had already removed `vpc-cni`/`kube-proxy` and Karpenter's IAM policy | Karpenter's release depends on them; `cluster_name` (read by every in-cluster consumer) depends on the networking add-ons. Verified by the clean-room run below |
| 22 | Destroy ordering, one layer down: EKS only referenced `vpc_id`/subnet IDs, so Terraform deleted the NAT gateway and private routes first | clean-room destroy: Karpenter couldn't reach the EC2 API (`dial tcp ...:443: i/o timeout`) to terminate its nodes, and the `karpenter-defaults` uninstall timed out | the VPC module's `private_subnet_ids` output depends on the NAT routes, so everything in those subnets is destroyed while egress still exists. Verified by the clean-room run below |
| 20 | Creating a managed scraper makes AMP tag its workspace `AMPAgentlessScraper`; Terraform stripped it on every apply | Drift Detection reported `~ tags { - "AMPAgentlessScraper" }` on a freshly applied environment - it would have opened a drift issue every day | `ignore_changes` on that one service-owned tag (live: `No changes`) |
| 21 | Drift detection treated a never-applied environment as drifted, and its "is it deployed" check couldn't work: `setup-terraform`'s wrapper adds output to stdout, so `terraform state list` was never empty | prod leg failed and opened a drift issue | check with `terraform-bin`; skip with a notice (live: prod skipped, run green) |

## Clean-room run of the final code

With every fix in place, the dev environment was destroyed and rebuilt from
nothing, to show that a first apply works in one pass with no manual steps:

| Step | Result |
|---|---|
| `terraform apply` from empty state | `Apply complete! Resources: 106 added, 0 changed, 0 destroyed.` - first attempt, no errors |
| Smoke test | 4 add-ons `ACTIVE`, no pod outside `Running`, Karpenter provisioned spot `c7a.medium` nodes for a test deployment, tenant quotas carrying CPU/memory limits |
| CI against it | PR plan (dev + prod) and Drift Detection green |
| `terraform destroy` with 3 Karpenter nodes and a workload still running, no manual drain or finalizer edits | CLEANROOM_DESTROY_PLACEHOLDER |

## Not covered live

- **Direct Connect** - needs a physical connection; covered by its mocked unit tests and the hybrid example's plan test.
- **Self-service onboarding workflow** (`onboard-service.yml`) and the **`tenant-onboard` role's** trust - need a separate app-team repo and a PAT; the role was created and its trust policy reviewed, but no call was made through it.
- **ServiceNow change gate** - no ServiceNow instance; covered by its 18 unit tests.
- **Prod environment and Managed Grafana** - planned by CI (plan role, conftest pass) but not applied.

## Teardown

TEARDOWN_PLACEHOLDER
