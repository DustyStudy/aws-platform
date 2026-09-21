# Incident response

How an incident is declared, run, and closed for the platform. The alert
routing that feeds it is the [`incident-routing`](../../terraform/modules/incident-routing)
module; the technical first-response steps are in [`runbooks/`](runbooks/).

> **Status of this document.** This is the process the platform is built
> around. It is a template until it has been exercised - see
> [GAMEDAYS.md](GAMEDAYS.md) for the exercise log. Nothing here should be read
> as a claim that these procedures have handled a production incident.

## Severity

Severity is about **customer/business impact**, not how alarming the alarm
looks. It's set by the alarm's topic (`sev1`-`sev4`) and re-assessed by the
Incident Commander (IC) once a human has looked.

| Sev | Definition | Examples | Response | Pages? |
|---|---|---|---|---|
| **SEV1** | Full outage or data loss/exposure of a production service, or active security compromise | All on-prem connectivity down (DX **and** VPN); prod cluster API unreachable; credentials leaked | Immediately, 24x7. IC + Ops + Comms | Yes |
| **SEV2** | Major degradation or **loss of redundancy** on a critical path; a SEV1 is one failure away | One DX/VPN path down; ALB target 5xx spike; DNS forwarder unreachable; pager delivery failing | Within 15 min, 24x7. IC = on-call | Yes |
| **SEV3** | Minor degradation, no customer impact yet, workaround exists | Drift detected in prod; single non-critical target unhealthy; cert expires < 14d | Next business day | No - ticket |
| **SEV4** | Cosmetic / hygiene | Untagged resource; noisy alarm needing tuning | Backlog | No - ticket |

When unsure between two levels, **pick the higher one** and downgrade later.
Downgrading is free; a late escalation isn't.

Loss of redundancy is deliberately SEV2: a single dead tunnel is not an
outage, but it is the last chance to fix it *before* it becomes one.

## Roles

One person can hold several roles in a small incident; in a SEV1 they
shouldn't.

| Role | Does | Doesn't |
|---|---|---|
| **Incident Commander (IC)** | Owns the incident. Decides severity, assigns roles, calls decisions, keeps the timeline. Decides when to escalate, roll back, or declare over | Type commands in prod. The IC coordinates; hands-on-keyboard is Ops |
| **Ops lead** | Investigates and mitigates. Runs the runbook, reports findings out loud/in channel | Decide severity or talk to stakeholders |
| **Comms lead** | Status updates on a fixed cadence to stakeholders; single source of "what do we say" | Debug |
| **Scribe** | Timestamped log of what was seen, tried, decided | Anything else |

## Lifecycle

1. **Detect** - alarm pages, or a human reports. Ack within the response target.
2. **Declare** - open `#inc-<yyyymmdd>-<slug>` in chat, post: severity,
   one-line impact, who is IC. *Declaring an incident is cheap and never
   wrong; hesitating is what costs time.*
3. **Stabilize first, diagnose second.** Restore service by the fastest safe
   means (fail over, roll back, scale up, disable the feature) *before*
   chasing root cause. Root cause is the postmortem's job.
4. **Communicate** on cadence: SEV1 every 30 min, SEV2 every 60 min, and on
   any change of state, even if the update is "no change".
5. **Resolve** - impact ended and verified by a metric, not a hunch. Note the
   time; leave the channel open for follow-ups.
6. **Review** - blameless postmortem within 5 business days for SEV1/SEV2
   ([template](POSTMORTEM-TEMPLATE.md)). Action items get owners and due
   dates and are tracked to completion.

## Emergency changes during an incident

Mitigation sometimes needs a prod change outside the normal window. That is
allowed and pre-approved *as an emergency change*: the IC approves, the change
is linked to the incident, and it is reviewed after the fact. See
[CHANGE-MANAGEMENT.md](../CHANGE-MANAGEMENT.md#emergency-changes) - the
apply workflow has an `emergency_incident` input for exactly this.

## Escalation

1. On-call engineer (primary).
2. Secondary on-call, if no ack in 10 min (configured in the paging tool).
3. Engineering manager / platform lead, for any SEV1, or a SEV2 open > 2 h.
4. Cloud provider support (Business/Enterprise) - open the case **early** for
   anything on the AWS side (DX, TGW, VPN); its clock starts when you open it.

## Alert quality

An alarm that pages must be **actionable, urgent, and real**:

- Every paging alarm links a runbook in its description (the modules take a
  `runbook_url`). No runbook, no page - use the ticket tier.
- An alarm that fires and needs no action gets tuned or deleted within the
  week. Pager fatigue is a reliability risk, not a comfort issue.
- Missing data is treated as *breaching* on connectivity alarms: silence from
  a tunnel is not health.
