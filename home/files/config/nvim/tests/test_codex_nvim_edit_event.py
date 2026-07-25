from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


DOTFILES_ROOT = Path(os.environ["DOTFILES_ROOT"])
BRIDGE_PATH = DOTFILES_ROOT / "home/files/libexec/dotfiles/codex-nvim-edit-event"
BRIDGE = runpy.run_path(str(BRIDGE_PATH))


class CodexNvimEditEventTest(unittest.TestCase):
    def payload(
        self,
        cwd: Path,
        command: str,
        tool_use_id: str,
        tool_name: str = "apply_patch",
    ) -> dict[str, object]:
        return {
            "cwd": str(cwd),
            "session_id": "session-test",
            "turn_id": "turn-test",
            "tool_input": {"command": command},
            "tool_name": tool_name,
            "tool_use_id": tool_use_id,
        }

    def git(self, root: Path, *arguments: str) -> None:
        subprocess.run(
            ("git", *arguments),
            cwd=root,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def init_repository(self, root: Path) -> None:
        self.git(root, "init", "-q")
        self.git(root, "config", "user.email", "codex-watch@example.invalid")
        self.git(root, "config", "user.name", "Codex Watch Test")

    def test_identical_commands_keep_independent_snapshots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            source = root / "sample.txt"
            source.write_text("before\n", encoding="utf-8")
            command = "\n".join(
                (
                    "*** Begin Patch",
                    "*** Update File: sample.txt",
                    "@@",
                    "-before",
                    "+after",
                    "*** End Patch",
                )
            )
            first = self.payload(root, command, "tool-first")
            second = self.payload(root, command, "tool-second")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](first)
                source.write_text("middle\n", encoding="utf-8")
                BRIDGE["capture_snapshot"](second)
                source.write_text("after\n", encoding="utf-8")

                second_event = BRIDGE["create_patch_event"](second)
                first_event = BRIDGE["create_patch_event"](first)

            self.assertEqual(second_event["changes"][0]["hunks"][0]["old_count"], 1)
            self.assertEqual(first_event["changes"][0]["hunks"][0]["old_count"], 1)

    def test_failed_add_does_not_report_existing_file_as_new(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            source = root / "existing.txt"
            source.write_text("keep\n", encoding="utf-8")
            command = "\n".join(
                (
                    "*** Begin Patch",
                    "*** Add File: existing.txt",
                    "+replacement",
                    "*** End Patch",
                )
            )
            payload = self.payload(root, command, "tool-add")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(event["changes"], [])

    def test_eof_newline_only_change_is_a_hunk(self) -> None:
        hunks = BRIDGE["changed_hunks"]("line\n", "line")
        self.assertEqual(len(hunks), 1)

    def test_bash_snapshot_reports_only_changes_made_by_the_command(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            existing = root / "existing.txt"
            changed = root / "changed.txt"
            existing.write_text("original\n", encoding="utf-8")
            changed.write_text("before\n", encoding="utf-8")
            self.init_repository(root)
            self.git(root, "add", ".")
            self.git(root, "commit", "-qm", "initial")
            existing.write_text("already dirty\n", encoding="utf-8")
            payload = self.payload(root, "formatter", "tool-bash", "Bash")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                changed.write_text("after\n", encoding="utf-8")
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(
                [Path(change["path"]).name for change in event["changes"]],
                ["changed.txt"],
            )
            self.assertEqual(event["changes"][0]["hunks"][0]["start_line"], 1)

    def test_bash_snapshot_tracks_edits_to_an_already_dirty_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            source = root / "sample.txt"
            source.write_text("committed\n", encoding="utf-8")
            self.init_repository(root)
            self.git(root, "add", ".")
            self.git(root, "commit", "-qm", "initial")
            source.write_text("dirty before\n", encoding="utf-8")
            payload = self.payload(root, "formatter", "tool-dirty", "Bash")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                source.write_text("dirty after\n", encoding="utf-8")
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(len(event["changes"]), 1)
            self.assertEqual(event["changes"][0]["hunks"][0]["old_count"], 1)

    def test_bash_snapshot_tracks_a_file_changed_and_staged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            source = root / "sample.txt"
            source.write_text("before\n", encoding="utf-8")
            self.init_repository(root)
            self.git(root, "add", ".")
            self.git(root, "commit", "-qm", "initial")
            payload = self.payload(
                root, "formatter && git add sample.txt", "tool-stage", "Bash"
            )

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                source.write_text("after\n", encoding="utf-8")
                self.git(root, "add", "sample.txt")
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(len(event["changes"]), 1)
            self.assertEqual(event["changes"][0]["kind"], "update")

    def test_bash_snapshot_tracks_new_untracked_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            self.init_repository(root)
            payload = self.payload(root, "generate", "tool-new", "Bash")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                (root / "generated.txt").write_text("new\n", encoding="utf-8")
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(len(event["changes"]), 1)
            self.assertEqual(event["changes"][0]["kind"], "add")

    def test_bash_outside_git_emits_an_empty_patch_event(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            events = root / "events"
            payload = self.payload(root, "touch sample.txt", "tool-no-git", "Bash")

            with patch.dict(os.environ, {"CODEX_NVIM_EDIT_EVENT_DIR": str(events)}):
                BRIDGE["capture_snapshot"](payload)
                (root / "sample.txt").write_text("new\n", encoding="utf-8")
                event = BRIDGE["create_patch_event"](payload)

            self.assertEqual(event["changes"], [])

    def test_hook_install_is_non_destructive_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            codex_home = Path(temporary)
            hooks_path = codex_home / "hooks.json"
            document = {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {
                                    "command": "herdr session",
                                    "timeout": 10,
                                    "type": "command",
                                }
                            ]
                        }
                    ],
                    "PreToolUse": [
                        {
                            "hooks": [
                                {
                                    "command": '"$HOME/.local/bin/codex-nvim-edit-event" pre',
                                    "timeout": 3,
                                    "type": "command",
                                }
                            ],
                            "matcher": "^apply_patch$",
                        },
                        {
                            "hooks": [
                                {
                                    "command": "custom pre-hook",
                                    "timeout": 3,
                                    "type": "command",
                                }
                            ],
                            "matcher": "custom",
                        },
                    ],
                }
            }
            hooks_path.write_text(json.dumps(document), encoding="utf-8")

            with patch.dict(os.environ, {"CODEX_HOME": str(codex_home)}):
                BRIDGE["install_hooks"](True)
                installed = hooks_path.read_bytes()
                BRIDGE["install_hooks"](True)

            self.assertEqual(installed, hooks_path.read_bytes())
            hooks = json.loads(installed)["hooks"]
            self.assertEqual(hooks["SessionStart"], document["hooks"]["SessionStart"])
            self.assertTrue(
                any(item.get("matcher") == "custom" for item in hooks["PreToolUse"])
            )
            self.assertTrue(
                any(
                    item.get("matcher") == "^apply_patch$"
                    for item in hooks["PreToolUse"]
                )
            )
            self.assertTrue(
                any(item.get("matcher") == "^Bash$" for item in hooks["PreToolUse"])
            )
            self.assertTrue(
                any(
                    item.get("matcher") == "^apply_patch$"
                    for item in hooks["PostToolUse"]
                )
            )
            self.assertTrue(
                any(item.get("matcher") == "^Bash$" for item in hooks["PostToolUse"])
            )
            self.assertEqual(hooks["PreToolUse"][0]["hooks"][0]["timeout"], 3)
            self.assertEqual(hooks["PostToolUse"][0]["hooks"][0]["timeout"], 3)
            managed_commands = [
                handler["command"]
                for event in ("PreToolUse", "PostToolUse", "Stop")
                for definition in hooks[event]
                for handler in definition["hooks"]
                if "codex-nvim-edit-event" in handler["command"]
            ]
            self.assertTrue(managed_commands)
            self.assertTrue(
                all(
                    "/.local/libexec/dotfiles/" in command
                    for command in managed_commands
                )
            )


if __name__ == "__main__":
    unittest.main()
