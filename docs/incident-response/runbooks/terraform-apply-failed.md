# Runbook: `terraform apply` failed midway / state locked

**Severity:** depends on what was half-changed. A partial apply of network
resources (TGW routes, resolver rules, SGs) can cause an outage - treat as
SEV2 until you know.

## 1. Don't re-run blindly

Read the failure. A retry after a partial apply of a *routing* change can
make it worse. Identify from the log which resources were changed before the
error.

## 2. State locked

State uses S3 native locking (`use_lockfile = true`) -> a `<key>.tflock` object.

```bash
aws s3 ls s3://<state-bucket>/<env>/ | grep tflock
```

- A run is still in progress -> **wait**; check `gh run list` for a live job.
- The run crashed/was cancelled and nobody is applying -> `terraform force-unlock <LOCK_ID>`
  (ID is in the error). Confirm with the IC that no one else is applying;
  force-unlocking during a live apply corrupts state.

## 3. Assess the damage

```bash
terraform plan -out=recover.tfplan   # what does Terraform think is still to do?
terraform show recover.tfplan
```

Compare to what's live for the blast-radius resources (routes, SG rules, LB
listeners). The plan is your diff between "applied half" and "intended".

## 4. Choose

| Situation | Action |
|---|---|
| Plan is the remaining intended changes and is safe | Apply it (emergency change if outside window) |
| Half-applied state is causing an outage | Roll forward is unsafe -> revert the commit, plan, apply the revert (emergency change) |
| Resource exists in AWS but not in state | `terraform import`, then plan |
| State corrupted | Restore the previous S3 object version (bucket versioning is enabled by `bootstrap/`), then re-plan |

## 5. Verify and record

No-op `terraform plan`; connectivity/health checks for what was touched. Log
in the change record and the incident. Root cause goes in the postmortem
(provider bug? IAM gap in the apply role? API rate limit? quota?).
