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


def plan_for(
    research: rt.ResearchRequest, source_ids: list[str] | None = None
) -> rt.InitialPlanDraft:
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
        rt.InitialPlanSection(
            heading="Direct evidence",
            target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
            requirement_ids=["R1"],
            deliverables=[requirements[0].summary],
        ),
        rt.InitialPlanSection(
            heading="Comparison",
            target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
            requirement_ids=["R2"],
            deliverables=[requirements[1].summary],
        ),
    ]
    return rt.InitialPlanDraft(
        requirements=requirements,
        sections=sections,
        query_seeds=[],
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
                rt.ReportSectionDraft(
                    heading="Summary",
                    body_markdown="Answer supported by evidence [S1] [S2]",
                    summary="summary",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2"])],
                    limitations=["Known constraint"],
                ),
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

        asyncio.run(run())

    def test_fresh_empty_deep_state_runs_plan_query_candidate_fetch_and_coverage(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        fragments = rt.explicit_request_fragments(research)
        initial = rt.InitialPlanDraft(
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
                rt.InitialPlanSection(
                    heading="Direct evidence",
                    target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                    requirement_ids=["R1"],
                    deliverables=["Need direct evidence"],
                ),
                rt.InitialPlanSection(
                    heading="Comparison",
                    target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                    requirement_ids=["R2"],
                    deliverables=["compare vendors"],
                ),
            ],
            query_seeds=[
                rt.QuerySeedModel(
                    query="direct evidence",
                    purpose="cover R1",
                    requirement_ids=["R1"],
                ),
                rt.QuerySeedModel(
                    query="vendor comparison independent",
                    purpose="cover R2",
                    requirement_ids=["R2"],
                ),
            ],
        )
        structured = StructuredAgent(
            [
                initial,
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported direct claim [S1]",
                    summary="direct",
                ),
                rt.ReportSectionDraft(
                    heading="Comparison",
                    requirement_ids=["R2"],
                    body_markdown="Comparison across two hosts [S2] [S3]",
                    summary="comparison",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2", "S3"])],
                    limitations=["Known constraint"],
                ),
            ]
        )

        search_calls: list[str] = []

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
            result: rt.SearchResult, _query: str, _focus: str | None
        ) -> rt.Evidence:
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
            self.assertEqual(search_calls, ["direct evidence", "vendor comparison independent"])
            self.assertTrue(
                all(item["turns"] == rt.STRUCTURED_OUTPUT_TURNS for item in structured.limits)
            )
            self.assertIn("Comparison across two hosts", response.answer_markdown)

        asyncio.run(run())

    def test_search_failure_and_same_batch_duplicate_do_not_stop_other_query(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
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
                        rt.SearchBatchEntry(query="dup", purpose="r2", requirement_ids=["R2"]),
                        rt.SearchBatchEntry(query="dup", purpose="r2 dup", requirement_ids=["R2"]),
                        rt.SearchBatchEntry(query="ok", purpose="r2 ok", requirement_ids=["R2"]),
                    ]
                ),
                APIError("Internal server error.", request=request, body=None),
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="idle-2", purpose="r2 idle", requirement_ids=["R2"]
                        )
                    ]
                ),
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported evidence [S1]",
                    summary="direct",
                ),
                rt.ReportSectionDraft(
                    heading="Comparison",
                    requirement_ids=["R2"],
                    body_markdown="Coverage gap remains",
                    summary="gap",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1"])],
                    limitations=["Known constraint"],
                ),
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
            self.assertEqual(response.stats["model_transient_recoveries"], 2)
            self.assertTrue(response.stats["evidence_shortfall_salvage"])

        asyncio.run(run())

    def test_repeated_stream_provider_error_salvages_collected_evidence(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        structured = StructuredAgent(
            [
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported evidence [S1]",
                    summary="direct",
                ),
                rt.ReportSectionDraft(
                    heading="Comparison",
                    requirement_ids=["R2"],
                    body_markdown="Coverage gap remains",
                    summary="gap",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1"])],
                    limitations=["Known constraint"],
                ),
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
                    "provider-salvage-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(response.stats["research_salvages"], 1)
            self.assertTrue(response.stats["evidence_shortfall_salvage"])

        asyncio.run(run())

    def test_finalization_provider_failure_uses_extractive_report(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        rt.set_collection_decision(state, "voluntary_stop")
        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        structured = StructuredAgent(
            [
                APIError("Internal server error.", request=request, body=None),
                APIError("Internal server error.", request=request, body=None),
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
                    "extractive-finalization-key",
                    rt.run_state_snapshot(state),
                )
            self.assertTrue(response.stats["extractive_finalization"])
            self.assertEqual(response.stats["extractive_finalization_reason"], "provider_failure")
            self.assertIn("検証済み証拠台帳から抽出的に構成", response.answer_markdown)
            self.assertIn("Runtime coverage gap", response.answer_markdown)
            self.assertEqual(len(response.sources), 1)

        asyncio.run(run())

    def test_deep_uses_candidate_queue_past_thirty_until_requirement_done(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(30)
        state.request_fragments = rt.explicit_request_fragments(research)
        initial = plan_for(research)
        state.requirements = initial.requirements
        state.report_plan = [
            rt.ReportPlanSection(
                heading=item.heading,
                target_chars=item.target_chars,
                requirement_ids=item.requirement_ids,
                source_ids=[],
                deliverables=item.deliverables,
            )
            for item in initial.sections
        ]
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
                            requirement_ids=["R2"],
                        )
                    ]
                ),
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported direct claim [S1]",
                    summary="direct",
                ),
                rt.ReportSectionDraft(
                    heading="Comparison",
                    requirement_ids=["R2"],
                    body_markdown="Comparison across two hosts [S31] [S32]",
                    summary="comparison",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S31", "S32"])],
                    limitations=["Known constraint"],
                ),
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
        draft = rt.InitialPlanDraft(
            requirements=[
                rt.RequirementModel(
                    id="R1", summary="Need direct evidence", kind="comparison", fragment_ids=["F1"]
                )
            ],
            sections=[
                rt.InitialPlanSection(
                    heading="Direct evidence",
                    target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                    requirement_ids=["R1"],
                    deliverables=["Need direct evidence"],
                )
            ],
            query_seeds=[],
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
                requirement_ids=["R1"],
            )
        ]
        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported claim [S1] [S2]",
                    summary="summary",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2"])],
                    limitations=["Known constraint"],
                ),
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
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(side_effect=AssertionError("resume should use queued candidate")),
                ),
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
                requirement_ids=["R1"],
            ),
            rt.Candidate(
                url="https://b.example/2",
                title="B",
                snippet="",
                engine="e",
                search_query="q",
                purpose="p",
                requirement_ids=["R1"],
            ),
        ]
        batch = rt.next_candidate_batch(state)
        self.assertEqual([item.url for item in batch], ["https://a.example/1"])
        self.assertEqual([item.url for item in state.candidate_queue], ["https://b.example/2"])

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
            rt.ReportPlanSection(
                heading="Combined",
                target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                requirement_ids=["R1", "R2"],
                source_ids=[],
                deliverables=["facts", "compare"],
            )
        ]
        payload = rt.build_section_context(research, state, "missing_plan_section", "Combined")
        self.assertEqual([item["id"] for item in payload["assigned_evidence"]], ["S1", "S2", "S3"])
        self.assertEqual(payload["planned_section"]["source_ids"], ["S1", "S2", "S3"])

    def test_gap_finalization_returns_completed_report_with_runtime_gap_limitation(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        fragments = rt.explicit_request_fragments(research)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(
            state,
            research,
            rt.InitialPlanDraft(
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
                    rt.InitialPlanSection(
                        heading="Direct",
                        target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                        requirement_ids=["R1"],
                        deliverables=["Need direct evidence"],
                    ),
                    rt.InitialPlanSection(
                        heading="Compare",
                        target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                        requirement_ids=["R2"],
                        deliverables=["compare vendors"],
                    ),
                ],
                query_seeds=[],
            ),
        )
        structured = StructuredAgent(
            [
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="missing comparison evidence 1",
                            purpose="cover R2",
                            requirement_ids=["R2"],
                        )
                    ]
                ),
                rt.SearchBatchDraft(
                    queries=[
                        rt.SearchBatchEntry(
                            query="missing comparison evidence 2",
                            purpose="cover R2",
                            requirement_ids=["R2"],
                        )
                    ]
                ),
                rt.ReportSectionDraft(
                    heading="Direct",
                    requirement_ids=["R1"],
                    body_markdown="Supported [S1]",
                    summary="direct",
                ),
                rt.ReportSectionDraft(
                    heading="Compare",
                    requirement_ids=["R2"],
                    body_markdown="Coverage gap remains",
                    summary="gap",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1"])],
                    limitations=["Known constraint"],
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
            self.assertTrue(response.stats["evidence_shortfall_salvage"])
            self.assertTrue(any("Runtime coverage gap" in item for item in response.limitations))
            self.assertEqual(response.stats["collection_decision"], "voluntary_stop")

        asyncio.run(run())

    def test_retryable_section_semantic_error_retries_then_completes(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, plan_for(research))
        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R9"],
                    body_markdown="Missing citation",
                    summary="bad",
                ),
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Valid citation [S1]",
                    summary="ok",
                ),
                rt.ReportSectionDraft(
                    heading="Comparison",
                    requirement_ids=["R2"],
                    body_markdown="Coverage gap",
                    summary="gap",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1"])],
                    limitations=["Known constraint"],
                ),
            ]
        )
        state.searched_queries = {
            f"q{index}" for index in range(rt.make_budget("deep").search_limit)
        }

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
                    "retry-key",
                    rt.run_state_snapshot(state),
                )
            self.assertGreaterEqual(response.stats["structured_output_retries"], 1)
            self.assertEqual(response.stats["collection_decision"], "voluntary_stop")

        asyncio.run(run())

    def test_nonretryable_programmer_tool_error_is_hard_failure(self) -> None:
        async def run() -> None:
            class ToolFailureAgent:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    raise TypeError("internal bug")

            with (
                patch.object(rt, "build_research_agent", return_value=ToolFailureAgent()),
                self.assertRaises(TypeError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "hard-failure-key",
                )

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
        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Valid citation [S1]",
                    summary="ok",
                )
            ]
        )

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
            self.assertEqual(structured.models.count(rt.ReportSectionDraft), 1)

        asyncio.run(run())

    def test_expected_exhaustion_below_twenty_uses_extractive_finalization(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1"],
            search_query=research.query,
            purpose="Need direct evidence",
            excerpt="Need direct evidence with enough matching terms for runtime coverage.",
        )
        draft = plan_for(research)
        rt.store_initial_plan(state, research, draft)
        state.searched_queries = {
            f"q{index}" for index in range(rt.make_budget("deep").search_limit)
        }
        state.stats["finalization_reserved"] = True
        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Direct evidence",
                    requirement_ids=["R1"],
                    body_markdown="Supported direct claim [S1]",
                    summary="summary",
                ),
                rt.MaxTokensReachedException("partial"),
                rt.MaxTokensReachedException("partial"),
                rt.MaxTokensReachedException("partial"),
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
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "exhaustion-key",
                    rt.run_state_snapshot(state),
                )
            self.assertTrue(response.stats["extractive_finalization"])
            self.assertEqual(
                response.stats["extractive_finalization_reason"], "structured_section_attempts"
            )
            self.assertNotIn("# Deep Research未完了", response.answer_markdown)
            self.assertEqual(len(response.sources), 1)

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
                            plan_for(research, ["S1"]),
                            rt.SearchBatchDraft(
                                queries=[
                                    rt.SearchBatchEntry(
                                        query="direct evidence",
                                        purpose="cover R1",
                                        requirement_ids=["R1"],
                                    )
                                ]
                            ),
                            rt.SearchBatchDraft(
                                queries=[
                                    rt.SearchBatchEntry(
                                        query="direct evidence retry",
                                        purpose="cover R1",
                                        requirement_ids=["R1"],
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

    def test_checkpointed_sections_resume_at_submission_only(self) -> None:
        state = stable_quick_state()
        state.report_sections = [rt.ReportSection("Summary", "Saved answer [S1] [S2]", 2)]
        structured = StructuredAgent(
            [
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2"])],
                    limitations=["Known constraint"],
                )
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
                    "resume-key",
                    rt.run_state_snapshot(state),
                )
            self.assertIn("Saved answer", response.answer_markdown)

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

    def test_invalid_structured_output_stops_at_bound_and_keeps_checkpoint(self) -> None:
        state = stable_quick_state()
        structured = StructuredAgent(
            [
                rt.MaxTokensReachedException("partial structured output"),
                rt.StructuredOutputException("invalid payload"),
                rt.ReportSectionDraft(
                    heading="Limitations", body_markdown="invalid", summary="Invalid"
                ),
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
                self.assertRaisesRegex(
                    rt.IncompleteResearchError, "structured_section_attempts"
                ) as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "invalid-key",
                    rt.run_state_snapshot(state),
                )
            self.assertIn("## Sources", failure.exception.answer_markdown)

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
                    (await tool_map["search_web"]("new evidence"))["status"], "success"
                )
                inspected = parse_tool_payload(await tool_map["inspect_evidence_ledger"]())
                self.assertEqual(inspected["ledger_revision"], 2)
                self.assertIsInstance(fatal, list)

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
