import importlib.util
import os
import sys
import unittest
from pathlib import Path

REPORT = (
    Path(__file__).resolve().parents[2]
    / "home/files/agents/skills/omo-watch/report.py"
)


def load_report():
    spec = importlib.util.spec_from_file_location("omo_watch_report_test", REPORT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


R = load_report()
PANE = "\n".join(
    [
        "   ▶ Aurora TB 5K2K phase1 investi... running wave 1/1 1/3 done, 2 running",
        "   ▶ fw-investigation · category:deep-low · Let me start by reading the context files. · 17m 42s",
        "   ✓ e1-prep · category:unspecified-low · 11m 41s",
        "   Now: fw-investigation の完了を待つ",
        "   Next: パッチを当ててビルド検証",
        "~/io/aurora-tb-5k2k-fix • 243K/1M (23.2%) (auto)   preview/GLM-5.3-Flash • effort medium (shift+tab)",
        "(😺 OmO Native by Q Kim) Pursuing goal (20m) ▰▰▰▱▱▱▱▱▱▱▱▱ goal continues in 3m 23s · 1 omo dag on duty",
    ]
)


class ParsePaneTest(unittest.TestCase):
    def test_extracts_footer_and_dag_and_goal(self):
        facts = R.parse_pane(PANE)
        self.assertEqual(facts["ctx"], "243K/1M(23.2%)")
        self.assertEqual(facts["effort"], "medium")
        self.assertEqual(facts["dag"], "1/3 done,2 running")
        self.assertEqual(facts["active"], "fw-investigation 17m 42s")
        self.assertTrue(facts["goal"].startswith("Pursuing goal"))
        self.assertEqual(facts["intent_now"], "fw-investigation の完了を待つ")
        self.assertEqual(facts["intent_next"], "パッチを当ててビルド検証")

    def test_empty_pane_yields_no_facts(self):
        self.assertEqual(R.parse_pane(""), {})

    def test_active_label_skips_finished_items(self):
        facts = R.parse_pane("   ✓ e1-prep · category:unspecified-low · 11m 41s")
        self.assertNotIn("active", facts)


class RenderTest(unittest.TestCase):
    def test_single_line_has_progress_and_watch_state(self):
        facts = R.parse_pane(PANE)
        line = R.render(
            "t7s",
            {"state": "working", "pid": "bun:123"},
            facts,
            "+4096B/600s",
            "heartbeat: t7s:working",
        )
        self.assertTrue(line.startswith("REPORT "))
        self.assertEqual(line.count("\n"), 0)
        for needle in (
            "pane=t7s",
            "state=working",
            "pid=bun:123",
            "ctx=243K/1M(23.2%) effort=medium",
            "session=+4096B/600s",
            "dag=1/3 done,2 running",
            "active=fw-investigation 17m 42s",
            "watch=heartbeat: t7s:working",
        ):
            self.assertIn(needle, line)

    def test_render_omits_missing_pid_and_growth(self):
        line = R.render("t7s", {"state": "idle", "pid": "-"}, {}, "", "x")
        self.assertNotIn("pid=", line)
        self.assertNotIn("session=", line)


class SessionDirTest(unittest.TestCase):
    def test_project_slug_matches_omo_layout(self):
        self.assertEqual(
            R.session_dir("/home/teo/io/aurora-tb-5k2k-fix"),
            os.path.join(
                os.path.expanduser("~"),
                ".omo/agent/sessions/--home-teo-io-aurora-tb-5k2k-fix--",
            ),
        )


if __name__ == "__main__":
    unittest.main()
