# Change management

How changes to this platform map onto a conventional ITSM change process
(ITIL-style: request -> assess -> authorize -> schedule -> implement -> review).
The goal is that the engineering workflow *is* the change process, rather than
a parallel paperwork step that drifts out of sync with what was deployed.

> **Scope.** This defines the process and the controls the repo enforces. The
> ServiceNow side (change models, approval groups, CAB membership) is
> configured in your ITSM instance, not here; the repo integrates with it via
> [`scripts/change_gate.py`](../scripts/change_gate.py).

## The mapping

| ITSM step | Where it happens here | Control |
|---|---|---|
| **Request (RFC)** | Pull request, using the [PR template](../.github/PULL_REQUEST_TEMPLATE.md) (what, why, risk, rollback) | Branch protection: no direct pushes to `main` |
| **Impact / risk assessment** | `terraform plan` posted on the PR; conftest policy results; the PR template's risk field | Plan + policy gate must pass (`terraform-plan.yml`) |
| **Peer review** | PR approval | CODEOWNERS / required reviewers |
| **Authorize** | ServiceNow change record approved (normal changes: by CAB / approver group) | `change_gate.py` requires `approval = approved` |
| **Schedule** | Change record planned start/end window | Gate requires *now* to be inside the window |
| **Implement** | `terraform-apply.yml` -> `prod` environment (required reviewers) | Reviewer approval **and** change gate, checked at the moment of apply |
| **Record** | Workflow writes the outcome + commit SHA + run URL to the change record's work notes | Automatic; no copy-paste |
| **Review (PIR)** | Failed/rolled-back changes and all emergency changes get a review | Emergency applies auto-open a tracked issue |

## Change types

| Type | When | Approval | Lead time | How it deploys |
|---|---|---|---|---|
| **Standard** | Pre-approved, low-risk, repeatable, with a proven procedure: e.g. onboarding a tenant namespace via the golden path, adding a forward rule, rotating a cert | Pre-authorized template in ServiceNow; no CAB per change | None | Dev auto-applies on merge; prod via change gate with a standard-change record |
| **Normal** | Anything with non-trivial risk: new network path, TGW route-table change, VPN/DX changes, module major-version bump | CAB / approver group | Per your CAB calendar | Prod apply requires the approved record in `Implement` state, within its window |
| **Emergency** | Restoring service during an active P1/P2 incident | IC approves; ECAB/retroactive record after the fact | None | `emergency_incident` input; see below |

**Higher-risk by default in this repo** (treat as Normal even if it feels
small): anything touching Transit Gateway route tables/propagation, Direct
Connect or VPN, Route 53 Resolver rules/endpoints, SCPs, IAM trust policies,
or KMS key policies. A wrong TGW propagation is a network-wide outage or a
segmentation breach with no error message.

## Risk rubric (goes in the PR template)

| Factor | Low | Medium | High |
|---|---|---|---|
| Blast radius | One tenant / dev only | One environment | Shared network, IAM, or multiple environments |
| Reversibility | `git revert` + apply restores | Revert works but has data/state effects | Destructive (replaces/destroys), or needs vendor involvement |
| Plan clarity | Plan is small and fully understood | Plan has unexpected diffs, explained | Plan has replacements/destroys of shared resources |
| Novelty | Done many times | Done before, differently | First time |

Two or more Highs = Normal change with a rollback rehearsed in a lower
environment first.

## Deploying to prod - the actual steps

1. PR merged (plan + policy + review already passed). Dev auto-applies.
2. Raise (or reference) the change record. Get it approved and scheduled.
3. In the change window, once the record is in **Implement**:
   *Actions -> Terraform Apply -> Run workflow* -> `environment: prod`,
   `change_request: CHG0030001`.
4. `prod` environment reviewers approve. The job starts, **then** the gate
   verifies the record (state, approval, window) - so a change approved for
   Tuesday can't be deployed on Thursday off the same run.
5. Apply runs; outcome is written back to the change record.
6. Close the record (Review state) after verification.

Configuration: set repo variable `SERVICENOW_INSTANCE` and secrets
`SERVICENOW_USER` / `SERVICENOW_PASSWORD` (an integration account with read on
`change_request` + `incident` and write on `change_request.work_notes`,
nothing else). **If `SERVICENOW_INSTANCE` is unset the gate is skipped** with a
visible notice - the template repo isn't wired to an ITSM. Set it before
treating this as a controlled production pipeline.

The gate **fails closed**: if ServiceNow is unreachable or returns an error,
the apply does not proceed. That's the right default for a control, and it's
why the emergency path exists.

## Emergency changes

Used only to restore service during an incident. Requires an **active P1/P2
incident** - the gate checks the incident is open and high priority, so
"emergency" can't be used to skip the process for something inconvenient.

1. IC approves the emergency change (in the incident channel; recorded in the timeline).
2. Run Terraform Apply with `emergency_incident: INC0010002` (and
   `change_request` if a record already exists).
3. `prod` environment reviewers still approve - the emergency path skips
   *scheduling and CAB*, not *a second pair of eyes*. In a real incident the IC
   or the secondary on-call is that reviewer.
4. On completion an issue labelled `emergency-change` is opened automatically
   with a checklist: retroactive change record, review of whether it was the
   right mitigation, follow-up fix through the normal process, link in the
   postmortem. It stays open until a human closes it.

Hand-editing prod in the console is **not** the emergency path - drift
detection will flag it and the next apply will silently undo it. Emergency
changes go through code so they're recorded, reviewed and reproducible.

## Metrics worth tracking (DORA + ITSM)

- **Change failure rate:** % of changes needing rollback/hotfix/incident.
- **Lead time for changes** and **deployment frequency.**
- **MTTR** for change-induced incidents.
- **Emergency change ratio:** a rising share means the normal process is too
  slow or planning is poor - investigate the process, not the people.
- **Changes without a record:** applies to prod without `change_request` -
  should be zero once the gate is enforced.
