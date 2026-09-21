# Game days and tabletop exercises

A process nobody has practiced is a hypothesis. This file is the **scenario
library** and the **log of exercises actually run**. The log starts empty on
purpose - entries are added only when an exercise happens, with real findings.

## How to run one (45-60 min tabletop)

1. Pick a scenario below. Assign IC, Ops, Comms, Scribe. Facilitator (not one
   of those) reads the scenario **one inject at a time**.
2. Participants answer as if it were real, using only the runbooks and
   dashboards they'd really have. Facilitator withholds the answer.
3. Scribe records every place someone said "I'd... uh..." - that's the finding.
4. Debrief with the [postmortem template](POSTMORTEM-TEMPLATE.md); file action
   items for every gap found in a runbook, alarm, or permission.

Live variants (staging only - never first in prod): actually drop a VPN
tunnel, blackhole a TGW route, or kill the outbound resolver rule and time
detection-to-mitigation.

## Scenario library

| # | Scenario | Injects (in order) | Tests |
|---|---|---|---|
| 1 | **Primary Direct Connect fails** | Page: `dx-down` -> traffic shifts to VPN, latency doubles -> on-prem team says the circuit provider is "investigating, ETA unknown" | Runbook, failover assumptions, provider escalation, comms cadence |
| 2 | **Both VPN tunnels flap** | Alarm: tunnel-down x2 -> tunnel logs show phase 2 mismatch -> it began right after an on-prem firewall change nobody told you about | Log access, change-record lookup, cross-team comms |
| 3 | **Split-horizon DNS breaks** | On-prem apps can't resolve `*.aws.internal`; AWS hosts can't resolve `corp.example.com` -> outbound endpoint SG changed in last deploy | Resolver runbook, drift/change correlation, rollback path |
| 4 | **ALB 5xx spike after deploy** | Target 5xx alarm -> deploy landed 4 min ago -> rollback needs an emergency change | Emergency change process ([CHANGE-MANAGEMENT.md](../CHANGE-MANAGEMENT.md)), stabilize-before-diagnose |
| 5 | **The pager is broken** | Nothing pages. Someone notices a SEV2 alarm sitting in ALARM for 40 min -> DLQ has 12 messages | Whether anyone would notice; `pager-delivery-failed` runbook |
| 6 | **Bad `terraform apply` mid-flight** | Apply fails halfway; state locked; half of a TGW route change is live | State-lock runbook, partial-apply recovery, blast-radius judgement |

## Exercise log

| Date | Scenario | Format (tabletop / live-staging) | Participants | Gaps found | Actions filed |
|---|---|---|---|---|---|
| *(none yet)* | | | | | |
