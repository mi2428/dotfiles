from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import httpx
from openai import APIStatusError
from strands.agent.conversation_manager import SlidingWindowConversationManager
from strands.tools.executors import SequentialToolExecutor

from test_support import (
    FakeRequest,
    RuntimeTestCase,
    StructuredAgent,
    deep_findings,
    deep_plan,
    deep_section_body,
    make_state,
    parse_tool_payload,
    planned_deep_state,
    report_sections,
    rt,
    stable_quick_state,
)


class RuntimeOrchestrationTests(RuntimeTestCase):
    def test_deep_collector_stop_event_waits_for_thirtieth_usable_source(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="Evidence", depth="deep")
            state = make_state(29)
            reached = asyncio.Event()
            extracted = rt.Evidence(
                url="http://example.com/30",
                title="Source 30",
                publisher="Publisher",
                published_at="2026-01-01",
                excerpt="Evidence 30 directly supports the requested research claim.",
                hash=f"{30:064x}",
                relevance=0.8,
                source_quality=0.5,
            )
            with (
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/30", "Thirty", "", "engine")
                        ]
                    ),
                ),
                patch.object(rt, "extract_evidence", new=AsyncMock(return_value=extracted)),
            ):
                tools, _allowlist, _fatal = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "target-key",
                    rt.query_hash(research.model_dump()),
                    state,
                    reached,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                await tool_map["search_web"]("source thirty")
                self.assertFalse(reached.is_set())
                await tool_map["fetch_source"]("http://example.com/30", "support claim")

            self.assertEqual(rt.usable_evidence_count(state), 30)
            self.assertTrue(reached.is_set())

        asyncio.run(run())

    def test_agent_configuration_and_retry_classification_are_bounded(self) -> None:
        request = rt.ResearchRequest(query="compare alternatives", depth="deep")
        agent = rt.build_research_agent(self.runtime.settings, request, [])
        model = cast(rt.SakuraKimiModel, agent.model)
        manager = cast(SlidingWindowConversationManager, agent.conversation_manager)
        params = cast(dict[str, Any], cast(dict[str, Any], model.config)["params"])
        self.assertEqual(model.client_args["max_retries"], 0)
        self.assertEqual(model.client_args["timeout"], 1800)
        self.assertEqual(params["max_tokens"], rt.KIMI_MAX_TOKENS)
        self.assertEqual(agent._retry_strategy._max_attempts, 1)
        self.assertIsInstance(agent.tool_executor, SequentialToolExecutor)
        self.assertEqual(manager.window_size, 30)
        self.assertIn("runtime owns finalization", cast(str, agent.system_prompt))

        def status_error(status_code: int) -> rt.EventLoopException:
            request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
            response = httpx.Response(status_code, request=request)
            return rt.EventLoopException(
                APIStatusError("provider error", response=response, body={})
            )

        self.assertEqual(rt.model_retry_delay(status_error(429), 0), 2)
        self.assertEqual(rt.model_retry_delay(status_error(503), 3), 16)
        self.assertIsNone(rt.model_retry_delay(status_error(400), 0))
        self.assertEqual(rt.model_retry_delay(TimeoutError("timeout"), 0), 0)

        finalizer = rt.build_finalization_agent(self.runtime.settings, request)
        finalizer_model = cast(rt.SakuraKimiModel, finalizer.model)
        finalizer_params = cast(
            dict[str, Any], cast(dict[str, Any], finalizer_model.config)["params"]
        )
        self.assertEqual(finalizer.tool_names, [])
        self.assertEqual(finalizer_params["max_tokens"], rt.FINALIZER_MAX_TOKENS)
        self.assertEqual(
            self.runtime.settings.kimi_timeout_seconds - rt.FINALIZER_TIMEOUT_SECONDS,
            rt.TIMEOUT_SAFETY_MARGIN_SECONDS,
        )

    def test_timeout_recovery_collects_once_then_forces_structured_finalization(self) -> None:
        class TimeoutAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                raise TimeoutError("upstream timeout")

        class CollectorAgent:
            def __init__(self, tools: list[Any]) -> None:
                self.tools = {tool.tool_name: tool for tool in tools}

            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                search = parse_tool_payload(await self.tools["search_web"]("evidence query"))
                for result in search["results"][:2]:
                    await self.tools["fetch_source"](result["url"], "support claim")
                await asyncio.Event().wait()
                raise AssertionError("evidence event should stop collection")

        evidence = [
            rt.Evidence(
                url=f"http://example.com/{index}",
                title=f"Title {index}",
                publisher="Publisher",
                published_at="2026-01-01",
                excerpt=f"Relevant evidence {index}",
                hash=f"{index:064x}",
                relevance=0.8,
                source_quality=0.5,
            )
            for index in range(1, 3)
        ]

        async def fake_extract(
            result: rt.SearchResult,
            query: str,
            focus: str | None,
        ) -> rt.Evidence:
            self.assertEqual(result.search_query, "evidence query")
            self.assertEqual(query, "research")
            self.assertEqual(focus, "focus; support claim")
            return evidence.pop(0)

        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Sources", body_markdown="invalid", summary="Invalid"
                ),
                rt.ReportSectionDraft(
                    heading="Summary",
                    body_markdown="Answer supported by evidence [S1] [S2]",
                    summary="Answer summary",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2"])],
                    limitations=["Known constraint"],
                ),
            ]
        )
        builds = 0

        def build_research(*args: Any) -> TimeoutAgent | CollectorAgent:
            nonlocal builds
            builds += 1
            return TimeoutAgent() if builds == 1 else CollectorAgent(args[2])

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", side_effect=build_research),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(rt, "MODEL_RETRY_BASE_SECONDS", 0),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/1", "One", "snippet", "engine"),
                            rt.SearchResult("http://example.com/2", "Two", "snippet", "engine"),
                        ]
                    ),
                ),
                patch.object(rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(
                        query="research", depth="quick", language="auto", focus="focus"
                    ),
                    "rid",
                    "key",
                )
            self.assertIn("Answer supported by evidence", response.answer_markdown)
            self.assertEqual(response.stats["model_transient_recoveries"], 1)
            self.assertEqual(response.stats["structured_output_retries"], 1)
            self.assertEqual(response.stats["agent_stop_reason"], "evidence_ready")
            row = self.runtime.db.execute(
                "SELECT status, state_json, response_json FROM research_runs "
                "WHERE idempotency_key=?",
                ("key",),
            ).fetchone()
            self.assertEqual(row["status"], "completed")
            self.assertIsNotNone(json.loads(row["state_json"])["final_response"])

        asyncio.run(run())

    def test_nonretryable_failure_after_evidence_is_salvaged_without_research_restart(self) -> None:
        state = stable_quick_state(1)

        class FailingCollector:
            def __init__(self, tools: list[Any]) -> None:
                self.tools = {tool.tool_name: tool for tool in tools}

            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                search = parse_tool_payload(await self.tools["search_web"]("second source"))
                await self.tools["fetch_source"](search["results"][0]["url"], "support claim")
                request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
                response = httpx.Response(400, request=request)
                raise rt.EventLoopException(
                    APIStatusError("provider error", response=response, body={})
                )

        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Summary",
                    body_markdown="Saved work [S1] [S2]",
                    summary="Saved work summary",
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
                    side_effect=lambda *args: FailingCollector(args[2]),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/new", "New", "snippet", "engine")
                        ]
                    ),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(
                        return_value=rt.Evidence(
                            url="http://example.com/new",
                            title="New",
                            publisher="Publisher",
                            published_at="2026-01-01",
                            excerpt="Second relevant source",
                            hash="f" * 64,
                            relevance=0.8,
                            source_quality=0.5,
                        )
                    ),
                ),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "salvage-key",
                    rt.run_state_snapshot(state),
                )
            self.assertIn("Saved work", response.answer_markdown)
            self.assertEqual(response.stats["research_salvages"], 1)
            self.assertEqual(response.stats["agent_stop_reason"], "EventLoopException")

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
            self.assertEqual(structured.models, [rt.ReportSubmissionDraft])

        asyncio.run(run())

    def test_deep_plan_is_checkpointed_once_and_resume_keeps_section_bodies_compact(self) -> None:
        source_count = rt.DEEP_MIN_CITED_SOURCES
        research = rt.ResearchRequest(query="Evidence", depth="deep")
        first = StructuredAgent(
            [
                rt.ReportPlanDraft(sections=deep_plan(source_count)),
                rt.MaxTokensReachedException("partial section"),
                rt.MaxTokensReachedException("partial section"),
                rt.MaxTokensReachedException("partial section"),
            ]
        )

        async def run() -> None:
            state = planned_deep_state(source_count)
            state.report_plan.clear()
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("research must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=first),
                self.assertRaisesRegex(
                    rt.IncompleteResearchError, "structured_section_attempts"
                ) as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "plan-resume-key",
                    rt.run_state_snapshot(state),
                )
            self.assertTrue(failure.exception.answer_markdown.startswith("# Deep Research未完了"))
            self.assertIn("## Safe Evidence Ledger", failure.exception.answer_markdown)

            row = self.runtime.db.execute(
                "SELECT status,state_json FROM research_runs WHERE idempotency_key=?",
                ("plan-resume-key",),
            ).fetchone()
            snapshot = json.loads(row["state_json"])
            self.assertEqual(row["status"], "failed_with_output")
            self.assertEqual(snapshot["phase"], "incomplete")
            self.assertEqual(len(snapshot["report_plan"]), rt.DEEP_PLAN_TARGET_SECTIONS)

            bodies = [
                f"Unique section {index}. " + deep_section_body(source_count)
                for index in range(1, rt.DEEP_PLAN_TARGET_SECTIONS + 1)
            ]
            resumed = StructuredAgent(
                [
                    *[
                        rt.ReportSectionDraft(
                            heading=f"Section {index}",
                            body_markdown=body,
                            summary=f"Summary {index}",
                        )
                        for index, body in enumerate(bodies, 1)
                    ],
                    rt.ReportSubmissionDraft(
                        findings=[rt.SubmitFinding(**item) for item in deep_findings(source_count)],
                        limitations=[
                            f"Limitation {index}" for index in range(1, rt.DEEP_MIN_LIMITATIONS + 1)
                        ],
                    ),
                ]
            )
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("research must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=resumed),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "plan-resume-key",
                    snapshot,
                )

            self.assertGreaterEqual(len(response.answer_markdown), rt.DEEP_MIN_ANSWER_CHARS)
            self.assertNotIn(rt.ReportPlanDraft, resumed.models)
            self.assertNotIn(bodies[0], resumed.prompts[1])
            self.assertEqual(resumed.models[-1], rt.ReportSubmissionDraft)

        asyncio.run(run())

    def test_finalizer_uses_adaptive_deliverable_repair_without_adding_a_section(self) -> None:
        source_count = rt.make_budget("deep").minimum_evidence
        state = planned_deep_state(source_count)
        research = rt.ResearchRequest(query="compare Evidence alternatives", depth="deep")
        revision = state.evidence_revision
        body = deep_section_body(source_count)
        state.report_sections = [
            rt.ReportSection(section.heading, section.body, revision, section.summary)
            for section in report_sections(source_count)
        ]
        state.report_sections[0] = rt.ReportSection(
            "Section 1",
            "| Option | Evaluation |\n|---|---|\n| A | Evidence |\n\n" + body,
            revision,
            "Comparison summary",
        )
        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Model ignored the requested repair heading",
                    body_markdown="| Option | Evaluation |\n|---|---|\n| A | Evidence [S1] |\n\n"
                    + body,
                    summary="Comparison repair",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(**item) for item in deep_findings(source_count)],
                    limitations=[
                        f"Limitation {index}" for index in range(1, rt.DEEP_MIN_LIMITATIONS + 1)
                    ],
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
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "repair-key",
                    rt.run_state_snapshot(state),
                )

            self.assertEqual(response.answer_markdown.count("## Section 1\n\n"), 1)
            self.assertNotIn("## Model ignored", response.answer_markdown)
            self.assertIn("Evidence [1]", response.answer_markdown)
            self.assertEqual(
                structured.models,
                [rt.ReportSectionDraft, rt.ReportSubmissionDraft],
            )

        asyncio.run(run())

    def test_hung_finalizer_times_out_then_retries_same_checkpoint(self) -> None:
        state = stable_quick_state()
        cancelled = False

        class HungFinalizer:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                nonlocal cancelled
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    cancelled = True
                    await asyncio.sleep(10)
                raise AssertionError("cancelled finalizer must not return")

        structured = StructuredAgent(
            [
                rt.ReportSectionDraft(
                    heading="Summary",
                    body_markdown="Checkpoint-preserving response [S1] [S2]",
                    summary="Checkpoint summary",
                ),
                rt.ReportSubmissionDraft(
                    findings=[rt.SubmitFinding(claim="Claim", source_ids=["S1", "S2"])],
                    limitations=["Known constraint"],
                ),
            ]
        )
        builds = 0

        def build_finalizer(*_args: Any) -> HungFinalizer | StructuredAgent:
            nonlocal builds
            builds += 1
            return HungFinalizer() if builds == 1 else structured

        async def run() -> None:
            started = asyncio.get_running_loop().time()
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("research must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", side_effect=build_finalizer),
                patch.object(rt, "FINALIZER_TIMEOUT_SECONDS", 0.01),
                patch.object(rt, "AGENT_CANCEL_GRACE_SECONDS", 0.01),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "hung-finalizer-key",
                    rt.run_state_snapshot(state),
                )
            self.assertTrue(cancelled)
            self.assertLess(asyncio.get_running_loop().time() - started, 1)
            self.assertIn("Checkpoint-preserving response", response.answer_markdown)
            self.assertEqual(response.stats["model_transient_recoveries"], 1)

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
            row = self.runtime.db.execute(
                "SELECT status,state_json FROM research_runs WHERE idempotency_key=?",
                ("invalid-key",),
            ).fetchone()
            snapshot = json.loads(row["state_json"])
            self.assertEqual(row["status"], "failed_with_output")
            self.assertEqual(snapshot["stats"]["structured_output_retries"], 3)
            self.assertFalse(snapshot["report_sections"])
            self.assertIn("## Sources", failure.exception.answer_markdown)

        asyncio.run(run())

    def test_submission_exhaustion_returns_completed_sections_without_an_extra_call(self) -> None:
        state = stable_quick_state()
        state.report_sections = [
            rt.ReportSection(
                "Saved section",
                "Checkpointed answer [S1] [S2]",
                state.evidence_revision,
                "Saved summary",
            )
        ]
        structured = StructuredAgent(
            [rt.MaxTokensReachedException("partial submission") for _ in range(3)]
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
                    rt.IncompleteResearchError, "normal_contract_unmet"
                ) as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "rid",
                    "submission-failure-key",
                    rt.run_state_snapshot(state),
                )

            self.assertIn("## 完成済み節", failure.exception.answer_markdown)
            self.assertIn("## Saved section", failure.exception.answer_markdown)
            self.assertIn("Checkpointed answer [1] [2]", failure.exception.answer_markdown)
            self.assertEqual(len(structured.prompts), 3)

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
                searched = await tool_map["search_web"]("new evidence")
                self.assertEqual(searched["status"], "success")
                self.assertEqual(
                    (await tool_map["fetch_source"]("http://not-allowed.example", "claim"))[
                        "status"
                    ],
                    "error",
                )
                self.assertEqual(
                    (await tool_map["write_report_section"](2, "Summary", "Claim [S1] [S2]"))[
                        "status"
                    ],
                    "error",
                )
                inspected = parse_tool_payload(await tool_map["inspect_evidence_ledger"]())
                self.assertEqual(inspected["ledger_revision"], 2)
                self.assertEqual(
                    (await tool_map["write_report_section"](2, "Summary", "Claim [S1] [S2]"))[
                        "status"
                    ],
                    "success",
                )
                accepted = await tool_map["submit_report"](
                    2,
                    [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
                    ["Known constraint"],
                )
                self.assertEqual(accepted["status"], "success")
                self.assertIsInstance(fatal[0], rt.IntegrityError)
                saved = self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key=?",
                    ("tools-key",),
                ).fetchone()
                self.assertIn("new evidence", json.loads(saved["state_json"])["searched_queries"])

        asyncio.run(run())

    def test_no_progress_gets_one_fresh_continuation_then_fails_without_looping(self) -> None:
        class NoProgressAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                return SimpleNamespace(
                    stop_reason="end_turn",
                    message={"role": "assistant", "content": []},
                )

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", return_value=NoProgressAgent()) as build,
                self.assertRaisesRegex(rt.IncompleteResearchError, "no_progress") as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "rid",
                    "no-progress-key",
                )
            self.assertEqual(build.call_count, 2)
            row = self.runtime.db.execute(
                "SELECT status,state_json,response_json FROM research_runs WHERE idempotency_key=?",
                ("no-progress-key",),
            ).fetchone()
            snapshot = json.loads(row["state_json"])
            self.assertEqual(row["status"], "failed_with_output")
            self.assertIsNone(row["response_json"])
            self.assertEqual(snapshot["stats"]["research_continuations"], 1)
            self.assertIn("## 未達", failure.exception.answer_markdown)

        asyncio.run(run())

    def test_evidence_exhaustion_returns_output_and_same_key_can_resume(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="research", depth="quick")
            state = make_state(0, "quick")
            state.searched_queries = {
                f"query {index}" for index in range(rt.make_budget("quick").search_limit)
            }
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("exhausted research must not start an agent"),
                ),
                self.assertRaisesRegex(rt.IncompleteResearchError, "evidence_exhausted") as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "exhausted-key",
                    rt.run_state_snapshot(state),
                )
            self.assertIn("# Deep Research未完了", failure.exception.answer_markdown)
            self.assertIn("## Safe Evidence Ledger", failure.exception.answer_markdown)

            resumed_id, _request_hash, cached, snapshot = await rt.reserve_run(
                self.runtime,
                research,
                "exhausted-key",
            )
            self.assertEqual(resumed_id, "rid")
            self.assertIsNone(cached)
            self.assertEqual(cast(dict[str, Any], snapshot)["phase"], "incomplete")

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
                self.assertRaisesRegex(rt.IncompleteResearchError, "wall_timeout") as wall_failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "wall-rid",
                    "wall-key",
                )
            wall = json.loads(
                self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key='wall-key'"
                ).fetchone()[0]
            )
            self.assertTrue(wall["stats"]["wall_exhausted"])
            self.assertIn("時間上限", wall_failure.exception.answer_markdown)

            with (
                patch.object(rt, "build_research_agent", return_value=TimeoutAgent()),
                patch.object(rt, "MODEL_TRANSIENT_RECOVERIES", 2),
                self.assertRaisesRegex(
                    rt.IncompleteResearchError, "provider_failure"
                ) as model_failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="research", depth="quick"),
                    "model-rid",
                    "model-key",
                )
            model = json.loads(
                self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key='model-key'"
                ).fetchone()[0]
            )
            self.assertFalse(model["stats"]["wall_exhausted"])
            self.assertEqual(model["stats"]["model_transient_recoveries"], 2)
            self.assertIn("モデル提供者", model_failure.exception.answer_markdown)

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
            stale = self.runtime.db.execute(
                "SELECT status,state_json FROM research_runs WHERE idempotency_key='stale-key'"
            ).fetchone()
            self.assertEqual(stale["status"], "interrupted")
            self.assertEqual(len(json.loads(stale["state_json"])["evidence_ledger"]), 1)

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
            cancelled = self.runtime.db.execute(
                "SELECT status,state_json FROM research_runs WHERE idempotency_key='cancel-key'"
            ).fetchone()
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertIn("stats", json.loads(cancelled["state_json"]))

        asyncio.run(run())


if __name__ == "__main__":
    import unittest

    unittest.main(verbosity=2)
