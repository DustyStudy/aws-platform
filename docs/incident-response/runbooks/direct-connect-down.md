# Runbook: Direct Connect down

**Alarm:** `<prefix>-dx-<connection-id>-down` (SEV2)
**Impact:** The primary on-prem path is gone. If the VPN backup is healthy,
traffic has failed over (expect higher latency, lower throughput, ~1.25 Gbps
per VPN tunnel ceiling). If the VPN is *also* down, this is a **SEV1**.

## 1. Triage (2 min)

```bash
CON=dxcon-abc123
aws directconnect describe-connections --connection-id $CON \
  --query 'connections[0].{state:connectionState,loa:loaIssueTime,location:location}'
aws directconnect describe-virtual-interfaces --connection-id $CON \
  --query 'virtualInterfaces[].{vif:virtualInterfaceId,state:virtualInterfaceState,bgp:bgpPeers[].{peer:bgpPeerState,status:bgpStatus}}'
```

| State | Meaning | Next |
|---|---|---|
| Connection `down` | Physical/layer-1: cross-connect, optic, fibre, provider | Step 2 (provider) |
| Connection `available`, VIF `down`, BGP `down` | Layer 3: BGP session (auth key, ASN, VLAN, peer IP) | Step 3 |
| VIF `available`, BGP `up`, but no traffic | Routing: prefixes not advertised/propagated | Step 4 |

## 2. Physical layer

- Check the AWS Health Dashboard / `aws health describe-events` for DX
  maintenance at the location.
- Contact the circuit/colo provider and on-prem network team: optics, patch,
  router interface state.
- **Open the AWS support case now** (Business+ support, severity per impact) -
  it starts a clock regardless of what you find.

## 3. BGP layer

Confirm on the on-prem router: VLAN tag matches the VIF, peer IPs match
`amazon_address`/`customer_address`, MD5 auth key matches, ASN is the one on the
VIF, MTU consistent (8500 transit VIF; a mismatch shows as a session that
establishes but stalls on large route updates).

## 4. Routing layer

```bash
# What is on-prem actually advertising to AWS, and does the TGW have it?
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <hybrid-rtb> \
  --filters Name=type,Values=propagated \
  --query 'Routes[].{cidr:DestinationCidrBlock,att:TransitGatewayAttachments[0].ResourceType,state:State}'
```

- Missing on-prem prefixes -> on-prem isn't advertising them, or exceeded the
  100-prefix limit for routes advertised from on-prem over a transit VIF (AWS
  drops the BGP session when it's exceeded) - summarize on the router.
- AWS prefixes not visible on-prem -> check `allowed_prefixes` on the
  `direct-connect` module (max 20).

## 5. Mitigate

- **Confirm the VPN backup is carrying traffic** (`vpn-tunnel-down.md` if not)
  and tell stakeholders about reduced bandwidth/latency.
- Do **not** flap the VIF or change BGP config on the AWS side as a guess.
- Throughput-sensitive jobs (bulk replication, backups) may need to be
  paused/rescheduled while on VPN - IC decides.

## 6. Verify recovery

Connection `available`, BGP `up` on all VIFs, TGW shows propagated on-prem
routes, alarm returns to OK, and the VPN is no longer the primary path (check
route preference: DX must win over VPN, i.e. longer AS-path on the VPN side).

## 7. After

Always postmortem for SEV1; for SEV2 if > 1 h. Ask: did failover happen
without human action? Was the bandwidth loss anticipated?
