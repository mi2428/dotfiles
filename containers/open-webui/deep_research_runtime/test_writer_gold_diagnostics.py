import unittest

from writer_gold_diagnostics import diagnose_draft

AMBER = "Amber stores 120 maps."
BIRCH = "Birch stores 80 maps."
FACTS = {"S1": {AMBER}, "S2": {BIRCH}, "S3": {AMBER, BIRCH}}


class WriterGoldDiagnosticsTests(unittest.TestCase):
    def test_failure_categories_do_not_conflate_format_and_citation_errors(self) -> None:
        def check(text: str, ids: list[str]) -> dict[str, int]:
            return diagnose_draft(
                {"paragraphs": [{"text": text, "source_ids": ids}], "bullets": [], "tables": []},
                FACTS,
            )

        good = check(AMBER, ["S1"])
        self.assertEqual(good["known_clauses"], 1)
        self.assertEqual(sum(good.values()), 1)
        formatting = check("amber  stores 120 maps", ["S1"])
        self.assertEqual(formatting["format_only_clauses"], 1)
        self.assertEqual(formatting["misattributed_known_clauses"], 0)
        wrong_source = check(AMBER, ["S2"])
        self.assertEqual(wrong_source["misattributed_known_clauses"], 1)
        self.assertEqual(wrong_source["irrelevant_citations"], 1)
        self.assertEqual(check(AMBER, ["S1", "S2"])["irrelevant_citations"], 1)
        self.assertEqual(check(AMBER, ["S999"])["unknown_citations"], 1)
        self.assertEqual(check(AMBER, [])["uncited_blocks"], 1)
        unknown = check("PUBLIC_PRIVATE_SENTINEL 999", ["S1"])
        self.assertEqual(unknown["unclassified_clauses"], 1)
        self.assertEqual(unknown["introduced_numbers"], 1)
        self.assertEqual(unknown["misattributed_known_clauses"], 0)
        self.assertNotIn("SENTINEL", str(unknown))
        self.assertTrue(all(type(value) is int for value in unknown.values()))
        combined = check(AMBER + "\n" + BIRCH, ["S3"])
        self.assertEqual(combined["known_clauses"], 2)
        self.assertEqual(sum(combined.values()), 2)
        table = diagnose_draft(
            {
                "paragraphs": [],
                "bullets": [],
                "tables": [
                    {
                        "title": "Inventory",
                        "headers": ["Record", "Stock"],
                        "rows": [{"cells": ["Amber", "120 maps"], "source_ids": ["S1"]}],
                    }
                ],
            },
            FACTS,
        )
        self.assertEqual(table["table_title_mismatches"], 1)
        self.assertEqual(table["table_layout_mismatches"], 2)
        self.assertEqual(table["unclassified_clauses"], 1)
        self.assertEqual(table["introduced_numbers"], 0)


if __name__ == "__main__":
    unittest.main()
