# Runbook: ALB 5xx spike / unhealthy targets

**Alarms:** `<prefix>-alb-target-5xx`, `<prefix>-alb-<tg>-unhealthy-hosts`
(SEV2). SEV1 if the service is effectively down for users.

## 1. Whose 5xx is it?

| Metric | Meaning |
|---|---|
| `HTTPCode_Target_5XX_Count` high | **The application** is returning errors |
| `HTTPCode_ELB_5XX_Count` high (502/503/504) | **The LB**: no healthy targets (503), bad target response (502), target timeout (504) |
| `UnHealthyHostCount` > 0 | Health checks failing - see step 3 |

## 2. Did we just change something? (highest-yield question)

```bash
gh run list --workflow terraform-apply.yml --limit 5     # infra
kubectl -n <ns> rollout history deploy/<name>            # app
```

If yes and the timing fits: **roll back first, diagnose after** (stabilize
before diagnose). A prod rollback outside the window is an emergency change -
IC approves, log the incident ID.

## 3. Unhealthy targets

```bash
aws elbv2 describe-target-health --target-group-arn <arn> \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].{t:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason,desc:TargetHealth.Description}'
```

| Reason | Cause |
|---|---|
| `Target.Timeout` | SG between LB and target blocks the health-check port, or app is hung |
| `Target.ResponseCodeMismatch` | Health path returns non-2xx (app up, dependency down, or path changed) |
| `Target.FailedHealthChecks` | Connection refused - app not listening on the target port |
| `Target.NotRegistered` / `Target.NotInUse` | Nothing registered (pods rescheduling; TargetGroupBinding broken) |

If **all** targets are unhealthy the LB fails open in some configs and serves to
unhealthy targets - don't assume a health check is protecting you.

## 4. Look at the access logs

Access logs are in the `access_logs_bucket` (S3). Athena/`grep` on
`elb_status_code`, `target_status_code`, `request_processing_time`,
`target_processing_time`: is it one path, one target, one client, or
everything?

## 5. Mitigate

Rollback; scale targets up if saturated (`RejectedConnectionCount`,
`TargetResponseTime`); remove a single bad target; shed load / rate-limit at WAF
if it's abusive traffic (WAF association is optional in the module).

## 6. Verify

Target 5xx back to baseline for 15 min, all targets healthy, and a synthetic
request through the LB succeeds end to end.
