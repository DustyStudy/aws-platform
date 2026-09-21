# direct-connect

Everything *logical* on top of an existing Direct Connect connection: DX
gateway, transit virtual interface(s), gateway association to a Transit
Gateway with an explicit allowed-prefix list, TGW route table
association/propagation, and a connection-state alarm.

The physical circuit itself (ordering, cross-connect, LOA-CFA) happens outside
Terraform, so `connection_id` is an input. For a resilient design, order two
connections at different locations and create a VIF on each - this module
takes a map of VIFs.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `connection_id` | Existing `dxcon-...` | `string` | n/a |
| `amazon_side_asn` | DX gateway ASN (must differ from TGW and on-prem ASN) | `number` | `64513` |
| `transit_gateway_id` | TGW to associate | `string` | n/a |
| `association_route_table_id` | TGW route table for the DX attachment | `string` | n/a |
| `propagation_route_table_ids` | TGW route tables that learn on-prem prefixes, `name => ID` | `map(string)` | `{}` |
| `allowed_prefixes` | CIDRs advertised to on-prem (max 20) | `list(string)` | n/a |
| `virtual_interfaces` | Transit VIFs (`vlan`, `bgp_asn`, optional addresses / auth key / MTU) | `map(object)` | n/a |
| `alarm_actions` / `runbook_url` | Alarm wiring | | |

Design notes:

- **Two ASNs on the AWS side.** The TGW and DX gateway each need their own
  ASN, and neither may match the on-prem ASN; BGP sessions flap oddly (or
  never establish) otherwise.
- **`allowed_prefixes` is what on-prem hears.** Advertise the summarized
  regional supernet, not every VPC - a new VPC then needs no change on the
  on-prem router.
- **DX is not encrypted.** If the data class requires encryption in transit
  across the circuit, run IPsec over it (VPN on a public VIF) or use MACsec
  on a dedicated 10/100 Gbps port.

Runbook: `docs/incident-response/runbooks/direct-connect-down.md`.
