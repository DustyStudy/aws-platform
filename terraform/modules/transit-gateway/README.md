# transit-gateway

Hub of a hub-and-spoke network. Creates the TGW, named route tables, VPC
attachments, per-attachment route-table association/propagation, optional
static routes, TGW flow logs, and an optional RAM share.

**Segmentation is explicit.** The TGW's default association and propagation
are disabled, so no attachment is reachable from anything until a route table
says so. Each attachment names the table it associates with and the tables
that learn its CIDR - "prod can't reach dev" is the absence of a propagation,
not a firewall rule someone has to remember.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `amazon_side_asn` | Private BGP ASN for the AWS side | `number` | `64512` |
| `route_tables` | TGW route table names | `list(string)` | `["spokes","shared","hybrid"]` |
| `vpc_attachments` | VPCs to attach (`vpc_id`, `subnet_ids`, `route_table`, `propagate_to`, `appliance_mode`) | `map(object)` | `{}` |
| `static_routes` | Static routes, e.g. default route to an inspection VPC | `map(object)` | `{}` |
| `share_with_principals` | Org/OU/account ARNs to share the TGW with via RAM | `list(string)` | `[]` |
| `enable_flow_logs` / `flow_log_bucket_arn` | TGW flow logs to S3 | `bool` / `string` | `false` / `null` |
| `tags` | Common tags | `map(string)` | `{}` |

| Output | Description |
|---|---|
| `transit_gateway_id` / `transit_gateway_arn` | The TGW |
| `route_table_ids` | Route table name -> ID |
| `vpc_attachment_ids` | Attachment key -> ID |

Pair with [`site-to-site-vpn`](../site-to-site-vpn) and
[`direct-connect`](../direct-connect) for on-prem connectivity. See
`examples/hybrid-network`.

Tests: `terraform test` (mocked provider - no AWS account needed).

## Why some inputs are maps and `enable_*` flags

Terraform must know every `for_each` key / `count` at plan time. IDs and ARNs
from other modules are unknown on a first deploy, so anything that identifies
a resource instance is a **static-keyed map** (`name => apply-time ID`) and
optional features are toggled by a **boolean**, not by testing an ARN for
`null`. `examples/hybrid-network/tests/plan.tftest.hcl` plans the whole
composition with unknown IDs to keep this true.
