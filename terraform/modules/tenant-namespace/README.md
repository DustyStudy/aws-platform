# tenant-namespace

The self-service "golden path" module: one call provisions everything a team
needs to run one service on the shared platform, and nothing they don't get
by default.

Per call, this creates:

- A Kubernetes namespace (`svc-<team>-<service>`), one per service so two
  services owned by the same team never collide on a shared namespace
  resource.
- A `ResourceQuota` + `LimitRange` - hard ceilings on what the namespace can
  consume, and sane per-container defaults so a forgotten `resources:` block
  doesn't silently get unlimited burst.
- `NetworkPolicy` objects: default-deny, then explicit allows for
  same-namespace traffic, ingress from the shared ALB controller, DNS, and
  HTTPS egress. Nothing reaches another team's namespace by default.
- An ECR repository (`tenant-<team>-<service>`), immutable tags, scan-on-push,
  KMS-encrypted, with a lifecycle policy that expires untagged images after
  14 days and keeps the last 20 tagged ones.
- An IRSA IAM role trust-scoped to exactly this service's
  `ServiceAccount` (`system:serviceaccount:<namespace>:<service>`), permitted
  to read only `secretsmanager` secrets under its own `<team>/<service>/*`
  path - not the whole account's secrets, not another team's.
- Namespace-scoped human access: the team's engineers get
  `AmazonEKSEditPolicy` limited to their one namespace via an EKS access
  entry, not a cluster-admin kubeconfig.

This module is what `.github/workflows/onboard-service.yml` (the reusable
onboarding workflow) generates a call to when an app team requests a new
service - see [`docs/ONBOARDING.md`](../../../docs/ONBOARDING.md).

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | EKS cluster name | `string` | n/a |
| `oidc_provider_arn` / `oidc_provider_url` | From the `eks-platform` module, for IRSA | `string` | n/a |
| `team_name` | Owning team | `string` | n/a |
| `service_name` | Service name (also the ServiceAccount name) | `string` | n/a |
| `ingress_controller_namespace` | Namespace the ALB controller runs in | `string` | `"kube-system"` |
| `ecr_kms_key_arn` | KMS key for ECR image encryption | `string` | n/a |
| `team_iam_principal_arns` | IAM principals granted namespace-scoped access | `list(string)` | `[]` |
| `quota_cpu_requests` / `quota_cpu_limits` | Namespace CPU quota | `string` | `"4"` / `"8"` |
| `quota_memory_requests` / `quota_memory_limits` | Namespace memory quota | `string` | `"8Gi"` / `"16Gi"` |
| `quota_max_pods` | Max pods in namespace | `string` | `"20"` |
| `default_container_*` | Per-container defaults (`LimitRange`) | `string` | see `variables.tf` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `namespace` | Kubernetes namespace name |
| `ecr_repository_url` / `ecr_repository_name` | ECR repo for this service |
| `irsa_role_arn` | IAM role the service's pods assume |
| `service_account_name` | Kubernetes ServiceAccount to reference in Helm/manifests |
