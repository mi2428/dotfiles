import importlib.util
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

WATCH = (
    Path(__file__).resolve().parents[2]
    / "home/files/agents/skills/omo-watch/watch.py"
)


def load_watch():
    spec = importlib.util.spec_from_file_location("omo_watch_context_test", WATCH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


W = load_watch()
ARGS = SimpleNamespace(
    context_grace=180.0, context_max_wait=1800.0, context_max_defers=3
)
JST = timezone(timedelta(hours=9))
NOW = time.time()


def target(session: str | None = None):
    state = W.Target("t3r", "/tmp/project", None)
    state.session = session
    state.last_progress = time.time() - 1000
    return state


def verdict(mode: str, text: str, now: float, state=None):
    state = state or target()
    return W.infer_context(ARGS, state, mode, W.pane_context(text, now), now)


class PaneContextTest(unittest.TestCase):
    def test_backstop_time_sets_wake_epoch(self):
        now = datetime(2026, 11, 26, 15, 50, tzinfo=JST).timestamp()
        text = " Stall backstop ready 2026-11-26 15:57 GMT+9 (4m 30s) - resumes"
        parsed = W.pane_context(text, now)
        self.assertAlmostEqual(parsed["wake_epoch"], now + 420, delta=1)
        decision, until, reason = W.infer_context(
            ARGS, target(), "frozen-working", parsed, now
        )
        self.assertEqual(decision, "wait")
        self.assertGreater(until, now)
        self.assertIn("scheduled wake", reason)

    def test_goal_continuation_parses_full_and_truncated(self):
        now = NOW
        full = W.pane_context("goal continues in 1m 2s · next", now)
        self.assertAlmostEqual(full["wake_epoch"], now + 62)
        cut = W.pane_context("goal continues in 4m 1...", now)
        self.assertAlmostEqual(cut["wake_epoch"], now + 240)

    def test_running_dag_defers(self):
        text = " ▶ 1024-rule study phase 1: running wave 1/1 3/4 done, 1 running"
        decision, until, reason = verdict("frozen-working", text, NOW)
        self.assertEqual(decision, "wait")
        self.assertEqual(until, NOW + 180)
        self.assertIn("active work", reason)

    def test_compaction_defers(self):
        text = " Compacting context... (esc to cancel)\n Working (5s • esc to interrupt)"
        decision, _, reason = verdict("frozen-working", text, NOW)
        self.assertEqual(decision, "wait")
        self.assertIn("active work", reason)

    def test_goal_achieved_is_never_recovered(self):
        state = target()
        state.defers["frozen-working"] = ARGS.context_max_defers
        decision, _, reason = verdict(
            "frozen-working", " Goal achieved (34m)\n Working (5s)", NOW, state
        )
        self.assertEqual(decision, "wait")
        self.assertIn("goal achieved", reason)

    def test_bare_frozen_working_recovers(self):
        decision, _, reason = verdict(
            "frozen-working", " Working (120s • esc to interrupt)", NOW
        )
        self.assertEqual(decision, "recover")
        self.assertIn("no scheduled wake", reason)

    def test_recent_progress_defers(self):
        state = target()
        state.last_progress = NOW - 50
        decision, _, reason = W.infer_context(
            ARGS, state, "frozen-working", W.pane_context(" Working (5s)", NOW), NOW
        )
        self.assertEqual(decision, "wait")
        self.assertIn("progress 50s ago", reason)

    def test_recent_session_write_defers(self):
        with tempfile.NamedTemporaryFile(suffix=".jsonl") as handle:
            handle.write(b"{}")
            handle.flush()
            state = target(handle.name)
            decision, _, reason = W.infer_context(
                ARGS, state, "frozen-working", W.pane_context(" Working (5s)", time.time()), time.time()
            )
        self.assertEqual(decision, "wait")
        self.assertIn("session written", reason)

    def test_deferral_budget_exhausts(self):
        state = target()
        state.defers["frozen-working"] = ARGS.context_max_defers
        decision, _, reason = verdict(
            "frozen-working", " Compacting context...", NOW, state
        )
        self.assertEqual(decision, "recover")
        self.assertIn("deferrals exhausted", reason)

    def test_gate_defers_three_times_then_recovers(self):
        original_log = W.log
        W.log = lambda _message: None
        try:
            state = target()
            text = " Compacting context...\n Working (5s • esc to interrupt)"
            evidence = {"pane_status": "Working"}
            first = W.gate_action(ARGS, state, "frozen-working", evidence, text, NOW)
            self.assertIsNone(first)
            self.assertEqual(state.defers["frozen-working"], 1)
            self.assertEqual(state.defer_until, NOW + 180)
            early = W.gate_action(ARGS, state, "frozen-working", evidence, text, NOW + 100)
            self.assertIsNone(early)
            self.assertEqual(state.defers["frozen-working"], 1)
            second = W.gate_action(ARGS, state, "frozen-working", evidence, text, NOW + 181)
            self.assertIsNone(second)
            self.assertEqual(state.defers["frozen-working"], 2)
            third = W.gate_action(ARGS, state, "frozen-working", evidence, text, NOW + 362)
            self.assertIsNone(third)
            self.assertEqual(state.defers["frozen-working"], 3)
            final = W.gate_action(ARGS, state, "frozen-working", evidence, text, NOW + 543)
            self.assertIsNotNone(final)
            self.assertEqual(final["context_verdict"][:24], "context deferrals exhaus")
            self.assertIn("context", final)
        finally:
            W.log = original_log


if __name__ == "__main__":
    unittest.main()
