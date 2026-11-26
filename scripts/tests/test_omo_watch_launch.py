import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

WATCH = (
    Path(__file__).resolve().parents[2]
    / "home/files/agents/skills/omo-watch/watch.py"
)


def load_watch():
    spec = importlib.util.spec_from_file_location("omo_watch_launch_test", WATCH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


W = load_watch()


def args_for(launch="omo", panes=(), name=None, overrides=None):
    return SimpleNamespace(
        launch=launch,
        launch_pane=dict(overrides or {}),
        pane=list(panes),
        name=name,
    )


def target(project="/tmp/project", thinking="medium", name=None):
    state = W.Target("t9x", project, name)
    state.thinking = thinking
    return state


class LaunchCommandTest(unittest.TestCase):
    def test_unnamed_target_restarts_in_its_own_project_with_footer_level(self):
        launch = W.launch_command(args_for(), "t9x", target(), "effort high")
        self.assertEqual(launch, "cd /tmp/project && omo --thinking high")
        self.assertEqual(W.launch_cwd(launch), "/tmp/project")

    def test_project_path_with_space_is_quoted(self):
        launch = W.launch_command(
            args_for(), "t9x", target(project="/tmp/a b", thinking=None), ""
        )
        self.assertEqual(launch, "cd '/tmp/a b' && omo")
        self.assertEqual(W.launch_cwd(launch), "/tmp/a b")

    def test_custom_launch_applies_to_named_pane_only(self):
        custom = "cd /other && omo --thinking max"
        named = W.launch_command(
            args_for(launch=custom, panes=["t9x"]), "t9x", target(), ""
        )
        unnamed = W.launch_command(args_for(launch=custom), "t9x", target(), "")
        self.assertEqual(named, custom)
        self.assertEqual(unnamed, "cd /tmp/project && omo --thinking medium")

    def test_custom_launch_applies_to_named_filter(self):
        custom = "cd /other && omo --thinking max"
        state = target(name="worker")
        launch = W.launch_command(
            args_for(launch=custom, name="worker"), "t9x", state, ""
        )
        self.assertEqual(launch, custom)

    def test_launch_pane_override_wins(self):
        launch = W.launch_command(
            args_for(panes=["t9x"], overrides={"t9x": "cd /x && omo"}),
            "t9x",
            target(),
            "",
        )
        self.assertEqual(launch, "cd /x && omo")

    def test_parse_args_builds_override_map(self):
        parsed = W.parse_args(
            ["--launch-pane", "t1=cd /x && omo", "--once"]
        )
        self.assertEqual(parsed.launch_pane, {"t1": "cd /x && omo"})
        self.assertEqual(parsed.launch, "omo")
        self.assertEqual(W.parse_args([]).launch_pane, {})

    def test_parse_args_rejects_malformed_override(self):
        with self.assertRaises(SystemExit):
            W.parse_args(["--launch-pane", "t1"])


class ClaimTest(unittest.TestCase):
    def setUp(self):
        self.old_claims = W.CLAIMS
        self.tmp = tempfile.TemporaryDirectory()
        W.CLAIMS = self.tmp.name

    def tearDown(self):
        W.CLAIMS = self.old_claims
        self.tmp.cleanup()

    def test_second_claim_reports_the_holder(self):
        fd, holder, error = W.claim_target("abc")
        self.assertIsNotNone(fd)
        self.assertIsNone(holder)
        self.assertIsNone(error)
        second, holder, error = W.claim_target("abc")
        self.assertIsNone(second)
        self.assertEqual(holder, os.getpid())
        self.assertIsNone(error)
        state = W.Target("abc", "/tmp/project", None, claim_fd=fd)
        W.release_claim(state)
        self.assertIsNone(state.claim_fd)
        third, holder, _ = W.claim_target("abc")
        self.assertIsNotNone(third)
        self.assertIsNone(holder)
        os.close(third)

    def test_unusable_claim_dir_degrades_to_unclaimed(self):
        W.CLAIMS = "/proc/self/no-such-dir/claims"
        fd, holder, error = W.claim_target("abc")
        self.assertIsNone(fd)
        self.assertIsNone(holder)
        self.assertTrue(error)


if __name__ == "__main__":
    unittest.main()
