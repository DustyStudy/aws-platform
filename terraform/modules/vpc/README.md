# vpc

Multi-AZ VPC with a three-tier subnet layout: `public` (NAT/ALB),
`private` (EKS nodes - tagged for both the AWS Load Balancer Controller and
Karpenter discovery), and `data` (no route to the internet, for RDS and other
stateful services). Rejected traffic is logged to a KMS-encrypted CloudWatch
log group.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `vpc_cidr` | VPC CIDR block | `string` | n/a |
| `azs` | Availability zones | `list(string)` | n/a |
| `public_subnet_cidrs` | Public subnet CIDRs, one per AZ | `list(string)` | n/a |
| `private_subnet_cidrs` | Private subnet CIDRs, one per AZ | `list(string)` | n/a |
| `data_subnet_cidrs` | Data subnet CIDRs, one per AZ | `list(string)` | n/a |
| `single_nat_gateway` | Cost-optimize with one shared NAT | `bool` | `false` |
| `flow_log_retention_days` | CloudWatch retention for flow logs | `number` | `90` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `data_subnet_ids` | Data subnet IDs |
| `nat_gateway_ids` | NAT gateway IDs |
