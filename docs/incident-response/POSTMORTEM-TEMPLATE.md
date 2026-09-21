# Postmortem: <title>

*Blameless. Describes how the **system and process** allowed this, not who
made a mistake. If a person could make this mistake, the process should have
made it hard.*

| | |
|---|---|
| Incident | `#inc-<yyyymmdd>-<slug>` |
| Severity | SEV_ |
| Status | Draft / In review / Final |
| IC / Authors | |
| Started (UTC) / Detected / Mitigated / Resolved | |
| Duration of customer impact | |

## Summary

Two or three sentences a stakeholder can read and stop.

## Impact

Who/what was affected, how badly, for how long. Numbers where possible
(requests failed, users affected, SLO budget consumed).

## Timeline (UTC)

| Time | Event |
|---|---|
| | First signal (alarm / report) |
| | Page acked |
| | Incident declared, IC assigned |
| | Hypothesis / action taken / result |
| | Mitigation applied |
| | Impact ended (verified by: metric) |

## Root cause and contributing factors

Root cause: the deepest thing that, had it been different, would have
prevented this. Then the contributing factors - the reasons it wasn't caught,
was slow to diagnose, or was bigger than it needed to be. Use "5 whys" until
the answer is a process or design property, not a person.

## Detection and response - what worked / what didn't

- **Detection:** did an alarm fire before a human noticed? If not, why not?
  Time from impact start to page:
- **Response:** was the runbook right? Was severity set correctly?
- **Communication:** were updates on cadence?

## Where we got lucky

Things that could have made this worse but didn't. These are unfixed risks.

## Action items

Each has an owner and a due date, and goes in the tracker. "Be more careful"
is not an action item.

| Action | Type (prevent / detect / mitigate) | Owner | Due | Ticket |
|---|---|---|---|---|
| | | | | |

## Lessons

What we'd tell the next on-call.
