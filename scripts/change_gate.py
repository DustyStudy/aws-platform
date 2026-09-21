#!/usr/bin/env python3
"""ITSM change gate for production applies (ServiceNow).

Answers one question before `terraform apply` touches prod: *is there an
approved change record that says this may happen right now?*

    change_gate.py check --change CHG0030001
    change_gate.py check --emergency-incident INC0010002 [--change CHG0030002]
    change_gate.py note  --change CHG0030001 --message "Applied <sha>: success"

Normal / standard changes must be in ``Implement`` state, approved, and the
current time must be inside the planned start/end window. Emergency changes
skip the window/approval check but must be tied to an *active P1/P2 incident*,
so "emergency" can't be used as a way around the process on a quiet Tuesday.

Configuration (environment):
    SN_INSTANCE   ServiceNow instance name ("acme") or full https URL
    SN_USER / SN_PASSWORD   an integration account with read on change_request
                            and incident, and write on change_request work_notes

Standard library only - it runs on a stock GitHub-hosted runner with no
install step, which is one less supply-chain dependency in the deploy path.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone

# ServiceNow change_request.state choice values (out-of-the-box).
STATE_IMPLEMENT = "-1"
# incident.state: 7 = Closed, 8 = Canceled, 6 = Resolved
INCIDENT_INACTIVE_STATES = {"6", "7", "8"}

CHANGE_RE = re.compile(r"^CHG\d{7,}$")
INCIDENT_RE = re.compile(r"^INC\d{7,}$")

SN_TIME_FORMAT = "%Y-%m-%d %H:%M:%S"  # ServiceNow returns UTC in this format


@dataclass
class Result:
    ok: bool
    reasons: list[str] = field(default_factory=list)

    def fail(self, reason: str) -> "Result":
        self.ok = False
        self.reasons.append(reason)
        return self


def parse_sn_time(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.strptime(value, SN_TIME_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def evaluate_change(record: dict, now: datetime) -> Result:
    """Pure decision logic for a normal/standard change - no I/O, easy to test."""
    result = Result(ok=True)
    number = record.get("number", "?")

    if str(record.get("state")) != STATE_IMPLEMENT:
        result.fail(f"{number} is not in Implement state (state={record.get('state')!r}); it must be scheduled and moved to Implement before deploying")

    if str(record.get("approval", "")).lower() != "approved":
        result.fail(f"{number} is not approved (approval={record.get('approval')!r})")

    start = parse_sn_time(record.get("start_date", ""))
    end = parse_sn_time(record.get("end_date", ""))
    if start is None or end is None:
        result.fail(f"{number} has no valid planned start/end window")
    elif not (start <= now <= end):
        result.fail(f"now ({now:%Y-%m-%d %H:%M:%S}Z) is outside {number}'s window ({start:%Y-%m-%d %H:%M}Z - {end:%Y-%m-%d %H:%M}Z)")

    return result


def evaluate_emergency(incident: dict | None, incident_number: str) -> Result:
    """An emergency change must be justified by a live P1/P2 incident."""
    result = Result(ok=True)
    if incident is None:
        return result.fail(f"incident {incident_number} not found")

    if str(incident.get("state")) in INCIDENT_INACTIVE_STATES:
        result.fail(f"{incident_number} is not active (state={incident.get('state')!r}); emergency changes need a live incident")

    if str(incident.get("priority")) not in {"1", "2"}:
        result.fail(f"{incident_number} is priority {incident.get('priority')!r}; emergency changes require P1 or P2 - raise a normal change instead")

    return result


class ServiceNow:
    def __init__(self, instance: str, user: str, password: str):
        base = instance if instance.startswith("https://") else f"https://{instance}.service-now.com"
        self.base = base.rstrip("/")
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=self.headers)
        with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310 - https base enforced above
            return json.loads(resp.read().decode())

    def get_one(self, table: str, number: str, fields: str) -> dict | None:
        query = urllib.parse.urlencode({
            "sysparm_query": f"number={number}",
            "sysparm_fields": fields,
            "sysparm_limit": "1",
        })
        rows = self._request("GET", f"/api/now/table/{table}?{query}").get("result", [])
        return rows[0] if rows else None

    def add_work_note(self, sys_id: str, message: str) -> None:
        self._request("PATCH", f"/api/now/table/change_request/{sys_id}", {"work_notes": message})


def client_from_env() -> ServiceNow:
    missing = [k for k in ("SN_INSTANCE", "SN_USER", "SN_PASSWORD") if not os.environ.get(k)]
    if missing:
        raise SystemExit(f"change gate misconfigured: missing {', '.join(missing)}")
    return ServiceNow(os.environ["SN_INSTANCE"], os.environ["SN_USER"], os.environ["SN_PASSWORD"])


def cmd_check(args: argparse.Namespace, sn: ServiceNow, now: datetime) -> int:
    if args.change and not CHANGE_RE.match(args.change):
        print(f"::error::'{args.change}' is not a change number (expected CHG#######)")
        return 2
    if args.emergency_incident and not INCIDENT_RE.match(args.emergency_incident):
        print(f"::error::'{args.emergency_incident}' is not an incident number (expected INC#######)")
        return 2
    if not args.change and not args.emergency_incident:
        print("::error::a production apply needs --change, or --emergency-incident for an emergency")
        return 2

    if args.emergency_incident:
        incident = sn.get_one("incident", args.emergency_incident, "number,state,priority,short_description")
        result = evaluate_emergency(incident, args.emergency_incident)
        label = f"EMERGENCY via {args.emergency_incident}"
    else:
        record = sn.get_one("change_request", args.change, "number,state,approval,start_date,end_date,type,short_description")
        if record is None:
            result = Result(ok=False, reasons=[f"change {args.change} not found"])
        else:
            result = evaluate_change(record, now)
        label = args.change

    if result.ok:
        print(f"change gate PASSED: {label}")
        return 0

    for reason in result.reasons:
        print(f"::error::change gate: {reason}")
    print(f"change gate FAILED: {label}")
    return 1


def cmd_note(args: argparse.Namespace, sn: ServiceNow, _now: datetime) -> int:
    record = sn.get_one("change_request", args.change, "sys_id,number")
    if record is None:
        print(f"::warning::cannot write work note: {args.change} not found")
        return 1
    sn.add_work_note(record["sys_id"], args.message)
    print(f"work note added to {args.change}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="verify a change record authorizes a prod apply right now")
    check.add_argument("--change")
    check.add_argument("--emergency-incident")
    check.set_defaults(func=cmd_check)

    note = sub.add_parser("note", help="append a work note to a change record")
    note.add_argument("--change", required=True)
    note.add_argument("--message", required=True)
    note.set_defaults(func=cmd_note)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args, client_from_env(), datetime.now(timezone.utc))
    except urllib.error.HTTPError as exc:
        # Fail CLOSED: if we can't reach/authenticate to the ITSM, we can't
        # prove the change is approved, so the apply does not proceed.
        print(f"::error::ServiceNow returned HTTP {exc.code} - failing closed")
        return 1
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"::error::cannot reach ServiceNow ({exc}) - failing closed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
