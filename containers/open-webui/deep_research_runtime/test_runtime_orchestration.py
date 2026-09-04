from __future__ import annotations

import asyncio
import json
import unittest
from dataclasses import replace
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import httpx
from openai import APIError

from test_support import (
    FakeRequest,
    RuntimeTestCase,
    StructuredAgent,
    make_state,
    parse_tool_payload,
    rt,
    stable_quick_state,
)


def plan_for(research: rt.ResearchRequest) -> rt.PlanDraft:
    fragments = rt.explicit_request_fragments(research)
    requirements = [
        rt.RequirementModel(
            id="R1",
            summary=fragments[0].text,
            kind="direct",
            fragment_ids=[fragments[0].id],
        ),
        rt.RequirementModel(
            id="R2",
            summary="independent comparison evidence",
            kind="comparison",
            fragment_ids=[fragments[-1].id],
        ),
    ]
    sections = [
        rt.PlanSection(
            heading="Direct evidence",
            requirement_ids=["R1"],
        ),
        rt.PlanSection(
            heading="Comparison",
            requirement_ids=["R2"],
        ),
    ]
    return rt.PlanDraft(
        requirements=requirements,
        sections=sections,
    )


def cited(text: str, *source_ids: str) -> rt.CitedPlainText:
    return rt.CitedPlainText(text=text, source_ids=list(source_ids))


def section(
    *paragraphs: rt.CitedPlainText,
    bullets: list[rt.CitedPlainText] | None = None,
    tables: list[rt.ReportTable] | None = None,
) -> rt.SectionContentDraft:
    return rt.SectionContentDraft(
        paragraphs=list(paragraphs),
        bullets=bullets or [],
        tables=tables or [],
    )


def comparison_section(text: str, *source_ids: str) -> rt.SectionContentDraft:
    return section(
        cited(text, *source_ids),
        tables=[
            rt.ReportTable(
                headers=["Comparison", "Evidence"],
                rows=[rt.ReportTableRow(cells=["Compared", text], source_ids=list(source_ids))],
            )
        ],
    )


