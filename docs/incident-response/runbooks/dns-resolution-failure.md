# Runbook: DNS resolution failure (hybrid)

**Symptoms:** on-prem can't resolve AWS private names, or AWS workloads can't
resolve on-prem names (`corp.example.com`), or both. Usually **SEV2**; SEV1 if
it takes down a production dependency.

## 1. Which direction is broken?

| Direction | Path | Components |
|---|---|---|
| AWS -> on-prem | VPC resolver -> **forward rule** -> outbound endpoint -> TGW/DX/VPN -> on-prem DNS | rule association, outbound SG, connectivity, on-prem DNS |
| on-prem -> AWS | on-prem DNS conditional forwarder -> **inbound endpoint** IPs -> private hosted zone | forwarder config, inbound SG, connectivity |

## 2. Reproduce from the right place

```bash
# From an AWS instance (SSM Session Manager):
dig +short corp.example.com                       # via VPC resolver
dig +short corp.example.com @<on-prem-dns-ip>     # bypass rule: tests raw connectivity/53
# From on-prem:
dig +short myservice.aws.internal @<inbound-endpoint-ip>
```

- Direct query to on-prem DNS works but the VPC resolver query doesn't ->
  **rule** problem (step 3).
- Direct query also fails -> **network** problem: check DX/VPN first
  (`direct-connect-down.md`, `vpn-tunnel-down.md`), TGW routes, and the outbound
  endpoint SG egress (must allow 53/tcp+udp to the on-prem DNS IPs).
- Only large answers fail -> TCP/53 blocked (UDP works, truncated response
  can't retry over TCP).

## 3. Check the rule and its association

```bash
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?RuleType==`FORWARD`].{id:Id,domain:DomainName,status:Status,targets:TargetIps[].Ip}'
aws route53resolver list-resolver-rule-associations \
  --query 'ResolverRuleAssociations[].{rule:ResolverRuleId,vpc:VPCId,status:Status}'
```

- Rule status not `COMPLETE`, or the VPC isn't associated -> add the VPC to
  `associate_vpc_ids` (normal change; emergency change if in an incident).
- A more specific rule (or a private hosted zone associated to the VPC for
  the same name) overrides the forward rule - names resolve to the wrong place
  rather than failing.

## 4. Use query logs

If `query_log_destination_arn` is set: CloudWatch Logs Insights on the query log
group filtered by `query_name` shows whether queries arrive, which rule matched
(`srcids`), the `rcode` (NXDOMAIN vs SERVFAIL vs timeout) and answers.

## 5. Was this a change?

`gh run list --workflow terraform-apply.yml --limit 5` - the usual root cause is
a recent SG/rule/association change. Roll back via an emergency change, don't
hand-edit in the console (drift detection will flag it, and the next apply will
undo your fix).

## 6. Verify

Resolve a name in each direction from a real client; endpoints show healthy
ENIs in both AZs; no `SERVFAIL` in query logs for 10 min.
