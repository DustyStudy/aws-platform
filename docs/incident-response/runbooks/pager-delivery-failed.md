# Runbook: pager delivery failed

**Alarm:** `<prefix>-pager-delivery-failed` - messages are sitting in the pager
DLQ. **Treat as SEV2**: while this is true, real SEV1/SEV2 alerts may not reach a
human. It routes to the *ticket* tier (email) because it can't page via the
thing that is broken - so if you're reading this, you likely got an email.

## 1. What failed?

```bash
aws sqs receive-message --queue-url <pager-dlq-url> --max-number-of-messages 10 \
  --attribute-names All --message-attribute-names All
aws sns list-subscriptions-by-topic --topic-arn <sev1-topic-arn>
```

The messages *are* the alerts that didn't page - read them: **is there a real
incident right now?** If so, page manually via the paging tool's UI/phone and
declare the incident before fixing the plumbing.

## 2. Why?

| Finding | Cause | Fix |
|---|---|---|
| Subscription `PendingConfirmation` | HTTPS endpoint never confirmed | Confirm in the paging tool; re-subscribe |
| Delivery status 4xx from endpoint | Integration key revoked/rotated, or integration disabled | Get the current URL from the paging tool; update `pager_endpoint` (secret) and apply |
| Delivery status 5xx / timeout | Paging vendor outage | Check vendor status page; fall back to phone tree / the ticket email tier |
| Topic KMS `AccessDenied` | Key policy changed | Restore `AllowAlarmPublishers` statement |

## 3. Restore and verify

Fix the cause, then send a test alert to `sev2` (`aws sns publish`) and confirm
the on-call phone rings. Purge the DLQ once its contents are reviewed. **Replay
any real alerts** that were stuck.

## 4. After

Every occurrence gets a postmortem line: how long was the pager dark, and would
we have known without this alarm? Consider a synthetic heartbeat (daily test
page to a low-urgency service) if the pager has failed silently before.
