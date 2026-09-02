from __future__ import annotations

import asyncio
from dataclasses import replace
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import aiohttp
import httpx

from test_support import (
    FakeResponse,
    FakeSession,
    RuntimeTestCase,
    deep_answer,
    deep_findings,
    deep_section_body,
    make_state,
    report_sections,
    rt,
)


class RuntimeContractTests(RuntimeTestCase):
    def test_openapi_auth_validation_and_exact_cached_markdown(self) -> None:
        schema = rt.app.openapi()
        self.assertEqual(set(schema["paths"]), {"/research"})
        operation = schema["paths"]["/research"]["post"]
        self.assertEqual(operation["operationId"], "deep_research")
        self.assertEqual(operation["security"], [{"HTTPBearer": []}])

        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                self.assertEqual(
                    (await client.post("/research", json={"query": "x"})).status_code, 401
                )
                headers = {"Authorization": "Bearer test-api-key"}
                self.assertEqual(
                    (
                        await client.post("/research", headers=headers, json={"query": ""})
                    ).status_code,
                    422,
                )
                cached = rt.ResearchResponse(
                    research_id="rid",
                    answer_markdown='Exact `_meta["key"]` [S1]',
                    findings=[rt.CitationModel(claim="claim", source_ids=["S1"])],
                    sources=[
                        rt.SourceModel(
                            id="S1",
                            url="https://example.com",
                            hash="a" * 64,
                            relevance=1,
                            source_quality=1,
                        )
                    ],
                    limitations=[],
                    stats={},
                ).model_dump()
                with patch.object(
                    rt,
                    "reserve_run",
                    new=AsyncMock(return_value=("rid", "hash", cached, None)),
                ):
                    response = await client.post(
                        "/research", headers=headers, json={"query": "cached"}
                    )
                self.assertEqual(response.text, cached["answer_markdown"])
                self.assertEqual(response.headers["x-openwebui-direct-output"], "true")

        asyncio.run(run())

    def test_report_assembly_and_generic_source_ranking(self) -> None:
        source = rt.SourceModel(
            id="S1",
            url="https://example.com/a_(b)",
            title="Line 1\nLine 2",
            hash="a" * 64,
            relevance=1,
            source_quality=0.8,
        )
        answer = rt.append_limitations_section(
            rt.format_public_citations("Answer [S1]"),
            [rt.format_public_citations("S6、S15、S16は制約", bare=True)],
        )
        answer = rt.append_sources_section(answer, [source])
        self.assertIn("Answer [1]", answer)
        self.assertIn("- [6][15][16]は制約", answer)
        self.assertIn("[1] Line 1 Line 2 — <https://example.com/a_(b)>", answer)
        self.assertLess(answer.index("## Limitations"), answer.index("## Sources"))
        self.assertEqual(rt.source_quality("https://www.mhlw.go.jp/example"), 0.9)
        self.assertEqual(rt.source_quality("https://docs.example.com/reference"), 0.8)
        self.assertEqual(rt.source_quality("https://vendor.example/news"), 0.5)

    def test_answer_cap_leaves_a_full_report_envelope_for_final_assembly(self) -> None:
        budget = rt.make_budget("deep")
        self.assertEqual(
            rt.MAX_ANSWER_CHARS,
            rt.MAX_REPORT_SECTIONS * rt.MAX_REPORT_SECTION_CHARS * 2,
        )
        self.assertEqual(
            (
                rt.MAX_REPORT_SECTIONS,
                rt.DEEP_MIN_SECTIONS,
                rt.DEEP_MIN_ANSWER_CHARS,
                rt.DEEP_MIN_CITED_SOURCES,
                rt.DEEP_MIN_FINDINGS,
                rt.DEEP_MIN_LIMITATIONS,
            ),
            (24, 24, 77_000, 26, 15, 8),
        )
        self.assertEqual(
            (budget.searches, budget.search_limit, budget.evidence, budget.minimum_evidence),
            (96, 192, 60, 30),
        )
        self.assertLessEqual(rt.STRUCTURED_DEEP_SECTION_CHARS, rt.MAX_REPORT_SECTION_CHARS)

    def test_deep_contract_and_hard_limit_tail_salvage(self) -> None:
        budget = rt.make_budget("deep")
        source_count = budget.minimum_evidence
        limitations = [f"Limitation {index}" for index in range(1, rt.DEEP_MIN_LIMITATIONS + 1)]
        state = make_state(source_count)
        response = rt.validate_submit_report(
            "rid",
            state,
            source_count,
            deep_answer(source_count),
            deep_findings(source_count),
            limitations,
            budget,
            "deep",
        )
        self.assertEqual(len(response.sources), source_count)

        under_cited = rt.DEEP_MIN_CITED_SOURCES - 1
        with self.assertRaisesRegex(ValueError, "cited sources"):
            rt.validate_submit_report(
                "rid",
                state,
                source_count,
                deep_answer(under_cited),
                deep_findings(under_cited),
                limitations,
                budget,
                "deep",
            )

        salvage = make_state(rt.DEEP_MIN_CITED_SOURCES)
        salvage.searched_queries = {f"query {index}" for index in range(budget.search_limit)}
        research = rt.ResearchRequest(query="generic research", depth="deep")
        self.assertTrue(rt.evidence_ready_for_report(salvage, research, budget))
        salvaged = rt.validate_submit_report(
            "rid",
            salvage,
            salvage.evidence_revision,
            deep_answer(rt.DEEP_MIN_CITED_SOURCES),
            deep_findings(rt.DEEP_MIN_CITED_SOURCES),
            limitations,
            budget,
            "deep",
        )
        self.assertEqual(len(salvaged.sources), rt.DEEP_MIN_CITED_SOURCES)

        unusable = replace(
            state, evidence=[replace(state.evidence[0], relevance=0), *state.evidence[1:]]
        )
        with self.assertRaisesRegex(ValueError, "minimum evidence"):
            rt.validate_submit_report(
                "rid",
                unusable,
                source_count,
                deep_answer(source_count),
                deep_findings(source_count),
                limitations,
                budget,
                "deep",
            )

    def test_explicit_deliverables_drive_section_loop_without_domain_assumptions(self) -> None:
        budget = rt.make_budget("deep")
        source_count = budget.minimum_evidence
        limitations = [f"Limitation {index}" for index in range(1, rt.DEEP_MIN_LIMITATIONS + 1)]
        state = make_state(source_count)
        state.report_sections = report_sections(source_count)
        comparison = rt.ResearchRequest(query="方式Aと方式Bの違い", depth="deep")
        self.assertTrue(rt.report_needs_section(state, comparison))

        state.report_sections[0] = rt.ReportSection(
            "方式の比較",
            "| 方式 | 評価 |\n|---|---|\n| A | 根拠 |\n\n" + deep_section_body(source_count),
            source_count,
        )
        error = rt.report_request_error(
            rt.assemble_report_sections(state.report_sections),
            "deep",
            comparison.query,
        )
        self.assertIn(
            'section "方式の比較"',
            error or "",
        )

        state.report_sections[0] = rt.ReportSection(
            "方式の比較",
            "| 方式 | 評価 |\n|---|---|\n| A | 根拠 [S1] |\n\n" + deep_section_body(source_count),
            source_count,
        )
        self.assertFalse(rt.report_needs_section(state, comparison))

        answer = rt.assemble_report_sections(state.report_sections)
        with self.assertRaisesRegex(ValueError, "benchmark analysis"):
            rt.validate_submit_report(
                "rid",
                state,
                source_count,
                answer,
                deep_findings(source_count),
                limitations,
                budget,
                "deep",
                "第三者ベンチマーク",
            )
        with self.assertRaisesRegex(ValueError, "12-month roadmap"):
            rt.validate_submit_report(
                "rid",
                state,
                source_count,
                answer.replace("## Section 2", "## ロードマップ", 1),
                deep_findings(source_count),
                limitations,
                budget,
                "deep",
                "12か月ロードマップ",
            )
        hiring = rt.validate_submit_report(
            "rid",
            state,
            source_count,
            answer,
            deep_findings(source_count),
            limitations,
            budget,
            "deep",
            "人材の採用判断を支援してください",
        )
        self.assertNotIn("12か月ロードマップ", hiring.answer_markdown)

    def test_relevance_is_lexical_auditable_and_refresh_invalidates_stale_report(self) -> None:
        table = "\n".join(f"試行{index}回 性能{300 + index}点" for index in range(12))
        excerpt, relevance = rt.select_relevant_excerpt(table, "性能 指標", None)
        self.assertEqual(excerpt, table)
        self.assertGreater(relevance, 0)
        _, unrelated = rt.select_relevant_excerpt(
            "This substantive document contains enough readable alphabetic content but discusses "
            "a completely different operational topic that cannot support the requested claim.",
            "unrelated-keyword",
            None,
        )
        self.assertEqual(unrelated, 0)

        state = make_state(1, "quick")
        state.evidence = [replace(state.evidence[0], excerpt=table, relevance=0, search_query="")]
        state.report_sections = [rt.ReportSection("Saved", "Claim [S1]", 1)]
        state.final_response = {"cached": True}
        changed = rt.refresh_evidence_relevance(
            state, rt.ResearchRequest(query="性能 指標", depth="quick")
        )
        self.assertTrue(changed)
        self.assertGreater(state.evidence[0].relevance, 0)
        self.assertFalse(state.report_sections)
        self.assertIsNone(state.final_response)

    def test_finalization_excludes_unusable_evidence_and_prunes_unsafe_sections(self) -> None:
        state = make_state(2)
        state.evidence[1] = replace(state.evidence[1], relevance=0)
        state.report_sections = [
            rt.ReportSection("Safe", "Supported claim [S1]", state.evidence_revision),
            rt.ReportSection("Unsafe", "Unsupported claim [S2]", state.evidence_revision),
        ]
        state.stats["report_sections"] = 2

        self.assertTrue(rt.prune_unusable_report_sections(state))
        self.assertEqual([section.heading for section in state.report_sections], ["Safe"])
        context = rt.finalization_context(rt.ResearchRequest(query="Evidence"), state)
        self.assertEqual([item["id"] for item in context["evidence"]], ["S1"])
        with self.assertRaisesRegex(ValueError, "unusable source IDs"):
            rt.store_report_section(
                state,
                rt.ResearchRequest(query="Evidence"),
                state.evidence_revision,
                "Unsafe replacement",
                "Unsupported claim [S2] " * 50,
            )

    def test_extraction_persists_search_and_fetch_provenance(self) -> None:
        async def run() -> None:
            raw = b"""<html><head><title>Evidence</title></head><body><article><p>
            Performance evidence documents the measured result with enough substantive text
            to validate the extracted passage and its direct relevance.
            </p></article></body></html>"""
            with patch.object(
                rt,
                "fetch_bytes",
                new=AsyncMock(return_value=(raw, "https://example.com/result", "text/html")),
            ):
                evidence = await rt.extract_evidence(
                    rt.SearchResult(
                        "https://example.com/result",
                        "Evidence",
                        "snippet",
                        "engine",
                        "performance evidence",
                    ),
                    "broad request",
                    "measured result",
                )
            self.assertEqual(evidence.search_query, "performance evidence")
            self.assertEqual(evidence.purpose, "measured result")
            self.assertGreater(evidence.relevance, 0)
            state = make_state(0, "quick")
            state.evidence = [replace(evidence, id="S1")]
            snapshot = rt.run_state_snapshot(state)
            self.assertEqual(snapshot["evidence_ledger"][0]["search_query"], "performance evidence")

        asyncio.run(run())

    def test_idempotency_resume_cached_completion_and_cumulative_stats(self) -> None:
        async def run() -> None:
            request = rt.ResearchRequest(query="sample", depth="quick")
            key = rt.normalize_idempotency_key("message")
            research_id, request_hash, cached, snapshot = await rt.reserve_run(
                self.runtime, request, key
            )
            self.assertIsNone(cached)
            self.assertIsNone(snapshot)
            state = make_state(1, "quick")
            state.stats.update(
                model_transient_recoveries=4,
                research_continuations=3,
                structured_output_retries=2,
            )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "failed",
                research_id,
                request_hash,
                error="failed",
                state=rt.run_state_snapshot(state),
            )
            resumed_id, _, resumed_cached, resumed_snapshot = await rt.reserve_run(
                self.runtime, request, key
            )
            self.assertEqual(resumed_id, research_id)
            self.assertIsNone(resumed_cached)
            loaded = rt.load_run_state(
                cast(dict[str, Any], resumed_snapshot),
                depth="quick",
                budget=rt.make_budget("quick"),
                wall_limit=rt.wall_budget_seconds("quick"),
            )
            self.assertEqual(loaded.stats["model_transient_recoveries"], 4)
            self.assertEqual(loaded.stats["research_continuations"], 3)
            self.assertEqual(loaded.stats["structured_output_retries"], 2)

            response = rt.ResearchResponse(
                research_id=research_id,
                answer_markdown="done [S1]",
                findings=[rt.CitationModel(claim="claim", source_ids=["S1"])],
                sources=[rt.source_from_evidence(state.evidence[0])],
                limitations=["none"],
                stats={},
            )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "completed",
                research_id,
                request_hash,
                response=response.model_dump(),
            )
            _, _, completed, _ = await rt.reserve_run(self.runtime, request, key)
            self.assertEqual(cast(dict[str, Any], completed)["answer_markdown"], "done [S1]")

        asyncio.run(run())

    def test_network_boundaries_block_ssrf_bad_content_and_oversize_bodies(self) -> None:
        with self.assertRaises(ValueError):
            rt.validate_public_url("http://127.0.0.1/x")
        with self.assertRaises(ValueError):
            rt.validate_public_url("http://user:pass@example.com/x")

        async def run() -> None:
            with self.assertRaises(ValueError):
                session = cast(
                    aiohttp.ClientSession,
                    FakeSession(
                        FakeResponse(headers={"Content-Type": "text/xml"}, chunks=[b"<xml/>"])
                    ),
                )
                await rt.fetch_bytes(session, "http://example.com", 100)
            with self.assertRaises(ValueError):
                response = cast(
                    aiohttp.ClientResponse,
                    FakeResponse(chunks=[b"a" * 5, b"b" * 5]),
                )
                await rt.read_bytes_with_cap(response, 5)
            with self.assertRaises(ValueError):
                session = cast(
                    aiohttp.ClientSession,
                    FakeSession(
                        FakeResponse(
                            status=302,
                            headers={"Location": "http://127.0.0.1/private"},
                        )
                    ),
                )
                await rt.fetch_bytes(session, "https://example.com/public", 100)

        asyncio.run(run())


if __name__ == "__main__":
    import unittest

    unittest.main(verbosity=2)
