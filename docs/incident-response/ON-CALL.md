# On-call

## Expectations

- **Ack** a page within 5 minutes; **engage** (laptop open, looking) within 15
  for SEV2 and immediately for SEV1.
- Be somewhere with reliable connectivity and able to reach prod (VPN/SSO
  working) *before* your shift starts - test it, don't assume.
- You are the first responder, not the only one. Escalate early; asking for
  help at minute 10 is a normal use of the secondary, not a failure.

## Rotation

- Weekly, handoff at a fixed time (suggest Monday mid-morning, not Friday
  evening).
- Primary + secondary. Nobody is primary two weeks running.
- A page overnight = protected recovery time the next morning. Encode this in
  team policy, not goodwill.

## Handoff checklist

Outgoing on-call posts in the team channel:

- Open incidents and their state
- Alarms that flapped, and whether they were tuned
- Changes scheduled during the coming week (link to change records)
- Anything "weird but not yet an incident"
- Any degraded redundancy (e.g. "VPN tunnel 2 has been down since Tue -
  ticket #123, waiting on customer's firewall change")

## Start-of-shift checks (10 minutes)

- [ ] Pager test notification received on phone *and* backup channel
- [ ] Can assume the prod read-only role via SSO
- [ ] Dashboards load; know where the runbooks index is ([runbooks/](runbooks/))
- [ ] Read the previous shift's handoff
- [ ] `pager-delivery-failed` alarm is OK (the pager itself is working)

## Tooling map

| Need | Where |
|---|---|
| Who's paged / schedule | Paging tool (endpoint configured in `incident-routing`) |
| Runbooks | [runbooks/](runbooks/) - linked from each alarm's description |
| Severity definitions | [INCIDENT-RESPONSE.md](INCIDENT-RESPONSE.md#severity) |
| Emergency change path | [CHANGE-MANAGEMENT.md](../CHANGE-MANAGEMENT.md#emergency-changes) |
| Postmortem | [POSTMORTEM-TEMPLATE.md](POSTMORTEM-TEMPLATE.md) |

## After a page

Every page, even a false one, gets a one-line note in the handoff log: what
fired, what it was, whether the alarm needs changing. That log is where
alarm-tuning work comes from.
