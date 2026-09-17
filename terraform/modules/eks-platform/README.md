# eks-platform

The shared cluster every tenant namespace runs on. Private API endpoint by
default, IRSA enabled, node access via SSM (no SSH/bastion), secrets
envelope-encrypted with a dedicated KMS key.

Two capacity shapes:

- **System node group** - small, static, tainted `platform-system=true` so
  only core add-ons (CoreDNS, the AWS Load Balancer Controller, Karpenter
  itself) schedule there. The platform team sizes this once and rarely
  touches it again.
- **Karpenter** - provisions and right-sizes nodes for everything else
  (tenant workloads) on demand, consolidating underutilized capacity
  automatically. See `karpenter.tf`.

Human access is granted through EKS access entries scoped per-principal, not
by sharing a cluster-admin kubeconfig - platform admins get
`AmazonEKSClusterAdminPolicy` at cluster scope; app teams get
`AmazonEKSEditPolicy` scoped to just their namespace via the
`tenant-namespace` module.

| Name | Description | Type | Default |
|---|---|---|---|
| `cluster_name` | Cluster name | `string` | n/a |
| `kubernetes_version` | EKS Kubernetes version | `string` | `"1.31"` |
| `vpc_id` | VPC to deploy into | `string` | n/a |
| `private_subnet_ids` | Subnets for nodes and the private endpoint | `list(string)` | n/a |
| `endpoint_public_access` | Expose the API server publicly (CIDR-restricted) | `bool` | `false` |
| `public_access_cidrs` | Allowed CIDRs if the above is true | `list(string)` | `[]` |
| `system_node_instance_types` | System node group instance types | `list(string)` | `["t3.medium"]` |
| `system_node_min_size` / `max_size` / `desired_size` | System node group scaling | `number` | `2` / `4` / `2` |
| `karpenter_chart_version` | Karpenter Helm chart version | `string` | `"1.1.1"` |
| `karpenter_cpu_limit` | Cluster-wide vCPU ceiling for Karpenter-provisioned nodes | `string` | `"100"` |
| `platform_admin_principal_arns` | IAM principals granted cluster-admin | `list(string)` | `[]` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `cluster_name`, `cluster_endpoint`, `cluster_arn` | Cluster identifiers |
| `cluster_ca_certificate` | Base64 CA cert (sensitive) |
| `cluster_security_group_id` | Control plane security group |
| `oidc_provider_arn`, `oidc_provider_url` | For IRSA roles in dependent modules |
| `node_role_arn` | Shared node IAM role (system + Karpenter-launched nodes) |