class RuntimeOrchestrationTests(RuntimeTestCase):
    def test_standard_agent_path_completes_without_deep_loop(self) -> None:
        class StandardAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                return SimpleNamespace(
                    stop_reason="end_turn", message={"role": "assistant", "content": []}
                )

        structured = StructuredAgent(
            [
                section(cited("Answer supported by evidence", "S1", "S2")),
            ]
        )

        async def run() -> None:
            state = make_state(4, "standard")
            rt.set_collection_decision(state, "target_reached")
            with (
                patch.object(rt, "build_research_agent", return_value=StandardAgent()),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="standard"),
                    "rid",
                    "standard-key",
                    rt.run_state_snapshot(state),
                )
            self.assertIn("Answer supported by evidence", response.answer_markdown)
            self.assertEqual(structured.models, [rt.SectionContentDraft])
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_fresh_empty_deep_state_runs_plan_query_candidate_fetch_and_coverage(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        fragments = rt.explicit_request_fragments(research)
        initial = rt.PlanDraft(
            requirements=[
                rt.RequirementModel(
                    id="R1",
                    summary="Need direct evidence",
                    kind="direct",
                    fragment_ids=[fragments[0].id],
                ),
                rt.RequirementModel(
                    id="R2",
                    summary="compare vendors",
                    kind="comparison",
                    fragment_ids=[fragments[-1].id],
                ),
            ],
            sections=[
                rt.PlanSection(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                ),
                rt.PlanSection(
                    heading="Comparison",
                    requirement_ids=["R2"],
                ),
            ],
        )
        structured = StructuredAgent(
            [
                initial,
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="direct evidence", purpose="cover R1", requirement_id="R1"
                        ),
                        rt.SearchBatchEntry(
                            query="vendor comparison independent",
                            purpose="cover R2",
                            requirement_id="R2",
                        ),
                    ]
                ),
                section(cited("Supported direct claim", "S1")),
                comparison_section("Comparison across two hosts", "S2", "S3"),
            ]
        )

        search_calls: list[str] = []
        extraction_focuses: list[str | None] = []

        async def fake_search(
            _settings: rt.Settings,
            query: str,
            _language: str | None,
            _recency_days: int | None,
            _limit: int,
        ) -> list[rt.SearchResult]:
            search_calls.append(query)
            if query == "direct evidence":
                return [rt.SearchResult("https://a.example/direct", "A", "", "engine", query)]
            return [
                rt.SearchResult("https://b.example/compare", "B", "", "engine", query),
                rt.SearchResult("https://c.example/compare", "C", "", "engine", query),
            ]

        async def fake_extract(
            result: rt.SearchResult, _query: str, focus: str | None
        ) -> rt.Evidence:
            extraction_focuses.append(focus)
            return rt.Evidence(
                url=result.url,
                title=result.title,
                publisher=result.title,
                published_at="2026-01-01",
                excerpt="Evidence supporting the requested requirement.",
                hash=(result.title.lower() * 64)[:64],
                relevance=0.9,
                source_quality=0.7,
            )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("deep must stay runtime-owned"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(side_effect=fake_search)),
                patch.object(rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "fresh-key",
                )
            self.assertEqual(search_calls[:2], ["direct evidence", "vendor comparison independent"])
            self.assertEqual(
                search_calls[2:],
                [
                    "Need direct evidence",
                    "compare vendors",
                    "Need direct evidence Direct evidence",
                    "compare vendors Comparison",
                    "Need direct evidence Need direct evidence",
                    "compare vendors Need direct evidence",
                ],
            )
            self.assertTrue(
                all(item["turns"] == rt.STRUCTURED_OUTPUT_TURNS for item in structured.limits)
            )
            self.assertEqual(response.outcome, "completed")
            self.assertEqual(
                structured.models,
                [rt.PlanDraft, rt.SearchBatchDraft, rt.SectionContentDraft, rt.SectionContentDraft],
            )
            self.assertEqual(
                extraction_focuses,
                [
                    "cover R1; Need direct evidence",
                    "cover R2; compare vendors",
                    "cover R2; compare vendors",
                ],
            )
            self.assertIn("Comparison across two hosts", response.answer_markdown)
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key='fresh-key'"
            ).fetchone()
            completed_state = json.loads(row["state_json"])
            stats = completed_state["stats"]
            self.assertEqual(row["status"], "completed")
            self.assertEqual((stats["searches"], stats["documents"], stats["evidence"]), (8, 3, 3))
            self.assertEqual(stats["query_batch_calls"], 1)
            self.assertEqual(stats["model_transient_events"], [])
            self.assertEqual(stats["operation_failure_events"], [])
            self.assertEqual(
                [item["requirement_ids"] for item in completed_state["evidence_ledger"]],
                [["R1"], ["R2"], ["R2"]],
            )

        asyncio.run(run())

    def test_search_failure_and_same_batch_duplicate_do_not_stop_other_query(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        structured = StructuredAgent(
            [
                APIError("Internal server error.", request=request, body=None),
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(query="dup", purpose="r2", requirement_id="R2"),
                        rt.SearchBatchEntry(query="dup", purpose="r2 dup", requirement_id="R2"),
                        rt.SearchBatchEntry(query="ok", purpose="r2 ok", requirement_id="R2"),
                    ]
                ),
                APIError("Internal server error.", request=request, body=None),
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(query="idle-2", purpose="r2 idle", requirement_id="R2")
                    ]
                ),
                section(cited("Supported direct claim", "S1")),
            ]
        )

        calls: list[str] = []

        async def fake_search(*_args: Any) -> list[rt.SearchResult]:
            query = cast(str, _args[1])
            calls.append(query)
            if query == "dup":
                raise OSError("search failed")
            return []

        async def run() -> None:
            with (
                self.assertLogs(rt.LOG.name, level="WARNING") as logs,
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(side_effect=fake_search)),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0.0),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "search-failure-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(calls, ["dup", "ok", "idle-2"])
            model_logs = [line for line in logs.output if "model_failure" in line]
            operation_logs = [line for line in logs.output if "operation_failure" in line]
            self.assertEqual(len(model_logs), 2)
            self.assertEqual(len(operation_logs), 1)
            self.assertTrue(
                all(
                    "reason=provider_internal_error" in line
                    and "reason_source=message" in line
                    and "exception=APIError" in line
                    and "provider_code=none" in line
                    and "message_bucket=internal_server_error" in line
                    and "role=SearchBatchDraft" in line
                    and "Internal server error" not in line
                    for line in model_logs
                )
            )
            self.assertIn("reason=os_error", operation_logs[0])
            self.assertNotIn("search failed", operation_logs[0])
            self.assertEqual(response.outcome, "degraded")
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 1)
            self.assertEqual(structured.outputs, [])
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key=?",
                ("search-failure-key",),
            ).fetchone()
            stats = json.loads(row["state_json"])["stats"]
            self.assertEqual(row["status"], "completed")
            self.assertEqual(stats["model_transient_recoveries"], 2)
            self.assertEqual(stats["model_transient_failures"]["provider_internal_error"], 2)
            self.assertEqual(len(stats["model_transient_events"]), 2)
            self.assertEqual(stats["searches"], 3)
            self.assertEqual(stats["search_failures"], 1)
            self.assertEqual(stats["duplicate_queries"], 1)
            self.assertEqual(stats["operation_failure_reasons"]["search:os_error"], 1)
            self.assertEqual(len(stats["operation_failure_events"]), 1)

        asyncio.run(run())

    def test_query_provider_exhaustion_continues_with_validated_plan_queries(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        structured = StructuredAgent(
            [
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                section(cited("Supported direct claim", "S1")),
                comparison_section("Recovered comparison", "S2", "S3"),
            ]
        )
        search_calls: list[str] = []

        async def fake_search(*args: Any) -> list[rt.SearchResult]:
            query = cast(str, args[1])
            search_calls.append(query)
            return [
                rt.SearchResult("https://b.example/2", "B", "", "engine", query),
                rt.SearchResult("https://c.example/3", "C", "", "engine", query),
            ]

        async def fake_extract(result: rt.SearchResult, *_args: Any) -> rt.Evidence:
            return rt.Evidence(
                url=result.url,
                title=result.title,
                publisher=result.title,
                published_at="2026-01-01",
                excerpt="Independent evidence supporting the comparison requirement.",
                hash=(result.title.lower() * 64)[:64],
                relevance=0.9,
                source_quality=0.7,
            )

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(side_effect=fake_search)),
                patch.object(rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0.0),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "provider-salvage-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertIn("Supported direct claim", response.answer_markdown)
            self.assertIn("Recovered comparison", response.answer_markdown)
            self.assertEqual(
                search_calls,
                [
                    "independent comparison evidence",
                    "independent comparison evidence Comparison",
                    "independent comparison evidence compare vendors",
                    "Need direct evidence",
                    "Need direct evidence Direct evidence",
                    "Need direct evidence Need direct evidence",
                    "independent comparison evidence Need direct evidence",
                    "Need direct evidence compare vendors",
                ],
            )
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key=?",
                ("provider-salvage-key",),
            ).fetchone()
            stats = json.loads(row["state_json"])["stats"]
            self.assertEqual(row["status"], "completed")
            self.assertEqual(stats["model_transient_recoveries"], 5)
            self.assertEqual(stats["model_transient_failures"]["provider_internal_error"], 6)
            self.assertEqual(len(stats["model_transient_events"]), 6)
            self.assertEqual(stats["research_salvages"], 1)
            self.assertEqual(stats["query_batch_calls"], 0)
            self.assertEqual(stats["searches"], 8)
            self.assertEqual(stats["requirement_coverage"]["R2"]["covered"], True)

        asyncio.run(run())

    def test_deterministic_query_batch_is_bounded_and_exhaustible(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))

        batch = rt.deterministic_query_batch(state, rt.DEEP_QUERY_BATCH_SIZE)

        self.assertIsNotNone(batch)
        queries = cast(rt.SearchBatchDraft, batch).queries
        self.assertEqual(len(queries), rt.DEEP_QUERY_BATCH_SIZE)
        self.assertEqual({item.requirement_id for item in queries}, {"R2"})
        self.assertEqual(len({item.query for item in queries}), len(queries))
        self.assertTrue(all(len(item.query) <= rt.MAX_QUERY_CHARS for item in queries))
        state.searched_queries.update(item.query for item in queries)
        self.assertIsNone(rt.deterministic_query_batch(state, rt.DEEP_QUERY_BATCH_SIZE))

    def test_post_floor_deterministic_queries_use_query_and_focus_without_query_model_call(
        self,
    ) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(3)
        rt.store_initial_plan(state, research, plan_for(research))
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://b.example/3"
        )
        searches: list[str] = []
        structured = StructuredAgent(
            [
                section(cited("Supported direct claim", "S1")),
                comparison_section("Compared", "S2", "S3"),
            ]
        )

        async def fake_search(*args: Any) -> list[rt.SearchResult]:
            searches.append(cast(str, args[1]))
            return []

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(side_effect=fake_search)),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "post-floor-deterministic-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertEqual(
                searches,
                [
                    "Need direct evidence",
                    "compare vendors",
                    "Need direct evidence Direct evidence",
                    "compare vendors Comparison",
                    "Need direct evidence Need direct evidence",
                    "compare vendors Need direct evidence",
                ],
            )
            self.assertEqual(structured.models, [rt.SectionContentDraft, rt.SectionContentDraft])

    def test_section_provider_exhaustion_falls_back_locally_then_next_section_succeeds(
        self,
    ) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(3)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://b.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://c.example/3"
        )
        rt.store_initial_plan(state, research, plan_for(research))
        rt.set_collection_decision(state, "voluntary_stop")
        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        structured = StructuredAgent(
            [
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                comparison_section("Recovered comparison", "S2", "S3"),
            ]
        )
        modes: list[str] = []
        finalize = rt.finalize_report

        def capture_modes(current: rt.RunState, request: rt.ResearchRequest) -> rt.FinalReport:
            modes.extend(item.mode for item in current.report_sections)
            return finalize(current, request)

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0.0),
                patch.object(rt, "finalize_report", side_effect=capture_modes),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "extractive-finalization-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Runtime extractive evidence", response.answer_markdown)
            self.assertIn("Recovered comparison", response.answer_markdown)
            self.assertEqual(modes, ["extractive", "structured"])
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 7)
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_post_floor_deadline_skips_collection_calls_and_finalizes(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(3)
        rt.store_initial_plan(state, research, plan_for(research))
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://b.example/3"
        )
        structured = StructuredAgent(
            [
                section(cited("Saved direct", "S1")),
                comparison_section("Saved comparison", "S2", "S3"),
            ]
        )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "wall_budget_seconds",
                    return_value=rt.FINALIZATION_RESERVE_SECONDS,
                ),
                patch.object(rt, "load_run_state", return_value=state),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(side_effect=AssertionError("deadline should skip search")),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(side_effect=AssertionError("deadline should skip fetch")),
                ),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "post-floor-deadline-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertIn("Saved comparison", response.answer_markdown)
            self.assertEqual(structured.models, [rt.SectionContentDraft, rt.SectionContentDraft])

        asyncio.run(run())

    def test_post_floor_deterministic_catalog_exhaustion_stays_completed(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(3)
        rt.store_initial_plan(state, research, plan_for(research))
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://b.example/3"
        )
        while True:
            batch = rt.deterministic_query_batch(
                state, rt.make_budget("deep").search_limit, research
            )
            if batch is None:
                break
            state.searched_queries.update(
                item.query for item in cast(rt.SearchBatchDraft, batch).queries
            )
        structured = StructuredAgent(
            [
                section(cited("Supported direct claim", "S1")),
                comparison_section("Compared", "S2", "S3"),
            ]
        )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(side_effect=AssertionError("catalog is exhausted")),
                ),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "post-floor-catalog-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")

        asyncio.run(run())

    def test_inactive_only_queue_does_not_block_active_deterministic_query(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(3)
        rt.store_initial_plan(state, research, plan_for(research))
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://b.example/3"
        )
        state.candidate_queue = [
            rt.Candidate("https://r2-c.example/4", "R2", "", "e", "q2", "p2", "R2")
        ]
        searches: list[str] = []
        structured = StructuredAgent(
            [
                section(cited("Supported direct claim", "S1")),
                comparison_section("Compared", "S2", "S3"),
            ]
        )

        async def fake_search(*args: Any) -> list[rt.SearchResult]:
            searches.append(cast(str, args[1]))
            return []

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(side_effect=fake_search)),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "inactive-queue-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertTrue(searches)
            self.assertEqual(searches[0], "Need direct evidence")

        asyncio.run(run())

    def test_maximal_partial_gap_semantic_fallback_is_bounded_and_continues(self) -> None:
        research = rt.ResearchRequest(query="Need evidence", depth="deep")
        state = make_state(rt.MAX_PAYLOAD_EVIDENCE_EXCERPTS)
        state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
        unsafe = "[]#|<>`*_~\\"
        summary = (unsafe * 30)[:300]
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="covered direct", kind="direct", fragment_ids=["F1"]
            ),
            *[
                rt.RequirementModel(
                    id=f"R{index}",
                    summary=summary,
                    kind="comparison",
                    fragment_ids=["F1"],
                )
                for index in range(2, 7)
            ],
            rt.RequirementModel(id="R7", summary="next direct", kind="direct", fragment_ids=["F1"]),
        ]
        requirement_ids = [item.id for item in state.requirements]
        state.evidence = [
            replace(
                item,
                relevance=0.9,
                requirement_ids=requirement_ids,
                url=f"https://same.example/{index}",
                excerpt=(unsafe * 120)[:1200],
            )
            for index, item in enumerate(state.evidence, 1)
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Partial gaps",
                requirement_ids=[f"R{index}" for index in range(1, 7)],
            ),
            rt.PlanSection(
                heading="Next section",
                requirement_ids=["R7"],
            ),
        ]
        rt.set_collection_decision(state, "voluntary_stop")
        invalid = section(cited("invalid citation", "S999"))
        structured = StructuredAgent(
            [invalid, invalid, invalid, section(cited("Next structured section", "S1"))]
        )
        saved_sections: list[rt.ReportSection] = []
        finalize = rt.finalize_report

        def capture_sections(current: rt.RunState, request: rt.ResearchRequest) -> rt.FinalReport:
            saved_sections.extend(current.report_sections)
            return finalize(current, request)

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "finalize_report", side_effect=capture_sections),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "bounded-fallback-key",
                    rt.run_state_snapshot(state),
                )
            first = saved_sections[0]
            self.assertEqual([item.mode for item in saved_sections], ["extractive", "structured"])
            self.assertLess(len(first.body), rt.MAX_REPORT_SECTION_CHARS)
            self.assertEqual(first.body.count("Runtime extractive evidence:"), 12)
            self.assertNotIn("Runtime partial evidence:", first.body)
            self.assertEqual(first.body.count("Runtime coverage gap:"), 5)
            self.assertIn(rt.safe_extractive_text(summary, 300), first.body)
            self.assertIn("Next structured section", response.answer_markdown)
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 4)

        asyncio.run(run())

    def test_gap_checkpoint_resume_continues_with_structured_section(self) -> None:
        research = rt.ResearchRequest(query="Need evidence", depth="deep")
        state = make_state(3)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        state.evidence[1] = replace(state.evidence[1], relevance=0.9, requirement_ids=[])
        state.evidence[2] = replace(state.evidence[2], relevance=0.9, requirement_ids=["R3"])
        state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
        state.requirements = [
            rt.RequirementModel(id="R1", summary="fact 1", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(id="R2", summary="fact 2", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(id="R3", summary="fact 3", kind="direct", fragment_ids=["F1"]),
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Direct evidence",
                requirement_ids=["R1"],
            ),
            rt.PlanSection(
                heading="Comparison",
                requirement_ids=["R2"],
            ),
            rt.PlanSection(
                heading="Third fact",
                requirement_ids=["R3"],
            ),
        ]
        rt.set_collection_decision(state, "voluntary_stop")
        state.last_inspected_revision = state.evidence_revision
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Direct evidence"),
            section(cited("Supported evidence", "S1")),
        )
        state.report_sections.append(
            rt.ReportSection(
                "Comparison",
                "Runtime coverage gap: fact 2 (supporting evidence unavailable).",
                state.evidence_revision,
                "fact 2",
                ["R2"],
                [],
                "gap",
            )
        )
        structured = StructuredAgent([section(cited("Third structured fact", "S3"))])

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "partial-fallback-resume-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Third structured fact", response.answer_markdown)
            self.assertEqual(structured.models, [rt.SectionContentDraft])

        asyncio.run(run())

    def test_empty_provider_result_retries_before_finalization(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        rt.set_collection_decision(state, "voluntary_stop")
        structured = StructuredAgent(
            [
                None,
                section(cited("Supported claim", "S1")),
            ]
        )

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0.0),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "empty-provider-result-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 2)

        asyncio.run(run())

    def test_deep_uses_candidate_queue_past_thirty_until_requirement_done(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(30)
        initial = plan_for(research)
        rt.store_initial_plan(state, research, initial)
        state.evidence = [
            replace(
                item,
                relevance=0.9,
                requirement_ids=["R1"],
                url=f"https://direct{index}.example/doc",
                search_query=research.query,
                purpose="Need direct evidence",
                excerpt="Need direct evidence with vendor comparison terms for runtime coverage.",
            )
            for index, item in enumerate(state.evidence, 1)
        ]
        state.last_inspected_revision = state.evidence_revision
        structured = StructuredAgent(
            [
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="independent vendor comparison",
                            purpose="cover R2",
                            requirement_id="R2",
                        )
                    ]
                ),
                section(cited("Supported direct claim", "S1")),
                comparison_section("Comparison across two hosts", "S31", "S32"),
            ]
        )

        async def fake_extract(
            result: rt.SearchResult, _query: str, _focus: str | None
        ) -> rt.Evidence:
            host = result.url.split("/")[2]
            return rt.Evidence(
                url=result.url,
                title=host,
                publisher=host,
                published_at="2026-01-01",
                excerpt="Independent comparison evidence",
                hash=(host[0] * 64),
                relevance=0.9,
                source_quality=0.7,
            )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("deep must not use tool agent"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("https://a.example/compare", "A", "", "engine"),
                            rt.SearchResult("https://b.example/compare", "B", "", "engine"),
                        ]
                    ),
                ),
                patch.object(
                    rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)
                ) as extract,
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "deep-queue-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(extract.await_count, 2)
            self.assertIn("Comparison across two hosts", response.answer_markdown)
            self.assertLess(len(response.answer_markdown), rt.MAX_ANSWER_CHARS)

        asyncio.run(run())

    def test_failed_candidate_is_not_refetched_after_resume(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        draft = rt.PlanDraft(
            requirements=[
                rt.RequirementModel(
                    id="R1", summary="Need direct evidence", kind="comparison", fragment_ids=["F1"]
                )
            ],
            sections=[
                rt.PlanSection(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                )
            ],
        )
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1"],
            url="https://a.example/existing",
            search_query=research.query,
            purpose="Need direct evidence",
            excerpt="Need direct evidence with enough matching terms for runtime coverage.",
        )
        rt.store_initial_plan(state, research, draft)
        state.failed_candidates = [
            rt.FailedCandidate("https://bad.example/doc", "timeout", "fetch")
        ]
        state.candidate_queue = [
            rt.Candidate(
                url="https://good.example/doc",
                title="good",
                snippet="",
                engine="engine",
                search_query="good query",
                purpose="cover R1",
                requirement_id="R1",
            )
        ]
        structured = StructuredAgent(
            [
                comparison_section("Supported claim", "S1", "S2"),
            ]
        )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("deep must not use tool agent"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=[])) as search,
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(
                        return_value=rt.Evidence(
                            url="https://good.example/doc",
                            title="good",
                            publisher="good",
                            published_at="2026-01-01",
                            excerpt="Direct evidence",
                            hash="b" * 64,
                            relevance=0.9,
                            source_quality=0.7,
                        )
                    ),
                ) as extract,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "resume-candidate-key",
                    rt.run_state_snapshot(state),
                )
            await_args = extract.await_args
            self.assertIsNotNone(await_args)
            if await_args is None:
                self.fail("extract_evidence was not called")
            self.assertEqual(await_args.args[0].url, "https://good.example/doc")
            self.assertNotIn(
                "https://bad.example/doc", [call.args[1] for call in search.await_args_list]
            )

        asyncio.run(run())

    def test_deferred_candidate_is_kept_after_first_fetch_failure(self) -> None:
        state = make_state(0)
        state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="Need evidence", kind="direct", fragment_ids=["F1"]
            )
        ]
        state.candidate_queue = [
            rt.Candidate(
                url="https://a.example/1",
                title="A",
                snippet="",
                engine="e",
                search_query="q",
                purpose="p",
                requirement_id="R1",
            ),
            rt.Candidate(
                url="https://b.example/2",
                title="B",
                snippet="",
                engine="e",
                search_query="q",
                purpose="p",
                requirement_id="R1",
            ),
        ]
        batch = rt.next_candidate_batch(state, rt.make_budget("deep"))
        self.assertEqual([item.url for item in batch], ["https://a.example/1"])
        self.assertEqual([item.url for item in state.candidate_queue], ["https://b.example/2"])

    def test_candidate_batch_uses_budget_instead_of_stats_depth(self) -> None:
        def queued_state(stats_depth: str) -> rt.RunState:
            state = make_state(rt.make_budget("quick").evidence)
            state.stats["depth"] = stats_depth
            state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
            state.requirements = [
                rt.RequirementModel(
                    id="R1", summary="Need evidence", kind="direct", fragment_ids=["F1"]
                )
            ]
            state.candidate_queue = [
                rt.Candidate(
                    url="https://candidate.example/1",
                    title="candidate",
                    snippet="",
                    engine="e",
                    search_query="q",
                    purpose="p",
                    requirement_id="R1",
                )
            ]
            return state

        budget = rt.make_budget("deep")
        self.assertEqual(
            rt.next_candidate_batch(queued_state("quick"), budget),
            rt.next_candidate_batch(queued_state("deep"), budget),
        )

    def test_post_floor_candidate_batch_round_robins_active_requirements_and_keeps_inactive(
        self,
    ) -> None:
        state = make_state(4)
        state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
        state.requirements = [
            rt.RequirementModel(id="R1", summary="r1", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(id="R2", summary="r2", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(id="R3", summary="r3", kind="comparison", fragment_ids=["F1"]),
        ]
        state.report_plan = [
            rt.PlanSection(heading="One", requirement_ids=["R1"]),
            rt.PlanSection(heading="Two", requirement_ids=["R2"]),
            rt.PlanSection(heading="Three", requirement_ids=["R3"]),
        ]
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1-a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://r2-a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2],
            relevance=0.9,
            requirement_ids=["R2"],
            url="https://r2-bonus.example/3",
        )
        state.evidence[3] = replace(
            state.evidence[3], relevance=0.9, requirement_ids=["R3"], url="https://r3-a.example/4"
        )
        state.evidence.append(
            replace(state.evidence[3], id="S5", hash="5" * 64, url="https://r3-b.example/5")
        )
        state.evidence_revision = len(state.evidence)
        state.stats.update(evidence=5, usable_evidence=5, documents=5, evidence_revision=5)
        state.candidate_queue = [
            rt.Candidate("https://r1-c.example/7", "R1", "", "e", "q1", "p1", "R1"),
            rt.Candidate("https://r2-c.example/8", "R2", "", "e", "q2", "p2", "R2"),
            rt.Candidate("https://r3-c.example/9", "R3", "", "e", "q3", "p3", "R3"),
        ]

        batch = rt.next_candidate_batch(state, rt.make_budget("deep"))

        self.assertEqual([item.requirement_id for item in batch], ["R1"])
        self.assertEqual(
            [item.url for item in state.candidate_queue],
            ["https://r3-c.example/9", "https://r2-c.example/8"],
        )

    def test_started_post_floor_fetch_batch_processes_all_results_before_finalize(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(4)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="Need direct evidence", kind="comparison", fragment_ids=["F1"]
            ),
            rt.RequirementModel(
                id="R2",
                summary="compare vendors",
                kind="comparison",
                fragment_ids=[state.request_fragments[-1].id],
            ),
        ]
        state.report_plan = [
            rt.PlanSection(heading="First", requirement_ids=["R1"]),
            rt.PlanSection(heading="Second", requirement_ids=["R2"]),
        ]
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1-a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R1"], url="https://r1-b.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://r2-a.example/3"
        )
        state.evidence[3] = replace(
            state.evidence[3], relevance=0.9, requirement_ids=["R2"], url="https://r2-b.example/4"
        )
        state.candidate_queue = [
            rt.Candidate("https://r1-c.example/5", "R1C", "", "e", "q1", "p1", "R1"),
            rt.Candidate("https://r2-c.example/6", "R2C", "", "e", "q2", "p2", "R2"),
        ]
        structured = StructuredAgent(
            [
                comparison_section("First", "S1", "S2", "S5"),
                comparison_section("Second", "S3", "S4", "S6"),
            ]
        )

        async def fake_extract(result: rt.SearchResult, *_args: Any) -> rt.Evidence:
            host = result.url.split("/")[2]
            return rt.Evidence(
                url=result.url,
                title=host,
                publisher=host,
                published_at="2026-01-01",
                excerpt="bonus",
                hash=(host[0] * 64),
                relevance=0.9,
                source_quality=0.7,
            )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)
                ) as extract,
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=[])),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "full-fetch-batch-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertEqual(extract.await_count, 2)
            row = self.runtime.db.execute(
                "SELECT state_json FROM research_runs WHERE idempotency_key='full-fetch-batch-key'"
            ).fetchone()
            saved = json.loads(row["state_json"])
            self.assertEqual(saved["stats"]["evidence"], 6)
            self.assertEqual(saved["stats"]["documents"], 6)

    def test_section_evidence_context_deduplicates_shared_balanced_prefix(self) -> None:
        state = make_state(rt.MAX_PAYLOAD_EVIDENCE_EXCERPTS)
        state.request_fragments = [rt.RequestFragmentModel(id="F1", text="Need evidence")]
        state.requirements = [
            rt.RequirementModel(id="R1", summary="fact", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(
                id="R2", summary="comparison", kind="comparison", fragment_ids=["F1"]
            ),
        ]
        requirement_ids = [item.id for item in state.requirements]
        state.evidence = [replace(item, requirement_ids=requirement_ids) for item in state.evidence]

        source_ids = rt.section_evidence_ids(state, requirement_ids)

        self.assertEqual(source_ids, [f"S{index}" for index in range(1, 13)])
        self.assertEqual(len(source_ids), len(set(source_ids)))

    def test_section_payload_balances_multiple_requirement_evidence(self) -> None:
        research = rt.ResearchRequest(query="need facts and compare vendors", depth="deep")
        state = make_state(3)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1",
                summary="facts",
                kind="direct",
                fragment_ids=[state.request_fragments[0].id],
            ),
            rt.RequirementModel(
                id="R2",
                summary="compare",
                kind="comparison",
                fragment_ids=[state.request_fragments[-1].id],
            ),
        ]
        state.evidence[0] = replace(
            state.evidence[0], requirement_ids=["R1"], url="https://facts.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], requirement_ids=["R2"], url="https://b.example/3"
        )
        state.report_plan = [
            rt.PlanSection(
                heading="Combined",
                requirement_ids=["R1", "R2"],
            )
        ]
        contract = rt.build_section_contract(research, state, "Combined")
        payload = rt.build_section_context(research, state, contract)
        self.assertEqual([item["id"] for item in payload["assigned_evidence"]], ["S1", "S2", "S3"])
        self.assertEqual(
            [item["assigned_source_ids"] for item in payload["section_contract"]["requirements"]],
            [["S1"], ["S2", "S3"]],
        )
        self.assertTrue(payload["section_contract"]["requires_comparison_table"])
        self.assertEqual(
            [item["requirement_ids"] for item in payload["assigned_evidence"]],
            [["R1"], ["R2"], ["R2"]],
        )

    def test_gap_finalization_returns_completed_report_with_runtime_gap_limitation(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        fragments = rt.explicit_request_fragments(research)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(
            state,
            research,
            rt.PlanDraft(
                requirements=[
                    rt.RequirementModel(
                        id="R1",
                        summary="Need direct evidence",
                        kind="direct",
                        fragment_ids=[fragments[0].id],
                    ),
                    rt.RequirementModel(
                        id="R2",
                        summary="compare vendors",
                        kind="comparison",
                        fragment_ids=[fragments[-1].id],
                    ),
                ],
                sections=[
                    rt.PlanSection(
                        heading="Direct",
                        requirement_ids=["R1"],
                    ),
                    rt.PlanSection(
                        heading="Compare",
                        requirement_ids=["R2"],
                    ),
                ],
            ),
        )
        structured = StructuredAgent(
            [
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="missing comparison evidence 1",
                            purpose="cover R2",
                            requirement_id="R2",
                        )
                    ]
                ),
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="missing comparison evidence 2",
                            purpose="cover R2",
                            requirement_id="R2",
                        )
                    ]
                ),
            ]
        )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=[])),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "gap-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Runtime coverage gap", response.answer_markdown)
            self.assertNotIn(rt.SectionContentDraft, structured.models)
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_post_floor_fetch_failures_still_finish_completed(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(4)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="Need direct evidence", kind="comparison", fragment_ids=["F1"]
            ),
            rt.RequirementModel(
                id="R2",
                summary="compare vendors",
                kind="comparison",
                fragment_ids=[state.request_fragments[-1].id],
            ),
        ]
        state.report_plan = [
            rt.PlanSection(heading="First", requirement_ids=["R1"]),
            rt.PlanSection(heading="Second", requirement_ids=["R2"]),
        ]
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1-a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R1"], url="https://r1-b.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://r2-a.example/3"
        )
        state.evidence[3] = replace(
            state.evidence[3], relevance=0.9, requirement_ids=["R2"], url="https://r2-b.example/4"
        )
        state.candidate_queue = [
            rt.Candidate("https://r1-c.example/5", "R1C", "", "e", "q1", "p1", "R1"),
            rt.Candidate("https://r2-c.example/6", "R2C", "", "e", "q2", "p2", "R2"),
        ]
        while True:
            batch = rt.deterministic_query_batch(
                state, rt.make_budget("deep").search_limit, research
            )
            if batch is None:
                break
            state.searched_queries.update(
                item.query for item in cast(rt.SearchBatchDraft, batch).queries
            )
        structured = StructuredAgent(
            [
                comparison_section("First", "S1", "S2"),
                comparison_section("Second", "S3", "S4"),
            ]
        )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(side_effect=TimeoutError("late bonus timeout")),
                ),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(side_effect=AssertionError("catalog already exhausted")),
                ),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "post-floor-fetch-failures-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")

        asyncio.run(run())

    def test_partial_gap_calls_model_once_and_appends_one_runtime_note(self) -> None:
        research = rt.ResearchRequest(query="Need facts", depth="deep")
        state = make_state(1)
        fragments = rt.explicit_request_fragments(research)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(
            state,
            research,
            rt.PlanDraft(
                requirements=[
                    rt.RequirementModel(
                        id="R1",
                        summary="Need facts",
                        kind="direct",
                        fragment_ids=[fragments[0].id],
                    ),
                    rt.RequirementModel(
                        id="R2",
                        summary="compare vendors",
                        kind="comparison",
                        fragment_ids=[fragments[0].id],
                    ),
                ],
                sections=[
                    rt.PlanSection(
                        heading="Combined",
                        requirement_ids=["R1", "R2"],
                    )
                ],
            ),
        )
        rt.set_collection_decision(state, "voluntary_stop")
        structured = StructuredAgent(
            [
                section(cited("Supported covered content", "S1")),
            ]
        )
        modes: list[str] = []
        finalize = rt.finalize_report

        def capture_modes(current: rt.RunState, request: rt.ResearchRequest) -> rt.FinalReport:
            modes.extend(item.mode for item in current.report_sections)
            return finalize(current, request)

        async def run() -> None:
            with (
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "finalize_report", side_effect=capture_modes),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "partial-gap-key",
                    rt.run_state_snapshot(state),
                )
            report = response.answer_markdown.split("\n\n## Limitations", 1)[0]
            self.assertIn("Supported covered content [1]", report)
            self.assertEqual(report.count("Runtime coverage gap:"), 1)
            self.assertEqual(response.outcome, "degraded")
            self.assertEqual(modes, ["structured"])
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 1)
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_retryable_section_semantic_error_retries_then_completes(self) -> None:
        research = rt.ResearchRequest(query="Evidence", depth="standard")
        state = make_state(4, "standard")
        rt.set_collection_decision(state, "target_reached")
        structured = StructuredAgent(
            [
                section(cited("Bad", "S9")),
                section(cited("Valid citation", "S1")),
            ]
        )

        async def run() -> None:
            with (
                patch.object(
                    rt, "build_research_agent", side_effect=AssertionError("standard only")
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "retry-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "completed")
            self.assertEqual(structured.models, [rt.SectionContentDraft, rt.SectionContentDraft])

        asyncio.run(run())

    def test_nonretryable_programmer_tool_error_is_hard_failure(self) -> None:
        async def run() -> None:
            class ToolFailureAgent:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    raise TypeError("internal bug")

            with (
                patch.object(rt, "build_research_agent", return_value=ToolFailureAgent()),
                self.assertLogs(rt.LOG.name, level="ERROR") as logs,
                self.assertRaises(TypeError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "hard-failure-key",
                )
            row = self.runtime.db.execute(
                "SELECT status, error, state_json FROM research_runs WHERE idempotency_key = ?",
                ("hard-failure-key",),
            ).fetchone()
            self.assertEqual(row["status"], "failed")
            self.assertEqual(row["error"], "internal_error")
            fatal = json.loads(row["state_json"])["stats"]["fatal_error"]
            self.assertEqual(
                fatal,
                {
                    "timestamp": fatal["timestamp"],
                    "phase": "research",
                    "reason": "internal_error",
                    "reason_source": "exception",
                    "exception": "TypeError",
                    "cause_exception": "TypeError",
                    "http_status": None,
                    "provider_code": "none",
                    "message_bucket": "none",
                    "validation_bucket": "none",
                },
            )
            self.assertNotIn("internal bug", "\n".join(logs.output))
            self.assertIn("validation_bucket=none", "\n".join(logs.output))

        asyncio.run(run())

    def test_finalization_integrity_error_does_not_retry(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        state.searched_queries = {
            f"q{index}" for index in range(rt.make_budget("deep").search_limit)
        }
        structured = StructuredAgent([section(cited("Valid citation", "S1"))])

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "store_report_section",
                    side_effect=rt.IntegrityError("hard integrity failure"),
                ),
                self.assertRaisesRegex(rt.IntegrityError, "hard integrity failure"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "integrity-fast-fail-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(structured.models.count(rt.SectionContentDraft), 1)

        asyncio.run(run())

    def test_section_one_invalid_three_times_falls_back_then_section_two_succeeds(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(3)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1"],
            url="https://direct.example/1",
            search_query=research.query,
            purpose="Need direct evidence",
            excerpt="Need direct evidence with enough matching terms for runtime coverage.",
        )
        state.evidence[1] = replace(
            state.evidence[1],
            relevance=0.9,
            requirement_ids=["R2"],
            url="https://a.example/2",
        )
        state.evidence[2] = replace(
            state.evidence[2],
            relevance=0.9,
            requirement_ids=["R2"],
            url="https://b.example/3",
        )
        draft = plan_for(research)
        rt.store_initial_plan(state, research, draft)
        structured = StructuredAgent(
            [
                rt.MaxTokensReachedException("partial"),
                rt.MaxTokensReachedException("partial"),
                rt.MaxTokensReachedException("partial"),
                comparison_section("Structured second section", "S2", "S3"),
            ]
        )
        modes: list[str] = []
        finalize = rt.finalize_report

        def capture_modes(current: rt.RunState, request: rt.ResearchRequest) -> rt.FinalReport:
            modes.extend(item.mode for item in current.report_sections)
            return finalize(current, request)

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("deep must not use tool agent"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "finalize_report", side_effect=capture_modes),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "exhaustion-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(modes, ["extractive", "structured"])
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Runtime extractive evidence", response.answer_markdown)
            self.assertIn("Structured second section", response.answer_markdown)
            self.assertEqual(structured.models, [rt.SectionContentDraft] * 4)
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_evidence_cap_reached_with_uncovered_requirement_finalizes_degraded(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(rt.make_budget("deep").evidence)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1"],
            search_query=research.query,
            purpose="Need direct evidence",
        )
        rt.store_initial_plan(state, research, plan_for(research))
        structured = StructuredAgent([section(cited("Structured first section", "S1"))])

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "all-sections-fallback-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Structured first section", response.answer_markdown)
            self.assertIn("Runtime coverage gap", response.answer_markdown)
            self.assertEqual(structured.outputs, [])

        asyncio.run(run())

    def test_mixed_section_validation_failures_keep_each_safe_reason_count(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        state = make_state(2)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1"],
            url="https://a.example/1",
        )
        state.evidence[1] = replace(
            state.evidence[1],
            relevance=0.9,
            requirement_ids=["R1"],
            url="https://b.example/2",
        )
        fragments = rt.explicit_request_fragments(research)
        rt.store_initial_plan(
            state,
            research,
            rt.PlanDraft(
                requirements=[
                    rt.RequirementModel(
                        id="R1",
                        summary="compare vendors",
                        kind="comparison",
                        fragment_ids=[fragments[0].id],
                    )
                ],
                sections=[
                    rt.PlanSection(
                        heading="Comparison",
                        requirement_ids=["R1"],
                    )
                ],
            ),
        )
        state.searched_queries = {
            f"q{index}" for index in range(rt.make_budget("deep").search_limit)
        }
        structured = StructuredAgent(
            [
                section(cited("Body", "S1", "S2")),
                comparison_section("Body", "S1"),
                rt.MaxTokensReachedException("partial"),
                rt.MaxTokensReachedException("unused"),
            ]
        )
        telemetry: dict[str, Any] = {}
        finalize = rt.finalize_report

        def capture_stats(current: rt.RunState, request: rt.ResearchRequest) -> rt.FinalReport:
            telemetry.update(current.stats)
            return finalize(current, request)

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=AssertionError("deep only")),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "finalize_report", side_effect=capture_stats),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "mixed-reasons-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(
                telemetry["section_validation_failures"],
                {
                    "comparison section requires a table": 1,
                    "insufficient independent hosts for R1": 1,
                    "report section output exceeded the model token budget": 1,
                },
            )
            self.assertEqual(
                telemetry["section_validation_latest_reason"],
                "report section output exceeded the model token budget",
            )
            self.assertEqual(response.outcome, "degraded")

        asyncio.run(run())

    def test_reserve_shortage_still_checkpointed_for_resume(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")

        async def run() -> None:
            with (
                patch.object(rt, "wall_budget_seconds", return_value=0.01),
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("deep must not use tool agent"),
                ),
                patch.object(
                    rt,
                    "build_finalization_agent",
                    return_value=StructuredAgent(
                        [
                            plan_for(research),
                            rt.SearchBatchDraft(
                                queries=[
                                    rt.SearchBatchEntry(
                                        query="direct evidence",
                                        purpose="cover R1",
                                        requirement_id="R1",
                                    )
                                ]
                            ),
                            rt.SearchBatchDraft(
                                queries=[
                                    rt.SearchBatchEntry(
                                        query="direct evidence retry",
                                        purpose="cover R1",
                                        requirement_id="R1",
                                    )
                                ]
                            ),
                        ]
                    ),
                ),
                self.assertRaises(rt.IncompleteResearchError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "reserve-key",
                )
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key='reserve-key'"
            ).fetchone()
            self.assertEqual(row["status"], "failed_with_output")
            self.assertEqual(json.loads(row["state_json"])["phase"], "incomplete")

        asyncio.run(run())

    def test_all_checkpointed_sections_resume_with_zero_final_model_calls(self) -> None:
        state = stable_quick_state()
        state.report_sections = [
            rt.ReportSection(
                "Summary",
                "Saved answer [S1] [S2]",
                2,
                "saved",
                [],
                ["S1", "S2"],
                "structured",
            )
        ]
        state.stats["fatal_error"] = {"reason": "old_terminal_failure"}
        state.stats["model_transient_recoveries"] = 2
        state.stats["model_transient_events"] = [{"reason": "provider_timeout"}]
        state.stats["operation_failure_reasons"] = {"timeout": 1}
        state.stats["operation_failure_events"] = [{"reason": "timeout"}]

        async def run() -> None:
            research = rt.ResearchRequest(query="Evidence", depth="quick")
            request_hash = rt.query_hash(research.model_dump())
            await rt.checkpoint_run(
                self.runtime,
                "resume-key",
                "interrupted",
                "rid",
                request_hash,
                state=rt.run_state_snapshot(state),
            )
            research_id, _, cached, snapshot = await rt.reserve_run(
                self.runtime, research, "resume-key"
            )
            self.assertIsNone(cached)
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("research must not restart"),
                ),
                patch.object(
                    rt,
                    "build_finalization_agent",
                    side_effect=AssertionError("final model must not run"),
                ),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    research_id,
                    "resume-key",
                    snapshot,
                )
            self.assertIn("Saved answer", response.answer_markdown)
            self.assertEqual(response.outcome, "completed")
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key='resume-key'"
            ).fetchone()
            stats = json.loads(row["state_json"])["stats"]
            self.assertEqual(row["status"], "completed")
            self.assertEqual(stats["fatal_error"], {})
            self.assertEqual(stats["model_transient_recoveries"], 2)
            self.assertEqual(stats["model_transient_events"], [{"reason": "provider_timeout"}])
            self.assertEqual(stats["operation_failure_reasons"], {"timeout": 1})
            self.assertEqual(stats["operation_failure_events"], [{"reason": "timeout"}])

        asyncio.run(run())

    def test_no_progress_gets_one_fresh_continuation_then_fails_without_looping(self) -> None:
        class NoProgressAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                return SimpleNamespace(
                    stop_reason="end_turn", message={"role": "assistant", "content": []}
                )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", return_value=NoProgressAgent()) as build,
                self.assertRaisesRegex(rt.IncompleteResearchError, "no_progress"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "rid",
                    "no-progress-key",
                )
            self.assertEqual(build.call_count, 2)

        asyncio.run(run())

    def test_evidence_exhaustion_returns_output_and_same_key_can_resume(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="research", depth="quick")
            state = make_state(0, "quick")
            state.searched_queries = {
                f"query {index}" for index in range(rt.make_budget("quick").search_limit)
            }
            with self.assertRaisesRegex(rt.IncompleteResearchError, "evidence_exhausted"):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "exhausted-key",
                    rt.run_state_snapshot(state),
                )
            resumed_id, _request_hash, cached, snapshot = await rt.reserve_run(
                self.runtime, research, "exhausted-key"
            )
            self.assertEqual(resumed_id, "rid")
            self.assertIsNone(cached)
            self.assertEqual(cast(dict[str, Any], snapshot)["phase"], "incomplete")

        asyncio.run(run())

    def test_invalid_structured_output_falls_back_at_section_bound(self) -> None:
        state = stable_quick_state()
        structured = StructuredAgent(
            [
                rt.MaxTokensReachedException("partial structured output"),
                rt.StructuredOutputException("invalid payload"),
                section(cited("invalid", "S9")),
            ]
        )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("research must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "invalid-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.outcome, "degraded")
            self.assertIn("Runtime extractive evidence", response.answer_markdown)
            self.assertEqual(structured.models, [rt.SectionContentDraft] * 3)

        asyncio.run(run())

    def test_tools_checkpoint_allowlist_inspection_and_acceptance(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="Evidence", depth="quick")
            state = stable_quick_state()
            state.last_inspected_revision = None
            with patch.object(
                rt,
                "search_searxng",
                new=AsyncMock(
                    return_value=[rt.SearchResult("http://example.com/3", "Three", "", "engine")]
                ),
            ):
                tools, _allowlist, fatal = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "tools-key",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                self.assertEqual(
                    set(tool_map), {"search_web", "fetch_source", "inspect_evidence_ledger"}
                )
                self.assertEqual(
                    (await tool_map["search_web"]("new evidence"))["status"], "success"
                )
                inspected = parse_tool_payload(await tool_map["inspect_evidence_ledger"]())
                self.assertEqual(inspected["ledger_revision"], 2)
                self.assertNotIn("model_transient_events", inspected["stats"])
                self.assertNotIn("operation_failure_events", inspected["stats"])
                self.assertIsInstance(fatal, list)

        asyncio.run(run())

    def test_fetch_failure_checkpoints_safe_diagnostics_without_raw_text(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="Evidence", depth="quick")
            state = stable_quick_state()
            with (
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/3", "Three", "", "engine")
                        ]
                    ),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(side_effect=ValueError("fetch failed 503")),
                ) as extract,
                self.assertLogs(rt.LOG.name, level="WARNING") as logs,
            ):
                tools, _allowlist, _fatal = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "safe-fetch-key",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                await tool_map["search_web"]("new evidence")
                failure = parse_tool_payload(
                    await tool_map["fetch_source"]("http://example.com/3", "verify")
                )
            self.assertEqual(failure["message"], "http_error")
            self.assertEqual(state.stats["operation_failure_reasons"], {"fetch:http_error": 1})
            event = state.stats["operation_failure_events"][0]
            self.assertEqual(event["operation"], "fetch")
            self.assertEqual(event["stage"], "tool")
            self.assertEqual(event["http_status"], 503)
            self.assertEqual(event["exception"], "ValueError")
            self.assertEqual(extract.await_args_list[0].args[2], "verify")
            self.assertNotIn("fetch failed 503", "\n".join(logs.output))
            row = self.runtime.db.execute(
                "SELECT state_json FROM research_runs WHERE idempotency_key = ?",
                ("safe-fetch-key",),
            ).fetchone()
            self.assertNotIn("fetch failed 503", row["state_json"])

        asyncio.run(run())

    def test_wall_timeout_and_model_timeout_checkpoint_distinct_failures(self) -> None:
        class SlowAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                await asyncio.sleep(1)
                raise AssertionError("wall timeout should cancel")

        class TimeoutAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                raise TimeoutError("upstream timeout")

        async def run() -> None:
            with (
                patch.object(rt, "wall_budget_seconds", return_value=0.01),
                patch.object(rt, "build_research_agent", return_value=SlowAgent()),
                self.assertRaisesRegex(rt.IncompleteResearchError, "wall_timeout"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "wall-rid",
                    "wall-key",
                )
            with (
                patch.object(rt, "build_research_agent", return_value=TimeoutAgent()),
                patch.object(rt, "MODEL_TRANSIENT_RECOVERIES", 2),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0.0),
                self.assertRaisesRegex(rt.IncompleteResearchError, "provider_failure"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "model-rid",
                    "model-key",
                )

        asyncio.run(run())

    def test_process_restart_and_request_cancel_preserve_recoverable_state(self) -> None:
        async def run() -> None:
            await rt.checkpoint_run(
                self.runtime,
                "stale-key",
                "running",
                "rid",
                "hash",
                state=rt.run_state_snapshot(make_state(1, "quick")),
            )
            await rt.recover_stale_runs(self.runtime)

            class SlowAgent:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    await asyncio.sleep(1)
                    raise AssertionError("cancel should stop the agent")

            with patch.object(rt, "build_research_agent", return_value=SlowAgent()):
                task = asyncio.create_task(
                    rt.run_research(
                        self.runtime,
                        FakeRequest(),
                        rt.ResearchRequest(query="research", depth="quick"),
                        "cancel-rid",
                        "cancel-key",
                    )
                )
                await asyncio.sleep(0)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await task

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main(verbosity=2)
