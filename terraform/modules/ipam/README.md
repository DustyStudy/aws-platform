# ipam

Central IPv4 allocation with AWS VPC IPAM. One org-wide supernet, carved into
one pool per region, RAM-shared to the org so member accounts allocate VPC
CIDRs *from the pool* instead of choosing them.

Why it matters for hybrid networking: overlapping CIDRs are what make a
Transit Gateway or VPN unusable later, and the only fix is rebuilding the VPC.
With IPAM the range is allocated (and tracked, and non-overlapping by
construction) before the VPC exists. Pool netmask bounds also stop a team
claiming a /8 by accident.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `operating_regions` | Regions IPAM manages | `list(string)` | n/a |
| `top_level_cidr` | Org supernet, e.g. `10.0.0.0/8` | `string` | n/a |
| `regional_pools` | Per-region pool: `region`, `cidr`, `allocation_{default,min,max}` | `map(object)` | n/a |
| `share_with_principals` | Org/OU ARNs to share pools with | `list(string)` | `[]` |

| Output | Description |
|---|---|
| `regional_pool_ids` | Pool key -> ID; pass as `ipv4_ipam_pool_id` on `aws_vpc` |

The `vpc` module in this repo takes an explicit `vpc_cidr` today. Use the
allocation IPAM hands back (or a `aws_vpc_ipam_preview_next_cidr`) as that
input; switching the module to `ipv4_ipam_pool_id` directly is a natural
follow-up once IPAM is in use.

`tier = "advanced"` is required for org-wide management and is billed per
active IP - see the AWS VPC IPAM pricing page before enabling.
