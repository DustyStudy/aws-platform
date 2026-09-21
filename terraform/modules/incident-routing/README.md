# incident-routing

Severity-tiered alert routing: four KMS-encrypted SNS topics, `sev1`-`sev4`.

| Topic | Delivers to | Meaning |
|---|---|---|
| `sev1`, `sev2` | `pager_endpoint` (HTTPS - PagerDuty/Opsgenie/etc.) | A human is woken up |
| `sev3`, `sev4` | `ticket_emails` | A human looks during working hours |

Severity is chosen when the alarm is *written* (which topic it publishes to),
not improvised at 3am. Definitions and expected response live in
`docs/incident-response/INCIDENT-RESPONSE.md`.

Things this does that plain "alarm -> SNS -> email" doesn't:

- **The pager is monitored.** Undeliverable pages are dead-lettered to an SQS
  queue, and an alarm on that queue routes to the ticket tier. "The pager
  integration is broken" is otherwise invisible until the next real incident.
- **`require_pager`** turns a missing pager endpoint into a failed plan
  (`check` block) - set it in prod so SEV1/SEV2 can't silently go nowhere.
- The pager URL (it embeds the integration key) is `sensitive`.

| Name | Description | Type | Default |
|---|---|---|---|
| `name_prefix` | Prefix for resource names/tags | `string` | n/a |
| `pager_endpoint` | HTTPS pager integration URL | `string` (sensitive) | `null` |
| `ticket_emails` | SEV3/SEV4 recipients | `list(string)` | `[]` |
| `require_pager` | Fail plan if `pager_endpoint` is null | `bool` | `false` |

Output `topic_arns` -> use `topic_arns["sev2"]` as `alarm_actions` on any alarm.

Email subscriptions must be confirmed by the recipient once; HTTPS
subscriptions to PagerDuty auto-confirm.
