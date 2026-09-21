## What and why

<!-- One or two sentences. Link the ticket / incident. -->

## Change type

- [ ] Standard (pre-approved, repeatable - e.g. tenant onboarding)
- [ ] Normal (needs a change record before prod)
- [ ] Emergency (linked to active incident: INC_______)

Change record (if known): `CHG_______`

## Risk

<!-- See docs/CHANGE-MANAGEMENT.md#risk-rubric. Two or more Highs = Normal + rehearse in a lower env. -->

| Factor | Low / Med / High | Note |
|---|---|---|
| Blast radius | | |
| Reversibility | | |
| Plan clarity | | |
| Novelty | | |

**Touches any of:** TGW routes/propagation, Direct Connect/VPN, Resolver rules,
SCPs, IAM trust, KMS key policy?  - [ ] yes (treat as Normal) - [ ] no

## Rollback

<!-- How do we undo this, and how long does it take? "git revert + apply" is a valid answer only if true. -->

## Verification

<!-- How will we know it worked? A metric, a check, a test - not "looks fine". -->

## Checklist

- [ ] `terraform plan` reviewed (no unexpected replacements/destroys)
- [ ] Policy gate passes
- [ ] Runbook/docs updated if behavior or alarms changed
- [ ] New alarms link a runbook (`runbook_url`) and have a severity
