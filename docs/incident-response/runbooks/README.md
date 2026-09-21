# Runbooks

First-response steps for the alarms the platform's modules raise. Each alarm's
description links here (via the modules' `runbook_url`), so the page a human
gets is one click from the procedure.

| Runbook | Raised by | Default severity |
|---|---|---|
| [vpn-tunnel-down](vpn-tunnel-down.md) | `site-to-site-vpn` | SEV2 (SEV1 if both tunnels / DX also down) |
| [direct-connect-down](direct-connect-down.md) | `direct-connect` | SEV2 (SEV1 if VPN also down) |
| [dns-resolution-failure](dns-resolution-failure.md) | Reports / synthetic checks | SEV2 |
| [alb-5xx-spike](alb-5xx-spike.md) | `load-balancer` | SEV2 |
| [pager-delivery-failed](pager-delivery-failed.md) | `incident-routing` | SEV2 |
| [terraform-apply-failed](terraform-apply-failed.md) | CI failure / drift | SEV2-3 |

Runbook rules: start with what the alarm *means* and its impact, give a
2-minute triage that splits the problem space, prefer commands that can be
pasted, say what **not** to do, and end with how to verify recovery. A
runbook found wrong during an incident or exercise is fixed the same day.
