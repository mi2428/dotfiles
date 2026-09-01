"""Tests for the fail-closed Open WebUI middleware patch contract."""

import unittest

from apply_direct_tool_output import REPLACEMENTS, patch_middleware, replace_once


class DirectToolOutputPatchTests(unittest.TestCase):
    def test_replace_once_rejects_missing_or_ambiguous_fragments(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "patch guard failed"):
            replace_once("source", "missing", "replacement")
        with self.assertRaisesRegex(RuntimeError, "patch guard failed"):
            replace_once("old old", "old", "new")

    def test_all_pinned_replacements_are_emitted_once(self) -> None:
        source = "\n".join(old for old, _new in REPLACEMENTS)
        patched = patch_middleware(source)

        for _old, new in REPLACEMENTS:
            self.assertEqual(patched.count(new), 1)


if __name__ == "__main__":
    unittest.main()
