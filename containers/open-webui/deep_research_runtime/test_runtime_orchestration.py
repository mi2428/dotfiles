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
    deep_structured_outputs,
    make_state,
    mixed_deep_state,
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
            self.assertEqual(state.collection_decision, "target_reached")
            self.assertEqual(state.phase, "evidence_complete")

        asyncio.run(run())

    def test_resume_with_twenty_five_sources_continues_without_a_saved_decision(self) -> None:
        class InterruptedCollector:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                raise TimeoutError("provider interrupted")

        async def run() -> None:
            state = mixed_deep_state(25, 25)
            with (
                patch.object(
                    rt, "build_research_agent", return_value=InterruptedCollector()
                ) as build,
                patch.object(
                    rt,
                    "build_finalization_agent",
                    side_effect=AssertionError("resume must collect before finalization"),
                ),
                patch.object(rt, "MODEL_TRANSIENT_RECOVERIES", 0),
                self.assertRaisesRegex(rt.IncompleteResearchError, "provider_failure"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "rid",
                    "resume-25-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(build.call_count, 1)
            snapshot = json.loads(
                self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key='resume-25-key'"
                ).fetchone()[0]
            )
            self.assertIsNone(snapshot["collection_decision"])

        asyncio.run(run())

    def test_voluntary_stop_below_minimum_starts_one_continuation(self) -> None:
        class EarlyStopCollector:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                return SimpleNamespace(stop_reason="end_turn", message={"content": []})

        async def run() -> None:
            with (
                patch.object(
                    rt, "build_research_agent", return_value=EarlyStopCollector()
                ) as build,
                patch.object(
                    rt,
                    "build_finalization_agent",
                    side_effect=AssertionError("nineteen sources must not finalize"),
                ),
                self.assertRaisesRegex(rt.IncompleteResearchError, "no_progress"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "rid",
                    "below-minimum-key",
                    rt.run_state_snapshot(mixed_deep_state(19, 19)),
                )
            self.assertEqual(build.call_count, 2)

        asyncio.run(run())

    def test_sixtieth_stored_source_sets_stop_event_for_both_cap_decisions(self) -> None:
        async def run() -> None:
            for usable_before, relevance, expected in (
                (24, 0.8, "evidence_cap_reached"),
                (19, 0.0, "evidence_cap_exhausted"),
            ):
                with self.subTest(expected=expected):
                    state = mixed_deep_state(59, usable_before)
                    reached = asyncio.Event()
                    extracted = rt.Evidence(
                        url=f"http://example.com/cap-{usable_before}",
                        title="Cap source",
                        publisher="Publisher",
                        published_at="2026-01-01",
                        excerpt="Cap evidence content",
                        hash=f"{usable_before + 100:064x}",
                        relevance=relevance,
                        source_quality=0.5,
                    )
                    with (
                        patch.object(
                            rt,
                            "search_searxng",
                            new=AsyncMock(
                                return_value=[
                                    rt.SearchResult(
                                        extracted.url,
                                        "Cap source",
                                        "",
                                        "engine",
                                    )
                                ]
                            ),
                        ),
                        patch.object(
                            rt,
                            "extract_evidence",
                            new=AsyncMock(return_value=extracted),
                        ),
                    ):
                        tools, _allowlist, _fatal = rt.build_research_tools(
                            self.runtime,
                            rt.ResearchRequest(query="Evidence", depth="deep"),
                            "rid",
                            f"cap-event-{usable_before}",
                            "hash",
                            state,
                            reached,
                        )
                        tool_map = {tool.tool_name: tool for tool in tools}
                        await tool_map["search_web"](f"cap query {usable_before}")
                        await tool_map["fetch_source"](extracted.url, "cap evidence")
                    self.assertTrue(reached.is_set())
                    self.assertEqual(state.collection_decision, expected)

        asyncio.run(run())

    def test_voluntary_stop_between_minimum_and_target_checkpoints_finalization(self) -> None:
        class VoluntaryCollector:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                return SimpleNamespace(stop_reason="end_turn", message={"content": []})

        structured = StructuredAgent(deep_structured_outputs(25))

        async def run() -> None:
            state = mixed_deep_state(25, 25)
            with (
                patch.object(
                    rt, "build_research_agent", return_value=VoluntaryCollector()
                ) as build,
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "rid",
                    "voluntary-25-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(build.call_count, 1)
            self.assertEqual(response.stats["collection_decision"], "voluntary_stop")

        asyncio.run(run())

    def test_evidence_cap_finalizes_with_twenty_five_but_not_nineteen_usable(self) -> None:
        async def run() -> None:
            eligible = mixed_deep_state(60, 25)
            structured = StructuredAgent(deep_structured_outputs(25))
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("cap checkpoint must decide before collection"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "eligible-cap-rid",
                    "eligible-cap-key",
                    rt.run_state_snapshot(eligible),
                )
            self.assertEqual(response.stats["collection_decision"], "evidence_cap_reached")

            exhausted = mixed_deep_state(60, 19)
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("cap checkpoint must not restart collection"),
                ),
                patch.object(
                    rt,
                    "build_finalization_agent",
                    side_effect=AssertionError("ineligible cap must not finalize"),
                ),
                self.assertRaisesRegex(rt.IncompleteResearchError, "evidence_exhausted"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "exhausted-cap-rid",
                    "exhausted-cap-key",
                    rt.run_state_snapshot(exhausted),
                )
            snapshot = json.loads(
                self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key='exhausted-cap-key'"
                ).fetchone()[0]
            )
            self.assertEqual(snapshot["collection_decision"], "evidence_cap_exhausted")

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

        def status_error(
            status_code: int,
            body: dict[str, Any] | None = None,
        ) -> rt.EventLoopException:
            request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
            response = httpx.Response(status_code, request=request)
            return rt.EventLoopException(
                APIStatusError("provider error", response=response, body=body or {})
            )

        self.assertEqual(rt.model_retry_delay(status_error(429), 0), 2)
        self.assertEqual(rt.model_retry_delay(status_error(503), 3), 16)
        self.assertIsNone(rt.model_retry_delay(status_error(400), 0))
        self.assertEqual(rt.model_retry_delay(TimeoutError("timeout"), 0), 0)
        timeout_body = {"error": {"code": "timeout", "message": "upstream timeout"}}
        for status_code in (401, 403):
            self.assertFalse(
                rt.is_expected_provider_failure(status_error(status_code, timeout_body))
            )
        unknown = RuntimeError("unknown provider wrapper")
        unknown.__cause__ = TimeoutError("nested timeout")
        self.assertIsNone(rt.model_retry_delay(rt.EventLoopException(unknown), 0))
        self.assertEqual(
            rt.model_retry_delay(rt.EventLoopException(TimeoutError("known timeout")), 0),
            0,
        )

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

    def test_retryable_failure_after_evidence_is_salvaged_without_research_restart(self) -> None:
        state = stable_quick_state(1)

        class FailingCollector:
            def __init__(self, tools: list[Any]) -> None:
                self.tools = {tool.tool_name: tool for tool in tools}

            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                search = parse_tool_payload(await self.tools["search_web"]("second source"))
                await self.tools["fetch_source"](search["results"][0]["url"], "support claim")
                request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
                response = httpx.Response(503, request=request)
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

    def test_invalid_plan_semantics_retry_three_times_with_shared_validation(self) -> None:
        duplicate = deep_plan(rt.DEEP_MIN_CITED_SOURCES)
        duplicate[1] = duplicate[1].model_copy(update={"heading": duplicate[0].heading})
        short = [item.model_copy(update={"target_chars": 5_000}) for item in deep_plan(20)]

        class FeedbackPlanAgent(StructuredAgent):
            async def invoke_async(self, prompt: str, **kwargs: Any) -> SimpleNamespace:
                if kwargs["structured_output_model"] is not rt.ReportPlanDraft:
                    return await super().invoke_async(prompt, **kwargs)
                feedback = json.loads(prompt)["previous_validation_error"]
                if feedback is None:
                    output = rt.ReportPlanDraft(sections=duplicate)
                elif feedback == "report plan headings must be unique":
                    output = rt.ReportPlanDraft(sections=short)
                elif feedback == "report plan targets must total at least 77000 characters":
                    output = rt.ReportPlanDraft(sections=deep_plan(20))
                else:
                    raise AssertionError(f"unexpected safe plan feedback: {feedback}")
                self.models.append(rt.ReportPlanDraft)
                self.limits.append(kwargs["limits"])
                self.prompts.append(prompt)
                return SimpleNamespace(
                    stop_reason="tool_use",
                    structured_output=output,
                    message={"role": "assistant", "content": []},
                )

        structured = FeedbackPlanAgent(deep_structured_outputs(20)[1:])

        async def run() -> None:
            state = planned_deep_state(20)
            state.report_plan.clear()
            state.stats["report_plan_sections"] = 0
            state.stats["report_plan_target_chars"] = 0
            state.phase = "evidence_complete"
            state.unmet_requirements.clear()
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("collection decision must be resumed"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
            ):
                response = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="deep"),
                    "rid",
                    "plan-retries-key",
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(structured.models[:3], [rt.ReportPlanDraft] * 3)
            self.assertEqual(response.stats["plan_calls"], 3)
            self.assertEqual(response.stats["structured_output_retries"], 2)
            plan_prompts = [
                json.loads(prompt)
                for prompt, model in zip(structured.prompts, structured.models, strict=True)
                if model is rt.ReportPlanDraft
            ]
            self.assertEqual(
                [item["previous_validation_error"] for item in plan_prompts],
                [
                    None,
                    "report plan headings must be unique",
                    "report plan targets must total at least 77000 characters",
                ],
            )
            self.assertEqual(
                json.loads(
                    rt.build_plan_prompt(
                        rt.ResearchRequest(query="Evidence", depth="deep"),
                        state,
                        "RAW_PROVIDER_OUTPUT_SENTINEL",
                    )
                )["previous_validation_error"],
                "report plan failed semantic validation",
            )

        asyncio.run(run())

    def test_nonretryable_provider_and_internal_type_errors_are_hard_http_failures(self) -> None:
        def provider_error(
            status_code: int,
            body: dict[str, Any] | None = None,
        ) -> rt.EventLoopException:
            request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
            response = httpx.Response(status_code, request=request)
            return rt.EventLoopException(
                APIStatusError("provider error", response=response, body=body or {})
            )

        class HardFailureAgent:
            def __init__(self, error: Exception) -> None:
                self.error = error

            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                raise self.error

        async def assert_hard_response(
            client: httpx.AsyncClient,
            query: str,
            key: str,
            state: rt.RunState | None,
            error: Exception,
            *,
            finalizer: bool,
        ) -> None:
            headers = {
                "Authorization": "Bearer test-api-key",
                "X-OpenWebUI-Message-Id": key,
            }
            with (
                patch.object(
                    rt,
                    "reserve_run",
                    new=AsyncMock(
                        return_value=(
                            "rid",
                            "hash",
                            None,
                            rt.run_state_snapshot(state) if state is not None else None,
                        )
                    ),
                ),
                patch.object(
                    rt,
                    "build_research_agent",
                    return_value=HardFailureAgent(error),
                ) as research_build,
                patch.object(
                    rt,
                    "build_finalization_agent",
                    return_value=HardFailureAgent(error),
                ) as finalizer_build,
                patch.object(rt, "AGENT_CANCEL_GRACE_SECONDS", 0.01),
            ):
                response = await client.post(
                    "/research",
                    headers=headers,
                    json={"query": query, "depth": "deep" if state is not None else "quick"},
                )
            self.assertEqual(response.status_code, 502)
            self.assertNotIn("x-openwebui-direct-output", response.headers)
            self.assertNotIn("x-deep-research-status", response.headers)
            self.assertEqual(research_build.call_count, 0 if finalizer else 1)
            self.assertEqual(finalizer_build.call_count, 1 if finalizer else 0)

        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                finalizer_state = planned_deep_state(20)
                timeout_body = {"error": {"code": "timeout", "message": "upstream timeout"}}
                unknown = RuntimeError("unknown provider wrapper")
                unknown.__cause__ = TimeoutError("nested timeout")
                for key, state, error, finalizer in (
                    ("collector-401", None, provider_error(401, timeout_body), False),
                    ("finalizer-401", finalizer_state, provider_error(401, timeout_body), True),
                    ("finalizer-403", finalizer_state, provider_error(403, timeout_body), True),
                    ("unknown-wrapper", None, rt.EventLoopException(unknown), False),
                ):
                    await assert_hard_response(
                        client,
                        "Evidence" if state is not None else key,
                        key,
                        state,
                        error,
                        finalizer=finalizer,
                    )

                deep = planned_deep_state(20)
                deep.report_plan.clear()
                deep.stats["report_plan_sections"] = 0
                deep.stats["report_plan_target_chars"] = 0
                deep.phase = "evidence_complete"
                await assert_hard_response(
                    client,
                    "Evidence",
                    "plan-type-error",
                    deep,
                    TypeError("internal planner bug"),
                    finalizer=True,
                )

                with (
                    patch.object(
                        rt,
                        "reserve_run",
                        new=AsyncMock(return_value=("rid", "hash", None, None)),
                    ),
                    patch.object(
                        rt,
                        "build_research_agent",
                        return_value=HardFailureAgent(provider_error(503)),
                    ),
                    patch.object(rt, "MODEL_TRANSIENT_RECOVERIES", 0),
                    patch.object(rt, "AGENT_CANCEL_GRACE_SECONDS", 0.01),
                ):
                    response = await client.post(
                        "/research",
                        headers={
                            "Authorization": "Bearer test-api-key",
                            "X-OpenWebUI-Message-Id": "provider-503",
                        },
                        json={"query": "provider 503", "depth": "quick"},
                    )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.headers["x-openwebui-direct-output"], "true")
                self.assertEqual(response.headers["x-deep-research-status"], "failed")

        asyncio.run(run())

    def test_tool_dependency_programmer_errors_are_hard_http_failures(self) -> None:
        class ToolFailureAgent:
            def __init__(self, tools: list[Any], operation: str) -> None:
                self.tools = {tool.tool_name: tool for tool in tools}
                self.operation = operation

            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                searched = await self.tools["search_web"]("programmer error source")
                if self.operation == "fetch":
                    result = parse_tool_payload(searched)["results"][0]
                    await self.tools["fetch_source"](result["url"], "support claim")
                return SimpleNamespace(stop_reason="end_turn", message={"content": []})

        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            search_result = rt.SearchResult(
                "http://example.com/programmer-error",
                "Source",
                "snippet",
                "engine",
            )
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                for operation in ("search", "fetch"):
                    with (
                        patch.object(
                            rt,
                            "build_research_agent",
                            side_effect=lambda *args, operation=operation: ToolFailureAgent(
                                args[2], operation
                            ),
                        ),
                        patch.object(
                            rt,
                            "search_searxng",
                            new=AsyncMock(
                                side_effect=(
                                    TypeError("internal search bug")
                                    if operation == "search"
                                    else None
                                ),
                                return_value=[search_result],
                            ),
                        ),
                        patch.object(
                            rt,
                            "extract_evidence",
                            new=AsyncMock(side_effect=TypeError("internal fetch bug")),
                        ),
                        patch.object(rt, "AGENT_CANCEL_GRACE_SECONDS", 0.01),
                    ):
                        response = await client.post(
                            "/research",
                            headers={
                                "Authorization": "Bearer test-api-key",
                                "X-OpenWebUI-Message-Id": f"tool-{operation}-type-error",
                            },
                            json={"query": f"tool {operation} TypeError", "depth": "quick"},
                        )
                    self.assertEqual(response.status_code, 502)
                    self.assertNotIn("x-openwebui-direct-output", response.headers)
                    self.assertNotIn("x-deep-research-status", response.headers)

            for error in (KeyError("internal key bug"), IndexError("internal index bug")):
                state = make_state(0, "quick")
                with patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(side_effect=error),
                ):
                    tools, _allowlist, fatal = rt.build_research_tools(
                        self.runtime,
                        rt.ResearchRequest(query="programmer error", depth="quick"),
                        "rid",
                        f"tool-{type(error).__name__}",
                        "hash",
                        state,
                    )
                    result = await tools[0]("programmer error source")
                self.assertEqual(result["status"], "error")
                self.assertIsInstance(fatal[0], type(error))

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

    def test_successful_noop_repairs_are_bounded_and_checkpointed_by_reason(self) -> None:
        research = rt.ResearchRequest(query="compare Evidence alternatives", depth="deep")

        async def fail_noop(
            action: rt.ReportAction,
            state: rt.RunState,
            key: str,
        ) -> dict[str, Any]:
            actual, heading, _reason = rt.next_report_action(state, research)
            self.assertEqual(actual, action)
            section = next(item for item in state.report_sections if item.heading == heading)
            structured = StructuredAgent(
                [
                    rt.ReportSectionDraft(
                        heading=section.heading,
                        body_markdown=section.body,
                        summary=section.summary,
                    )
                ]
            )
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("completed collection must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                self.assertRaisesRegex(rt.IncompleteResearchError, "normal_contract_unmet"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    key,
                    rt.run_state_snapshot(state),
                )
            self.assertEqual(structured.models, [rt.ReportSectionDraft])
            row = self.runtime.db.execute(
                "SELECT state_json FROM research_runs WHERE idempotency_key=?",
                (key,),
            ).fetchone()
            snapshot = cast(dict[str, Any], json.loads(row["state_json"]))
            self.assertEqual(snapshot["repair_noop_counts"][action], 1)
            self.assertEqual(len(snapshot["repair_noop_fingerprints"]), 1)
            self.assertEqual(len(snapshot["report_sections"]), len(state.report_sections))
            return snapshot

        async def run() -> None:
            expand = planned_deep_state(20)
            expand.report_sections = report_sections(20)
            expand.report_sections[0] = rt.ReportSection(
                "Section 1",
                ("Short but substantive evidence [S1]. " * 30).strip(),
                expand.evidence_revision,
                "Short section",
            )
            expand_snapshot = await fail_noop("expand_existing", expand, "noop-expand")

            citation = planned_deep_state(20)
            citation.report_sections = [
                rt.ReportSection(
                    section.heading,
                    section.body,
                    citation.evidence_revision,
                    section.summary,
                )
                for section in report_sections(1)
            ]
            await fail_noop("citation_repair", citation, "noop-citation")

            source_ids = [f"S{index}" for index in range(1, 21)]
            max_plan = [
                rt.ReportPlanSection(
                    heading=f"Max Section {index}",
                    target_chars=5_000,
                    source_ids=source_ids,
                    deliverables=[f"Deliverable {index}"],
                )
                for index in range(1, rt.DEEP_PLAN_MAX_SECTIONS + 1)
            ]
            deliverable = planned_deep_state(20)
            deliverable.report_plan = max_plan
            body = deep_section_body(20)
            deliverable.report_sections = [
                rt.ReportSection(
                    item.heading,
                    body,
                    deliverable.evidence_revision,
                    f"Summary {index}",
                )
                for index, item in enumerate(max_plan, 1)
            ]
            deliverable.report_sections[0] = rt.ReportSection(
                "Max Section 1",
                "| Option | Result |\n|---|---|\n| A | uncited |\n\n" + body,
                deliverable.evidence_revision,
                "Comparison summary",
            )
            await fail_noop("deliverable_repair", deliverable, "noop-deliverable")
            self.assertEqual(len(deliverable.report_sections), rt.DEEP_PLAN_MAX_SECTIONS)

            with (
                patch.object(
                    rt,
                    "build_finalization_agent",
                    side_effect=AssertionError("checkpointed no-op must not be retried"),
                ),
                self.assertRaisesRegex(rt.IncompleteResearchError, "normal_contract_unmet"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    research,
                    "rid",
                    "noop-expand",
                    expand_snapshot,
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

    def test_incomplete_diagnostics_bound_long_headings_and_hide_raw_inputs(self) -> None:
        long_heading = "機" * 200
        state = planned_deep_state(20)
        state.report_plan[0] = state.report_plan[0].model_copy(update={"heading": long_heading})
        structured = StructuredAgent(
            [rt.MaxTokensReachedException("DRAFT_SECRET_SENTINEL") for _ in range(3)]
        )

        async def run() -> None:
            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("collection decision must be preserved"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=structured),
                self.assertRaisesRegex(
                    rt.IncompleteResearchError, "structured_section_attempts"
                ) as failure,
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="REQUEST_SECRET_SENTINEL", depth="deep"),
                    "rid",
                    "safe-diagnostics-key",
                    rt.run_state_snapshot(state),
                )
            output = failure.exception.answer_markdown
            self.assertNotIn(long_heading, output)
            self.assertNotIn("REQUEST_SECRET_SENTINEL", output)
            self.assertNotIn("DRAFT_SECRET_SENTINEL", output)
            snapshot = json.loads(
                self.runtime.db.execute(
                    "SELECT state_json FROM research_runs "
                    "WHERE idempotency_key='safe-diagnostics-key'"
                ).fetchone()[0]
            )
            self.assertTrue(all(len(item) <= 200 for item in snapshot["unmet_requirements"]))

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

    def test_fatal_tool_error_wins_timeout_wall_and_structured_failure_races(self) -> None:
        async def run() -> None:
            fatal = [rt.IntegrityError("fatal tool integrity")]

            class ProviderConflict:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    raise TimeoutError("provider timeout")

            with (
                patch.object(rt, "build_research_tools", return_value=([], {}, fatal)),
                patch.object(rt, "build_research_agent", return_value=ProviderConflict()),
                self.assertRaisesRegex(rt.IntegrityError, "fatal tool integrity"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "provider-rid",
                    "fatal-provider-key",
                )

            class WallConflict:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    await asyncio.sleep(1)
                    raise AssertionError("wall timeout must cancel")

            with (
                patch.object(rt, "wall_budget_seconds", return_value=0.01),
                patch.object(rt, "build_research_tools", return_value=([], {}, fatal)),
                patch.object(rt, "build_research_agent", return_value=WallConflict()),
                self.assertRaisesRegex(rt.IntegrityError, "fatal tool integrity"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "wall-rid",
                    "fatal-wall-key",
                )

            class StructuredConflict:
                async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                    raise rt.MaxTokensReachedException("structured exhausted")

            with (
                patch.object(rt, "build_research_tools", return_value=([], {}, fatal)),
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=AssertionError("completed collection must not restart"),
                ),
                patch.object(rt, "build_finalization_agent", return_value=StructuredConflict()),
                self.assertRaisesRegex(rt.IntegrityError, "fatal tool integrity"),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="Evidence", depth="quick"),
                    "structured-rid",
                    "fatal-structured-key",
                    rt.run_state_snapshot(stable_quick_state()),
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
