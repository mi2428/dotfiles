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

    def test_completed_direct_output_still_persists_note(self) -> None:
        patched = patch_middleware("\n".join(old for old, _new in REPLACEMENTS))

        self.assertIn(
            "if direct_results[0].get('deep_research_status') != 'failed':\n"
            "                            try:\n"
            "                                await persist_deep_research_note(",
            patched,
        )

    def test_failed_direct_output_skips_note_and_reads_status_case_insensitively(self) -> None:
        patched = patch_middleware("\n".join(old for old, _new in REPLACEMENTS))

        self.assertIn(
            "tool_response_header_items.get('x-deep-research-status', '').casefold()",
            patched,
        )
        self.assertIn(
            "tool_response_header_items.get('x-openwebui-direct-output', '').casefold() == 'true'",
            patched,
        )
        self.assertIn(
            "tool_response_header_items.get('content-type', '').casefold().startswith('text/plain')",
            patched,
        )
        self.assertIn("'deep_research_status': deep_research_status", patched)
        self.assertIn(
            "content': [{'type': 'output_text', 'text': direct_tool_output}]",
            patched,
        )


if __name__ == "__main__":
    unittest.main()
