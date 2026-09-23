# observability

Cross-service observability, not per-service: this is the module that turns
"we have a dashboard for the one RDS instance" into "we can correlate a
latency spike across five teams' services on the same cluster."

- **AWS Managed Prometheus (AMP)** - one workspace per environment, fed by
  the AWS managed scraper. The scraper runs outside the cluster and reaches it
  through ENIs in the private subnets, with read-only RBAC. It collects
  cAdvisor, API server, and any pod annotated `prometheus.io/scrape: "true"`.
- **Container Insights** - the `amazon-cloudwatch-observability` EKS add-on
  (IRSA, container logs off). It publishes the node metrics the CPU/memory
  alarms evaluate.
- Neither collector needs instance metadata from a pod, which matters because
  the nodes enforce IMDSv2 with a hop limit of 1.
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
| `cluster_arn` | EKS cluster ARN (scraper source) | `string` | n/a |
| `cluster_security_group_id` | EKS cluster security group, attached to the scraper ENIs | `string` | n/a |
| `private_subnet_ids` | Subnets for the scraper ENIs | `list(string)` | n/a |
| `oidc_provider_arn` / `oidc_provider_url` | From `eks-platform`, for the CloudWatch agent's IRSA role | `string` | n/a |
| `enable_metrics_collection` | Create the scraper and the CloudWatch Observability add-on | `bool` | `true` |
| `create_grafana_workspace` | Provision an AMG workspace | `bool` | `false` |
| `alert_email` | Email subscribed to the platform SNS topic | `string` | `""` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `amp_workspace_id` / `amp_workspace_endpoint` | AMP workspace |
| `grafana_workspace_endpoint` | AMG endpoint, or `null` if not created |
| `sns_topic_arn` | Platform alert topic (encrypted with the module's CMK, which CloudWatch alarms are allowed to use) |
