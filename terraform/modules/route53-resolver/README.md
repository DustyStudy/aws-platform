# route53-resolver

Hybrid DNS. An **inbound** endpoint lets on-prem resolve AWS private hosted
zones; an **outbound** endpoint plus **forward rules** let AWS resolve on-prem
zones. Rules can be RAM-shared so spoke accounts associate their own VPCs
without deploying endpoints of their own (endpoints bill per ENI-hour).

- At least two subnets and at least two forward targets per rule are
  *enforced* - a single-AZ resolver or a single on-prem DNS server would turn
  one failure into an outage of every name lookup.
- Security groups are scoped: inbound accepts 53 only from `onprem_cidrs`;
  outbound only reaches the named on-prem resolvers.
- Optional query logging (CloudWatch / S3 / Firehose) - the first thing
  needed when "DNS is broken".

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix`, `vpc_id`, `subnet_ids` | Where the endpoints live (>= 2 subnets) | | n/a |
| `onprem_cidrs` | Sources allowed on the inbound endpoint | `list(string)` | `[]` |
| `create_inbound` / `create_outbound` | Toggle each direction | `bool` | `true` |
| `forward_rules` | `domain_name`, `target_ips` (>= 2), `target_port` | `map(object)` | `{}` |
| `associate_vpcs` | VPCs the rules (and query logs) apply to, `name => VPC ID`; include the endpoint VPC | `map(string)` | `{}` |
| `share_rules_with_principals` | RAM-share rules with these ARNs | `list(string)` | `[]` |
| `enable_query_logging` / `query_log_destination_arn` | Resolver query logs | `bool` / `string` | `false` / `null` |

Output `inbound_ip_addresses` is what the on-prem DNS servers are pointed at
as conditional forwarders for the AWS zones.

Runbook: `docs/incident-response/runbooks/dns-resolution-failure.md`.
