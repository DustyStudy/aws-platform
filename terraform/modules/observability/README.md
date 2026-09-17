# observability

Cross-service observability, not per-service: this is the module that turns
"we have a dashboard for the one RDS instance" into "we can correlate a
latency spike across five teams' services on the same cluster."

- **AWS Managed Prometheus (AMP)** - one workspace per environment. An ADOT
  collector runs in-cluster (IRSA-scoped to `aps:RemoteWrite` on just this
  workspace) and remote_writes cluster + tenant workload metrics into it.
- **AWS Managed Grafana (AMG)** - service-managed permissions, IAM Identity
  Center authentication, wired to both the AMP workspace and CloudWatch as
  data sources. Off by default in dev (`create_grafana_workspace = false`)
  since AMG workspaces bill hourly regardless of use.
- **CloudWatch alarms independent of the AMP/Grafana path** - node CPU/memory
  (via Container Insights) and a log-metric-filter-based alarm on Karpenter
  provisioning failures, so there's still a signal if the metrics pipeline
  itself is the thing that's broken.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names | `string` | n/a |
| `cluster_name` | EKS cluster name (for alarm dimensions/log group) | `string` | n/a |
| `oidc_provider_arn` / `oidc_provider_url` | From `eks-platform`, for the ADOT collector's IRSA role | `string` | n/a |
| `install_adot_collector` | Install the ADOT collector via Helm | `bool` | `true` |
| `adot_chart_version` | ADOT Helm chart version | `string` | `"0.19.2"` |
| `create_grafana_workspace` | Provision an AMG workspace | `bool` | `false` |
| `alert_email` | Email subscribed to the platform SNS topic | `string` | `""` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `amp_workspace_id` / `amp_workspace_endpoint` | AMP workspace |
| `grafana_workspace_endpoint` | AMG endpoint, or `null` if not created |
| `sns_topic_arn` | Platform alert topic |
