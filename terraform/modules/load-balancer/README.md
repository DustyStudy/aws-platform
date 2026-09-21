# load-balancer

ALB (`type = "application"`) or NLB (`type = "network"`) with the hardening
that's otherwise a checklist someone forgets:

- **Internal by default.** Internet-facing must be requested.
- **TLS only.** A certificate is a required input; an ALB's port 80 listener
  exists solely to 301 to HTTPS. TLS 1.3-preferred policy, 1.2 floor.
- ALB: `drop_invalid_header_fields`, strictest desync mitigation, deletion
  protection, security group whose **egress is limited to the target security
  groups on their own ports** (no `0.0.0.0/0` egress rule).
- **Access logs are required** (`access_logs_bucket`) - the first thing asked
  for in a 5xx incident, and impossible to retroactively enable.
- Optional WAFv2 association (ALB).
- Alarms: target 5xx, and per-target-group unhealthy hosts, wired to
  `alarm_actions` with a `runbook_url` in the description.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix`, `vpc_id`, `subnet_ids` | Placement (>= 2 AZs) | | n/a |
| `type` | `application` or `network` | `string` | `application` |
| `internal` | Internal vs internet-facing | `bool` | `true` |
| `certificate_arn` | ACM cert for the TLS listener | `string` | n/a |
| `allowed_ingress_cidrs` | ALB ingress CIDRs (443/80) | `list(string)` | `[]` |
| `target_groups` | Port, protocol, target type, health check | `map(object)` | n/a |
| `target_security_groups` | SGs of the targets, `name => ID` (ALB egress) | `map(string)` | `{}` |
| `access_logs_bucket` | S3 bucket for access logs | `string` | n/a |
| `associate_waf` / `waf_acl_arn` | WAFv2 ACL (ALB) | `bool` / `string` | `false` / `null` |
| `alarm_actions` / `runbook_url` | Alarm wiring | | |

Register targets from the workload side (EKS: AWS Load Balancer Controller
`TargetGroupBinding` against `target_group_arns["web"]`).

Runbook: `docs/incident-response/runbooks/alb-5xx-spike.md`.
