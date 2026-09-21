"""Tests for the change gate's decision logic. Run: python -m unittest scripts/test_change_gate.py"""

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import change_gate as cg  # noqa: E402

NOW = datetime(2026, 9, 21, 14, 0, 0, tzinfo=timezone.utc)


def change(**overrides):
    record = {
        "number": "CHG0030001",
        "state": "-1",
        "approval": "approved",
        "start_date": "2026-09-21 13:00:00",
        "end_date": "2026-09-21 16:00:00",
    }
    record.update(overrides)
    return record


class EvaluateChange(unittest.TestCase):
    def test_approved_in_window_in_implement_passes(self):
        self.assertTrue(cg.evaluate_change(change(), NOW).ok)

    def test_not_in_implement_state_fails(self):
        for state in ("-5", "-4", "-3", "-2", "0", "3"):  # new..scheduled, review, closed
            with self.subTest(state=state):
                self.assertFalse(cg.evaluate_change(change(state=state), NOW).ok)

    def test_unapproved_fails(self):
        for approval in ("requested", "not requested", "rejected", ""):
            with self.subTest(approval=approval):
                self.assertFalse(cg.evaluate_change(change(approval=approval), NOW).ok)

    def test_before_window_fails(self):
        r = cg.evaluate_change(change(start_date="2026-09-21 15:00:00", end_date="2026-09-21 17:00:00"), NOW)
        self.assertFalse(r.ok)
        self.assertIn("outside", r.reasons[0])

    def test_after_window_fails(self):
        self.assertFalse(cg.evaluate_change(change(start_date="2026-09-21 09:00:00", end_date="2026-09-21 10:00:00"), NOW).ok)

    def test_window_boundaries_are_inclusive(self):
        self.assertTrue(cg.evaluate_change(change(start_date="2026-09-21 14:00:00"), NOW).ok)
        self.assertTrue(cg.evaluate_change(change(end_date="2026-09-21 14:00:00"), NOW).ok)

    def test_missing_or_garbled_window_fails_closed(self):
        self.assertFalse(cg.evaluate_change(change(start_date="", end_date=""), NOW).ok)
        self.assertFalse(cg.evaluate_change(change(start_date="tomorrow"), NOW).ok)

    def test_all_problems_are_reported_together(self):
        r = cg.evaluate_change(change(state="-5", approval="rejected"), NOW)
        self.assertEqual(len(r.reasons), 2)


class EvaluateEmergency(unittest.TestCase):
    def test_active_p1_passes(self):
        self.assertTrue(cg.evaluate_emergency({"state": "2", "priority": "1"}, "INC0010002").ok)

    def test_active_p2_passes(self):
        self.assertTrue(cg.evaluate_emergency({"state": "1", "priority": "2"}, "INC0010002").ok)

    def test_low_priority_incident_is_not_an_emergency(self):
        r = cg.evaluate_emergency({"state": "2", "priority": "3"}, "INC0010002")
        self.assertFalse(r.ok)
        self.assertIn("P1 or P2", r.reasons[0])

    def test_closed_incident_fails(self):
        for state in ("6", "7", "8"):
            with self.subTest(state=state):
                self.assertFalse(cg.evaluate_emergency({"state": state, "priority": "1"}, "INC0010002").ok)

    def test_unknown_incident_fails(self):
        self.assertFalse(cg.evaluate_emergency(None, "INC0010002").ok)


class FakeServiceNow:
    """Stands in for the API client so cmd_check can be tested without HTTP."""

    def __init__(self, changes=None, incidents=None):
        self.changes = changes or {}
        self.incidents = incidents or {}

    def get_one(self, table, number, fields):
        return (self.changes if table == "change_request" else self.incidents).get(number)


class CmdCheck(unittest.TestCase):
    def run_check(self, sn, **kw):
        args = cg.build_parser().parse_args(
            ["check"]
            + (["--change", kw["change"]] if "change" in kw else [])
            + (["--emergency-incident", kw["incident"]] if "incident" in kw else [])
        )
        return cg.cmd_check(args, sn, NOW)

    def test_pass(self):
        self.assertEqual(self.run_check(FakeServiceNow(changes={"CHG0030001": change()}), change="CHG0030001"), 0)

    def test_unknown_change_fails(self):
        self.assertEqual(self.run_check(FakeServiceNow(), change="CHG0030001"), 1)

    def test_requires_a_reference(self):
        self.assertEqual(self.run_check(FakeServiceNow()), 2)

    def test_rejects_malformed_numbers(self):
        self.assertEqual(self.run_check(FakeServiceNow(), change="not-a-change"), 2)
        self.assertEqual(self.run_check(FakeServiceNow(), incident="CHG0030001"), 2)

    def test_emergency_path_ignores_change_window(self):
        sn = FakeServiceNow(incidents={"INC0010002": {"state": "2", "priority": "1"}})
        self.assertEqual(self.run_check(sn, incident="INC0010002"), 0)


if __name__ == "__main__":
    unittest.main()
