# Runbook: VPN tunnel down

**Alarm:** `<prefix>-vpn-<name>-tunnel-down` (SEV2 - redundancy lost)
**Impact:** One IPsec tunnel is down. Traffic should continue on the other; if
**both** are down (or Direct Connect is also down) this is a **SEV1**.

## 1. Triage (2 min)

```bash
VPN=vpn-0123456789abcdef0   # from the alarm's VpnId dimension
aws ec2 describe-vpn-connections --vpn-connection-ids $VPN \
  --query 'VpnConnections[0].VgwTelemetry[].{ip:OutsideIpAddress,status:Status,detail:StatusMessage,since:LastStatusChange,routes:AcceptedRouteCount}'
```

- One tunnel `DOWN`, other `UP` -> SEV2, continue.
- Both `DOWN` -> **escalate to SEV1**, declare an incident, and check whether
  Direct Connect is up (`direct-connect-down.md`).
- Both `UP` but alarm firing -> check `TunnelState` metric / alarm config.

## 2. Was it us or them? Check for a recent change

```bash
# Anything applied to this stack recently?
gh run list --workflow terraform-apply.yml --limit 5
```

Ask the on-prem network team: firewall/device change, reboot, ISP maintenance?
The most common causes are on the customer side: device reboot, changed
firewall policy, ISP change of the device's public IP (no longer matches the
customer gateway), NAT-T/UDP 4500 blocked.

## 3. Read the tunnel log

Log group `/aws/vpn/<prefix>/<name>` (JSON).

```bash
aws logs tail /aws/vpn/<prefix>/<name> --since 30m --format short | grep -iE "phase|ike|dpd|proposal|auth"
```

| Log shows | Likely cause | Fix |
|---|---|---|
| Phase 1 proposal mismatch / no proposal chosen | On-prem device offers a suite we don't allow (IKEv1, AES-128, SHA-1, DH < 14) | Reconfigure device to IKEv2 / AES-256 / SHA-2 / DH 14 or 20. **Don't** loosen the module's pinned suites as a quick fix without a change record |
| Phase 1 auth failed | PSK mismatch after a device rebuild | Re-apply the PSK from the `customer_gateway_configuration` output on the device |
| Phase 2 mismatch / TS unacceptable | Traffic selectors or PFS mismatch (BGP tunnels should use 0.0.0.0/0) | Fix device policy to any-any |
| DPD timeout, then restart | Device unreachable / ISP problem | Ping device public IP; escalate to on-prem/ISP |
| Tunnel `UP`, BGP `DOWN`, 0 routes | BGP session not established (inside CIDR, ASN, or a filter) | Check device BGP neighbor `169.254.x.y`, ASN `<on-prem ASN>` |

## 4. Mitigate

- One tunnel up and stable: the service is running without redundancy.
  **Keep the incident open at SEV2** until the second tunnel is back; open a
  ticket with the on-prem owner and an ETA.
- If you must reset from the AWS side (outside window = emergency change):
  `aws ec2 replace-vpn-tunnel` is **disruptive** - only with IC approval, and
  never on the last working tunnel.

## 5. Verify recovery

`TunnelState` = 1 on both tunnels for 10 min, `AcceptedRouteCount` > 0, and an
end-to-end check (ping / app health across the tunnel) passes.

## 6. After

Postmortem if it exceeded 30 min or went to SEV1. If the cause was an
unannounced on-prem change, the action item is the notification path, not the
person.
