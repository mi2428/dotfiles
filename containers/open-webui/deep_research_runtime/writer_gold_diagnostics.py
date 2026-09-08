"""Explain failures of the public quote-only writer micro, without retaining model text.

These counters never accept a draft or infer entailment for an unrecognized clause.
"""

import re


def diagnose_draft(draft: dict, facts: dict[str, set[str]]) -> dict[str, int]:
    def normalized(text: str) -> str:
        return " ".join(text.strip().removesuffix(".").split()).casefold()

    known = {normalized(text): text for texts in facts.values() for text in texts}
    result: dict[str, int] = dict.fromkeys(
        (
            "known_clauses",
            "format_only_clauses",
            "unclassified_clauses",
            "misattributed_known_clauses",
            "irrelevant_citations",
            "unknown_citations",
            "uncited_blocks",
            "table_layout_mismatches",
            "table_title_mismatches",
            "introduced_numbers",
        ),
        0,
    )
    blocks = [
        (item["text"], item["source_ids"])
        for key in ("paragraphs", "bullets")
        for item in draft[key]
    ]
    texts = [text for text, _ in blocks]
    for table in draft["tables"]:
        result["table_title_mismatches"] += table.get("title") not in {
            None,
            "",
            "Capacity comparison",
        }
        result["table_layout_mismatches"] += table["headers"] != ["Record", "Fact"]
        texts.extend([table.get("title") or "", *table["headers"]])
        for row in table["rows"]:
            cells = row["cells"]
            result["table_layout_mismatches"] += (
                len(cells) != 2
                or cells[0] not in {"Amber", "Birch"}
                or not cells[-1].startswith(cells[0] + " ")
            )
            blocks.append((cells[-1], row["source_ids"]))
            texts.extend(cells)
    numbers = {value for text in known.values() for value in re.findall(r"\d+", text)}
    result["introduced_numbers"] = sum(
        value not in numbers for text in texts for value in re.findall(r"\d+", text)
    )
    for text, ids in blocks:
        clauses = re.split(r"(?<=\.)\s+", text.strip())
        matched = [known.get(normalized(part)) for part in clauses]
        result["unknown_citations"] += sum(source not in facts for source in ids)
        result["uncited_blocks"] += not ids
        for part, fact in zip(clauses, matched, strict=True):
            if fact is None:
                result["unclassified_clauses"] += 1
                continue
            result["known_clauses"] += 1
            result["format_only_clauses"] += part != fact
            result["misattributed_known_clauses"] += not any(
                fact in facts.get(source, set()) for source in ids
            )
        if all(matched):
            result["irrelevant_citations"] += sum(
                source in facts and not any(fact in facts[source] for fact in matched)
                for source in ids
            )
    return result
