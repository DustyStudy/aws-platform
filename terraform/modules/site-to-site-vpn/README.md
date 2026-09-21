# site-to-site-vpn

Two-tunnel, BGP-based IPsec VPN terminating on a Transit Gateway. Meant as the
**backup path behind Direct Connect** or the primary path for smaller sites.

- IKEv2 only, AES-256, SHA-2, DH 14/20 - AWS's defaults still permit IKEv1,
  AES-128 and SHA-1, so the suites are pinned.
- BGP only. Static routing is not offered: BGP is what lets a dead tunnel
  withdraw its routes instead of black-holing traffic.
- Tunnel logs go to CloudWatch (JSON), so "why won't phase 1 come up" is
  answerable without a support case.
- One alarm per connection on the *minimum* `TunnelState` - fires when
  redundancy is lost (one tunnel down), not only after a total outage.
  Missing data counts as breaching.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `transit_gateway_id` | TGW to attach to | `string` | n/a |
| `association_route_table_id` | TGW route table the VPN associates with | `string` | n/a |
| `propagation_route_table_ids` | TGW route tables that learn on-prem prefixes, `name => ID` | `map(string)` | `{}` |
| `customer_gateways` | On-prem devices (`ip_address`, `bgp_asn`) | `map(object)` | n/a |
| `connections` | VPN connections (`customer_gateway`, optional inside CIDRs) | `map(object)` | n/a |
| `log_retention_days` | Tunnel log retention | `number` | `365` |
| `alarm_actions` | SNS topics for tunnel-down alarms | `list(string)` | `[]` |
| `runbook_url` | Included in alarm description | `string` | `""` |

**Secrets:** pre-shared keys live in Terraform state (the
`customer_gateway_configuration` output is `sensitive`). State must be
encrypted and access-scoped - `bootstrap/` already does both.

Runbook: `docs/incident-response/runbooks/vpn-tunnel-down.md`.
