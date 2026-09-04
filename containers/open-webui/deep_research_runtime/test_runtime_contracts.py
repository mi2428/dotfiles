from __future__ import annotations

import asyncio
import json
import os
import unittest
from dataclasses import replace
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import aiohttp
import httpx
from openai import APIConnectionError, APIError, APIStatusError
from pydantic import ValidationError
from strands.agent.conversation_manager import SlidingWindowConversationManager
from strands.tools.executors import SequentialToolExecutor

from test_support import FakeResponse, FakeSession, RuntimeTestCase, make_state, rt


def deep_plan_for(research: rt.ResearchRequest) -> rt.PlanDraft:
    fragments = rt.explicit_request_fragments(research)
    requirements = [
        rt.RequirementModel(
            id=f"R{index}",
            summary=fragment.text,
            kind=rt.classify_requirement_kind(fragment.text),
            fragment_ids=[fragment.id],
        )
        for index, fragment in enumerate(fragments, 1)
    ]
    sections = [
        rt.PlanSection(
            heading=f"Section {index}",
            requirement_ids=[requirement.id],
        )
        for index, requirement in enumerate(requirements, 1)
    ]
    return rt.PlanDraft(
        requirements=requirements,
        sections=sections,
    )


def cited(text: str, *source_ids: str) -> rt.CitedPlainText:
    return rt.CitedPlainText(text=text, source_ids=list(source_ids))


def table_row(cells: list[str], *source_ids: str) -> rt.ReportTableRow:
    return rt.ReportTableRow(cells=cells, source_ids=list(source_ids))


def table(headers: list[str], rows: list[rt.ReportTableRow], title: str = "") -> rt.ReportTable:
    return rt.ReportTable(title=title, headers=headers, rows=rows)


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


def render_contract() -> rt.SectionContract:
    return rt.SectionContract(
        heading="Summary",
        ledger_revision=0,
        evidence=(),
        requirements=(),
        covered_requirement_ids=(),
        gap_requirement_ids=(),
        host_thresholds=(),
        requires_comparison_table=False,
    )


class RuntimeContractTests(RuntimeTestCase):
    def test_openapi_auth_and_cached_markdown(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                self.assertEqual(
                    (await client.post("/research", json={"query": "x"})).status_code, 401
                )
                cached = rt.FinalReport(
                    version=2,
                    answer_markdown="done [S1]",
                    outcome="completed",
                ).model_dump()
                with patch.object(
                    rt,
                    "reserve_run",
                    new=AsyncMock(return_value=("rid", "hash", cached, None)),
                ):
                    response = await client.post(
                        "/research",
                        headers={"Authorization": "Bearer test-api-key"},
                        json={"query": "cached"},
                    )
                self.assertEqual(response.text, "done [S1]")
                self.assertEqual(response.headers["x-openwebui-direct-output"], "true")
                self.assertEqual(response.headers["x-deep-research-status"], "completed")

        asyncio.run(run())

    def test_openapi_cached_degraded_report_uses_degraded_status_header(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                cached = rt.FinalReport(
                    version=2,
                    answer_markdown=(
                        "> Degraded report\n\n## Summary\n\nBody [S1]\n\n"
                        "## Limitations\n- gap\n\n## Sources\n"
                        "[1] https://example.com — <https://example.com>"
                    ),
                    outcome="degraded",
                ).model_dump()
                with patch.object(
                    rt,
                    "reserve_run",
                    new=AsyncMock(return_value=("rid", "hash", cached, None)),
                ):
                    response = await client.post(
                        "/research",
                        headers={"Authorization": "Bearer test-api-key"},
                        json={"query": "cached"},
                    )
            self.assertEqual(response.headers["x-deep-research-status"], "degraded")

        asyncio.run(run())

    def test_openapi_rejects_wrong_auth_scheme_and_key(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                wrong_scheme = await client.post(
                    "/research",
                    headers={"Authorization": "Basic nope"},
                    json={"query": "x"},
                )
                wrong_key = await client.post(
                    "/research",
                    headers={"Authorization": "Bearer wrong-key"},
                    json={"query": "x"},
                )
            self.assertEqual(wrong_scheme.status_code, 401)
            self.assertEqual(wrong_key.status_code, 401)

        asyncio.run(run())

    def test_openapi_preserves_incomplete_cancel_and_fatal_boundaries(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            headers = {"Authorization": "Bearer test-api-key"}
            reserved = AsyncMock(return_value=("rid", "hash", None, None))
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                with (
                    patch.object(rt, "reserve_run", new=reserved),
                    patch.object(
                        rt,
                        "run_research",
                        new=AsyncMock(
                            side_effect=rt.IncompleteResearchError("no_progress", "partial\n")
                        ),
                    ),
                ):
                    incomplete = await client.post(
                        "/research", headers=headers, json={"query": "incomplete"}
                    )
                self.assertEqual(incomplete.text, "partial\n")
                self.assertTrue(incomplete.headers["content-type"].startswith("text/plain"))
                self.assertEqual(incomplete.headers["x-openwebui-direct-output"], "true")
                self.assertEqual(incomplete.headers["x-deep-research-status"], "failed")

                with (
                    patch.object(rt, "reserve_run", new=reserved),
                    patch.object(
                        rt,
                        "run_research",
                        new=AsyncMock(side_effect=asyncio.CancelledError()),
                    ),
                ):
                    cancelled = await client.post(
                        "/research", headers=headers, json={"query": "cancelled"}
                    )
                self.assertEqual(cancelled.status_code, 499)

                with (
                    patch.object(rt, "reserve_run", new=reserved),
                    patch.object(
                        rt,
                        "run_research",
                        new=AsyncMock(side_effect=rt.IntegrityError("corrupt")),
                    ),
                    self.assertLogs(rt.LOG.name, level="ERROR"),
                ):
                    fatal = await client.post("/research", headers=headers, json={"query": "fatal"})
                self.assertEqual(fatal.status_code, 502)

        asyncio.run(run())

    def test_final_report_renders_exact_sources_and_empty_limitations_policy(self) -> None:
        research = rt.ResearchRequest(query="Evidence", depth="quick")
        state = make_state(3, "quick")
        state.evidence[0] = replace(
            state.evidence[0],
            title="Line 1\nLine 2 [S999] <b>*x*</b>",
            url="https://example.com/a_(b)",
        )
        rt.set_collection_decision(state, "voluntary_stop")
        state.report_sections = [
            rt.ReportSection(
                "Summary",
                "Answer [S2] [S1]",
                state.evidence_revision,
                "summary",
                [],
                ["S1", "S2"],
                "structured",
            )
        ]
        report = rt.finalize_report(state, research)
        self.assertIn("Answer [2] [1]", report.answer_markdown)
        self.assertIn("## Limitations\n- なし", report.answer_markdown)
        self.assertIn(
            (
                "[1] "
                f"{rt.neutralize_model_text('Line 1 Line 2 [S999] <b>*x*</b>')} "
                "— <https://example.com/a_(b)>"
            ),
            report.answer_markdown,
        )
        sources = report.answer_markdown.split("## Sources\n", 1)[1]
        self.assertIn("[2] Source 2", sources)
        self.assertNotIn("[3] Source 3", sources)
        self.assertEqual(report.outcome, "completed")
        with (
            patch.object(rt, "MAX_ANSWER_CHARS", 20),
            self.assertRaisesRegex(rt.IntegrityError, "answer limit"),
        ):
            rt.finalize_report(state, research)

    def test_target_evidence_environment_override_stays_between_minimum_and_cap(self) -> None:
        with patch.dict(
            os.environ,
            {
                "DEEP_RESEARCH_TARGET_EVIDENCE_DEEP": "25",
                "DEEP_RESEARCH_EVIDENCE_TARGET_DEEP": "40",
            },
        ):
            self.assertEqual(rt.make_budget("deep").target_evidence, 25)
        for invalid in (0, 61):
            with (
                self.subTest(invalid=invalid),
                patch.dict(os.environ, {"DEEP_RESEARCH_TARGET_EVIDENCE_DEEP": str(invalid)}),
                self.assertRaisesRegex(RuntimeError, "TARGET_EVIDENCE_DEEP"),
            ):
                rt.make_budget("deep")

    def test_idempotency_conflict_completed_cache_corruption_and_impossible_status(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="sample", depth="quick")
            key = rt.normalize_idempotency_key("message")
            research_id, request_hash, _cached, _snapshot = await rt.reserve_run(
                self.runtime, research, key
            )
            response = rt.FinalReport(
                version=2,
                answer_markdown="done [S1]",
                outcome="completed",
            )
            checkpoint = rt.run_state_snapshot(make_state(1, "quick"))
            with self.assertRaisesRegex(rt.IntegrityError, "versioned checkpoint"):
                await rt.checkpoint_run(
                    self.runtime,
                    key,
                    "completed",
                    research_id,
                    request_hash,
                    response=response.model_dump(),
                )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "completed",
                research_id,
                request_hash,
                response=response.model_dump(),
                state=checkpoint,
            )
            row = self.runtime.db.execute(
                "SELECT state_json FROM research_runs WHERE idempotency_key=?", (key,)
            ).fetchone()
            diagnostic = json.loads(row["state_json"])
            self.assertEqual(diagnostic["checkpoint_version"], 2)
            diagnostic["checkpoint_version"] = 1
            diagnostic["stats"]["depth"] = "corrupt"
            self.runtime.db.execute(
                "UPDATE research_runs SET state_json=? WHERE idempotency_key=?",
                (json.dumps(diagnostic), key),
            )
            self.runtime.db.commit()
            replay_id, _, replay, replay_state = await rt.reserve_run(self.runtime, research, key)
            self.assertEqual(replay_id, research_id)
            self.assertEqual(replay, response.model_dump())
            self.assertIsNone(replay_state)
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                cached_http = await client.post(
                    "/research",
                    headers={
                        "Authorization": "Bearer test-api-key",
                        "x-openwebui-message-id": "message",
                    },
                    json={"query": "sample", "depth": "quick"},
                )
            self.assertEqual(cached_http.text, response.answer_markdown)
            self.assertEqual(cached_http.headers["x-deep-research-status"], response.outcome)
            with self.assertRaises(rt.HTTPException) as conflict:
                await rt.reserve_run(
                    self.runtime,
                    rt.ResearchRequest(query="different", depth="quick"),
                    key,
                )
            self.assertEqual(conflict.exception.status_code, 409)
            self.runtime.db.execute(
                "UPDATE research_runs SET response_json='{}' WHERE idempotency_key=?",
                (key,),
            )
            self.runtime.db.commit()
            with self.assertRaisesRegex(rt.IntegrityError, "unsupported final report version"):
                await rt.reserve_run(self.runtime, research, key)

            bad_key = "impossible-status"
            self.runtime.db.execute(
                """
                INSERT INTO research_runs (
                    idempotency_key, request_hash, research_id, status,
                    response_json, state_json, created_at, updated_at
                ) VALUES (?, ?, 'rid', 'failed_with_output', NULL, NULL, 1, 1)
                """,
                (bad_key, request_hash),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
                await rt.reserve_run(self.runtime, research, bad_key)

        asyncio.run(run())

    def test_reserve_rejects_unversioned_checkpoint_without_mutating_row(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="sample", depth="quick")
            request_hash = rt.query_hash(research.model_dump())
            for key, version in (("missing-version", None), ("wrong-version", 1)):
                snapshot = rt.run_state_snapshot(make_state(1, "quick"))
                if version is None:
                    snapshot.pop("checkpoint_version")
                else:
                    snapshot["checkpoint_version"] = version
                self.runtime.db.execute(
                    """
                    INSERT INTO research_runs (
                        idempotency_key, request_hash, research_id, status,
                        response_json, state_json, created_at, updated_at
                    ) VALUES (?, ?, 'rid', 'failed', NULL, ?, 1, 1)
                    """,
                    (key, request_hash, json.dumps(snapshot)),
                )
                self.runtime.db.commit()
                with (
                    self.subTest(key=key),
                    self.assertRaisesRegex(rt.IntegrityError, "unsupported checkpoint version"),
                ):
                    await rt.reserve_run(self.runtime, research, key)
                row = self.runtime.db.execute(
                    "SELECT status FROM research_runs WHERE idempotency_key=?", (key,)
                ).fetchone()
                self.assertEqual(row["status"], "failed")

        asyncio.run(run())

    def test_structured_timeout_keeps_provider_240s_inside_existing_envelope(self) -> None:
        self.assertEqual(self.runtime.settings.kimi_timeout_seconds, 3600)
        self.assertEqual(rt.wall_budget_seconds("quick"), 3900)
        self.assertEqual(rt.structured_role_timeout_seconds(self.runtime.settings, 4000), 3300)
        self.assertEqual(rt.structured_role_timeout_seconds(self.runtime.settings, 1800), 1800)
        self.assertGreater(rt.structured_role_timeout_seconds(self.runtime.settings, 1800), 240)
        self.assertEqual(rt.structured_role_timeout_seconds(self.runtime.settings, 300), 300)

    def test_kimi_adapter_and_shared_agent_retry_contracts(self) -> None:
        standard = rt.ResearchRequest(query="standard coverage", depth="standard")
        agent = rt.build_research_agent(self.runtime.settings, standard, [])
        model = cast(rt.SakuraKimiModel, agent.model)
        finalizer_model = cast(
            rt.SakuraKimiModel,
            rt.build_finalization_agent(self.runtime.settings, standard).model,
        )
        manager = cast(SlidingWindowConversationManager, agent.conversation_manager)
        research_params = cast(dict[str, Any], model.config["params"])
        finalizer_params = cast(dict[str, Any], finalizer_model.config["params"])
        self.assertEqual(model.client_args["timeout"], 3600)
        self.assertEqual(model.client_args["max_retries"], 0)
        self.assertNotIn("tool_choice", research_params)
        self.assertEqual(finalizer_params["tool_choice"], "required")
        self.assertIsInstance(manager, SlidingWindowConversationManager)
        self.assertIsInstance(agent.tool_executor, SequentialToolExecutor)
        self.assertEqual(manager.window_size, 30)

        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        response = httpx.Response(503, request=request)
        wrapped = rt.EventLoopException(
            APIStatusError("provider error", response=response, body={})
        )
        self.assertEqual(rt.model_retry_delay(wrapped, 0), 10)
        self.assertTrue(rt.is_expected_provider_failure(wrapped))
        self.assertEqual(
            rt.safe_model_recovery_details(wrapped),
            rt.SafeModelRecoveryDetails(
                "provider_http_server_error",
                "http_status",
                503,
                "none",
                "other",
                "APIStatusError",
            ),
        )
        exhausted = rt.EventLoopException(
            APIStatusError(
                "provider error",
                response=httpx.Response(
                    503,
                    request=request,
                    headers={"X-Sakura-Retry-Count": "5"},
                ),
                body={},
            )
        )
        self.assertIsNone(rt.model_retry_delay(exhausted, 0))
        self.assertTrue(rt.is_expected_provider_failure(exhausted))
        connection_error = APIConnectionError(request=request)
        self.assertEqual(rt.model_retry_delay(connection_error, 0), 10)
        unauthorized = APIStatusError(
            "unauthorized",
            response=httpx.Response(401, request=request),
            body={},
        )
        self.assertIsNone(rt.model_retry_delay(unauthorized, 0))
        self.assertFalse(rt.is_expected_provider_failure(unauthorized))
        self.assertEqual(
            rt.safe_model_recovery_details(unauthorized),
            rt.SafeModelRecoveryDetails(
                "provider_auth_error",
                "http_status",
                401,
                "none",
                "other",
                "APIStatusError",
            ),
        )
        stream_error = APIError("Internal server error.", request=request, body=None)
        self.assertEqual(rt.MODEL_TRANSIENT_RECOVERIES, 5)
        self.assertEqual(
            [rt.model_retry_delay(stream_error, attempt) for attempt in range(5)],
            [10, 20, 40, 80, 120],
        )
        self.assertTrue(rt.is_expected_provider_failure(stream_error))
        self.assertEqual(
            rt.safe_model_recovery_details(stream_error),
            rt.SafeModelRecoveryDetails(
                "provider_internal_error",
                "message",
                None,
                "none",
                "internal_server_error",
                "APIError",
            ),
        )
        self.assertEqual(
            rt.safe_model_recovery_details(connection_error),
            rt.SafeModelRecoveryDetails(
                "provider_connection_error",
                "exception",
                None,
                "none",
                "other",
                "APIConnectionError",
            ),
        )
        self.assertEqual(
            rt.safe_model_recovery_details(TimeoutError("model returned no result")),
            rt.SafeModelRecoveryDetails(
                "model_empty_result",
                "runtime",
                None,
                "none",
                "empty_result",
                "TimeoutError",
            ),
        )
        coded = APIError(
            "provider failure",
            request=request,
            body={"error": {"code": "overloaded_error", "message": "busy"}},
        )
        self.assertEqual(
            rt.safe_model_recovery_details(coded),
            rt.SafeModelRecoveryDetails(
                "provider_internal_error",
                "provider_code",
                None,
                "overloaded_error",
                "other",
                "APIError",
            ),
        )
        self.assertEqual(
            rt.safe_operation_error_details(ValueError("fetch failed 503")),
            rt.SafeOperationErrorDetails(
                "http_error", "http_status", "ValueError", "ValueError", 503
            ),
        )
        self.assertEqual(
            rt.safe_operation_error_details(OSError("secret provider text")),
            rt.SafeOperationErrorDetails("os_error", "exception", "OSError", "OSError", None),
        )
        fatal = rt.safe_fatal_error_event(
            rt.ModelOutputError("Markdown table rows must use separate lines"), "sections"
        )
        self.assertEqual(fatal["reason"], "model_output_error")
        self.assertEqual(fatal["reason_source"], "validation")
        self.assertEqual(fatal["cause_exception"], "ModelOutputError")
        self.assertEqual(fatal["validation_bucket"], "Markdown table rows must use separate lines")

    def test_validated_requirements_plan_maps_every_explicit_fragment(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        draft = deep_plan_for(research)
        fragments, requirements, sections = rt.validated_initial_plan(research, draft)
        self.assertEqual("".join(item.text for item in fragments), research.query)
        schema = rt.PlanDraft.model_json_schema()
        self.assertEqual(set(schema["properties"]), {"requirements", "sections"})
        self.assertEqual(set(schema["required"]), {"requirements", "sections"})
        section_schema = schema["$defs"]["PlanSection"]
        self.assertEqual(set(section_schema["properties"]), {"heading", "requirement_ids"})
        self.assertEqual(set(section_schema["required"]), {"heading", "requirement_ids"})
        self.assertEqual(section_schema["properties"]["requirement_ids"]["minItems"], 1)
        for removed in (
            "InitialPlanDraft",
            "InitialPlanSection",
            "ReportPlanSection",
            "QuerySeedModel",
        ):
            self.assertFalse(hasattr(rt, removed))
        self.assertEqual(
            rt.build_plan_context(research)["request_fragments"],
            [item.model_dump() for item in fragments],
        )
        self.assertEqual(
            {fragment_id for item in requirements for fragment_id in item.fragment_ids},
            {item.id for item in fragments},
        )
        self.assertEqual([item.requirement_ids for item in sections], [["R1"]])

    def test_requirement_coverage_uses_direct_one_host_and_comparison_two_hosts(self) -> None:
        state = make_state(3)
        state.request_fragments = [
            rt.RequestFragmentModel(id="F1", text="facts"),
            rt.RequestFragmentModel(id="F2", text="compare"),
        ]
        state.requirements = [
            rt.RequirementModel(id="R1", summary="facts", kind="direct", fragment_ids=["F1"]),
            rt.RequirementModel(id="R2", summary="compare", kind="comparison", fragment_ids=["F2"]),
        ]
        state.evidence[0] = replace(
            state.evidence[0], requirement_ids=["R1"], url="https://a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], requirement_ids=["R2"], url="https://a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], requirement_ids=["R2"], url="https://b.example/3"
        )
        self.assertTrue(rt.requirement_is_covered(state, state.requirements[0]))
        self.assertTrue(rt.requirement_is_covered(state, state.requirements[1]))

    def test_section_content_schema_excludes_runtime_fields_and_requires_block_sources(
        self,
    ) -> None:
        schema = rt.SectionContentDraft.model_json_schema()
        self.assertEqual(set(schema["properties"]), {"paragraphs", "bullets", "tables"})
        self.assertEqual(schema["required"], ["paragraphs"])
        self.assertEqual(schema["properties"]["paragraphs"]["minItems"], 1)
        cited_schema = schema["$defs"]["CitedPlainText"]
        self.assertIn("source_ids", cited_schema["required"])
        self.assertEqual(cited_schema["properties"]["source_ids"]["minItems"], 1)
        row_schema = schema["$defs"]["ReportTableRow"]
        self.assertIn("source_ids", row_schema["required"])
        self.assertEqual(row_schema["properties"]["source_ids"]["minItems"], 1)
        for field in ("heading", "requirement_ids", "summary", "gap"):
            self.assertNotIn(field, schema["properties"])
        for payload in (
            {},
            {"paragraphs": [{"text": "Body"}]},
            {"paragraphs": [{"text": "Body", "source_ids": []}]},
            {"bullets": [{"text": "Body", "source_ids": []}]},
            {
                "tables": [
                    {
                        "headers": ["A", "B"],
                        "rows": [{"cells": ["1", "2"], "source_ids": []}],
                    }
                ]
            },
        ):
            with self.subTest(payload=payload), self.assertRaises(ValidationError):
                rt.SectionContentDraft.model_validate(payload)

    def test_renderer_is_deterministic_and_neutralizes_injected_markdown(self) -> None:
        draft = section(
            cited("First\nline ### fake [S999] <b>tag</b>", "S1", "S2"),
            bullets=[cited("- list | cell", "S3")],
            tables=[
                table(
                    ["H1", "H2|"],
                    [table_row(["A", "B [S999]\n### x <i>ok</i>"], "S4")],
                    title="T|itle",
                )
            ],
        )
        expected = "\n\n".join(
            [
                f"{rt.neutralize_model_text('First\nline ### fake [S999] <b>tag</b>')} [S1] [S2]",
                f"- {rt.neutralize_model_text('- list | cell')} [S3]",
                "\n".join(
                    [
                        rt.neutralize_model_text("T|itle"),
                        "",
                        f"| {rt.neutralize_model_text('H1')} | {rt.neutralize_model_text('H2|')} |",
                        "| --- | --- |",
                        (
                            f"| {rt.neutralize_model_text('A')} | "
                            f"{rt.neutralize_model_text('B [S999]\n### x <i>ok</i>')} [S4] |"
                        ),
                    ]
                ),
            ]
        )
        rendered = rt.render_section_markdown(render_contract(), draft)
        self.assertEqual(rendered, expected)
        self.assertEqual(rt.render_section_markdown(render_contract(), draft), expected)
        self.assertEqual(rt.citation_ids(rendered), {"S1", "S2", "S3", "S4"})
        self.assertIsNone(rt.report_markdown_structure_error(rendered))

    def test_table_rows_render_one_per_line_and_reject_width_mismatch(self) -> None:
        rendered = rt.render_section_markdown(
            render_contract(),
            section(
                cited("Intro", "S1"),
                tables=[
                    table(
                        ["A", "B"],
                        [table_row(["1", "2"], "S2"), table_row(["3", "4"], "S3")],
                    )
                ],
            ),
        )
        self.assertIn("| 1 | 2 [S2] |\n| 3 | 4 [S3] |", rendered)
        with self.assertRaises(ValidationError):
            table(["A", "B"], [table_row(["1", "2", "3"], "S1")])

    def test_element_length_and_blank_validation(self) -> None:
        with self.assertRaises(ValidationError):
            table(["A" * 201, "B"], [table_row(["1", "2"], "S1")])
        with self.assertRaises(ValidationError):
            table(["A", "B"], [table_row(["1", "x" * 501], "S1")])
        with self.assertRaises(ValidationError):
            cited("   ", "S1")

    def test_renderer_neutralizes_links_emphasis_backslashes_lists_and_rules(self) -> None:
        rendered = rt.render_section_markdown(
            render_contract(),
            section(
                cited(r"[label](https://x) **bold** _em_ ~~~ `code` \\path", "S1"),
                bullets=[cited("--- * item", "S2")],
            ),
        )
        self.assertNotIn("[label]", rendered)
        self.assertNotIn("**bold**", rendered)
        self.assertNotIn("_em_", rendered)
        self.assertNotIn("~~~", rendered)
        self.assertNotIn("\\path", rendered)
        self.assertNotIn("---", rendered.replace("| --- | --- |", ""))
        self.assertNotRegex(rendered, r"\[[^\]]+\]\([^)]*\)")
        self.assertNotRegex(rendered, r"\*\*[^*]+\*\*")
        self.assertNotRegex(rendered, r"_[^_]+_")
        self.assertIn("[S1]", rendered)
        self.assertIn("[S2]", rendered)

    def test_extractive_text_uses_the_same_plain_text_boundary(self) -> None:
        rendered = rt.safe_extractive_text(r"--- [S999] | **bold** \\path")

        self.assertNotIn("---", rendered)
        self.assertNotIn("[S999]", rendered)
        self.assertNotIn("|", rendered)
        self.assertNotIn("**bold**", rendered)
        self.assertNotIn("\\path", rendered)
        self.assertEqual(rt.citation_ids(rendered), set())

    def test_report_heading_rejects_inline_markdown(self) -> None:
        for heading in (
            "[x](y)",
            "**bold**",
            "A|B",
            "<b>x</b>",
            "[S1] title",
            "A\rB",
        ):
            with self.subTest(heading=heading), self.assertRaisesRegex(ValueError, "plain text"):
                rt.validated_report_heading(heading)

    def test_final_report_schema_is_versioned_and_minimal(self) -> None:
        schema = rt.FinalReport.model_json_schema()
        self.assertEqual(set(schema["properties"]), {"version", "answer_markdown", "outcome"})
        self.assertEqual(set(schema["required"]), {"version", "answer_markdown", "outcome"})
        with self.assertRaises(ValidationError):
            rt.FinalReport.model_validate(
                {"version": 1, "answer_markdown": "x", "outcome": "completed"}
            )

    def test_safe_section_validation_error_rejects_suffix_smuggling(self) -> None:
        self.assertEqual(
            rt.safe_section_validation_error("missing cited evidence for R12"),
            "missing cited evidence for R12",
        )
        self.assertEqual(
            rt.safe_section_validation_error("insufficient independent hosts for R7"),
            "insufficient independent hosts for R7",
        )
        self.assertEqual(
            rt.safe_section_validation_error("missing cited evidence for R12 secret"),
            "report section failed semantic validation",
        )
        self.assertEqual(
            rt.safe_section_validation_error("insufficient independent hosts for R7 extra"),
            "report section failed semantic validation",
        )

    def test_report_markdown_structure_rejects_flattened_blocks(self) -> None:
        self.assertEqual(
            rt.report_markdown_structure_error("Intro ### Detail"),
            "Markdown headings must start on separate lines",
        )
        self.assertEqual(
            rt.report_markdown_structure_error("### Detail and flattened prose"),
            "Markdown headings must start on separate lines",
        )
        self.assertEqual(
            rt.report_markdown_structure_error("| A | B | | --- | --- | | 1 | 2 |"),
            "Markdown table rows must use separate lines",
        )
        self.assertIsNone(
            rt.report_markdown_structure_error(
                "Intro\n\n### Detail\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
            )
        )

    def test_finalize_report_allows_short_complete_report_and_rejects_missing_sections(
        self,
    ) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.set_collection_decision(state, "coverage_complete")
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Section 1"),
            section(cited("Supported claim", "S1")),
        )
        response = rt.finalize_report(state, research)
        self.assertIn("## Sources", response.answer_markdown)
        broken = replace(state, report_sections=[])
        with self.assertRaisesRegex(rt.IntegrityError, "incomplete or out of order"):
            rt.finalize_report(broken, research)

    def test_accepted_short_section_is_finalized_without_repair(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.set_collection_decision(state, "coverage_complete")
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Section 1"),
            section(cited("Short but cited", "S1")),
        )
        self.assertEqual(rt.finalize_report(state, research).outcome, "completed")

    def test_compact_payload_builders_exclude_unrelated_growth(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="with focus", depth="deep"
        )
        state = make_state(3)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="Need direct evidence", kind="direct", fragment_ids=["F1"]
            )
        ]
        state.evidence = [
            replace(item, requirement_ids=["R1"], relevance=0.9) for item in state.evidence
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Section 1",
                requirement_ids=["R1"],
            )
        ]
        state.report_sections = [
            rt.ReportSection(
                "Done",
                "Claim [S1]",
                state.evidence_revision,
                "summary",
                ["R1"],
                ["S1"],
                "structured",
            )
        ]
        state.candidate_queue = [
            rt.Candidate(
                url="https://other.example/4",
                title="Other",
                snippet="noise",
                engine="engine",
                search_query="noise",
                purpose="noise",
                requirement_id="R1",
            )
        ]
        query_payload = rt.build_query_context(research, state)
        contract = rt.build_section_contract(research, state, "Section 1")
        section_payload = rt.build_section_context(research, state, contract)
        self.assertNotIn("evidence", query_payload)
        self.assertNotIn("candidate_queue", query_payload)
        self.assertEqual(len(section_payload["assigned_evidence"]), 3)
        self.assertEqual(
            section_payload["section_contract"],
            {
                "heading": "Section 1",
                "ledger_revision": state.evidence_revision,
                "requirements": [
                    {
                        "id": "R1",
                        "summary": "Need direct evidence",
                        "kind": "direct",
                        "required_independent_host_count": 1,
                        "assigned_source_ids": ["S1", "S2", "S3"],
                    }
                ],
                "covered_requirement_ids": ["R1"],
                "gap_requirement_ids": [],
                "requires_comparison_table": False,
            },
        )
        self.assertEqual(section_payload["assigned_evidence"][0]["requirement_ids"], ["R1"])
        self.assertEqual(
            section_payload["completed_sections"],
            [
                {
                    "heading": "Done",
                    "requirement_ids": ["R1"],
                    "summary": "summary",
                    "source_ids": ["S1"],
                }
            ],
        )

    def test_section_contract_prompt_and_validator_share_exact_twelve_sources(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(13)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1",
                summary="Need direct evidence",
                kind="direct",
                fragment_ids=["F1"],
            )
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Evidence",
                requirement_ids=["R1"],
            )
        ]
        state.evidence = [
            replace(item, relevance=0.9, requirement_ids=["R1"]) for item in state.evidence
        ]
        contract = rt.build_section_contract(research, state, "Evidence")
        prompt = json.loads(rt.build_section_prompt(research, state, contract))
        expected_ids = [item.id for item in contract.evidence]
        self.assertEqual(expected_ids, [f"S{index}" for index in range(1, 13)])
        self.assertEqual([item["id"] for item in prompt["assigned_evidence"]], expected_ids)
        state.last_inspected_revision = state.evidence_revision
        before = rt.run_state_snapshot(state)
        with self.assertRaisesRegex(rt.ModelOutputError, "section contract"):
            rt.store_report_section(
                state,
                contract,
                section(cited("Unseen", "S13")),
            )
        self.assertEqual(rt.run_state_snapshot(state), before)

    def test_ledger_update_preserves_plan_and_rederives_section_evidence(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        plan = [item.model_dump() for item in state.report_plan]
        self.assertEqual(
            [item.id for item in rt.build_section_contract(research, state, "Section 1").evidence],
            ["S1"],
        )

        rt.apply_evidence_update(
            state,
            rt.Evidence(
                url="https://second.example/2",
                title="Second",
                publisher="Second",
                published_at="2026-01-01",
                excerpt="Additional direct evidence",
                hash="b" * 64,
                relevance=0.9,
                source_quality=0.7,
                requirement_ids=["R1"],
            ),
        )

        self.assertEqual([item.model_dump() for item in state.report_plan], plan)
        self.assertEqual(state.stats["report_plan_sections"], 1)
        self.assertEqual(
            [item.id for item in rt.build_section_contract(research, state, "Section 1").evidence],
            ["S1", "S2"],
        )

    def test_rendered_section_over_ten_thousand_chars_is_not_checkpointed(self) -> None:
        research = rt.ResearchRequest(query="Evidence", depth="standard")
        state = make_state(1, "standard")
        state.last_inspected_revision = state.evidence_revision
        contract = rt.build_section_contract(research, state)
        draft = section(*(cited("x" * 1200, "S1") for _ in range(9)))
        self.assertGreater(len(rt.render_section_markdown(contract, draft)), 10_000)
        before = rt.run_state_snapshot(state)
        with self.assertRaisesRegex(ValueError, "section body"):
            rt.store_report_section(state, contract, draft)
        self.assertEqual(rt.run_state_snapshot(state), before)

    def test_gap_only_section_is_bounded_after_markdown_neutralization(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        state = make_state(rt.MAX_PAYLOAD_EVIDENCE_EXCERPTS)
        state.request_fragments = rt.explicit_request_fragments(research)
        unsafe = "[]#|<>`*_~\\"
        summary = (unsafe * 30)[:300]
        state.requirements = [
            rt.RequirementModel(
                id=f"R{index}", summary=summary, kind="comparison", fragment_ids=["F1"]
            )
            for index in range(1, 6)
        ]
        requirement_ids = [item.id for item in state.requirements]
        state.report_plan = [
            rt.PlanSection(
                heading="Comparison",
                requirement_ids=requirement_ids,
            )
        ]
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
        state.last_inspected_revision = state.evidence_revision
        rt.set_collection_decision(state, "voluntary_stop")
        contract = rt.build_section_contract(research, state, "Comparison")
        self.assertEqual(contract.covered_requirement_ids, ())
        rt._store_gap_section(state, contract)
        body = state.report_sections[0].body
        self.assertLess(len(body), rt.MAX_REPORT_SECTION_CHARS)
        self.assertEqual(body.count("Runtime partial evidence:"), 1)
        self.assertEqual(body.count("Runtime coverage gap:"), 5)
        self.assertIn(rt.safe_extractive_text(summary, 300), body)
        self.assertIn("[S1]", state.report_sections[0].body)
        rt.validate_checkpoint_state(state, research)

    def test_query_context_keeps_lossless_max_input_fragments(self) -> None:
        query = "q" * rt.MAX_QUERY_CHARS
        focus = "," * rt.MAX_FOCUS_CHARS
        research = rt.ResearchRequest(query=query, focus=focus, depth="deep")
        fragments = rt.explicit_request_fragments(research)
        self.assertEqual("".join(item.text for item in fragments), query + focus)
        payload = rt.build_plan_context(research)
        self.assertEqual(
            "".join(item["text"] for item in payload["request_fragments"]), query + focus
        )

    def test_network_boundaries_block_ssrf_bad_content_and_oversize_bodies(self) -> None:
        with self.assertRaises(ValueError):
            rt.validate_public_url("http://127.0.0.1/x")

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
                response = cast(aiohttp.ClientResponse, FakeResponse(chunks=[b"a" * 5, b"b" * 5]))
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

    def test_plan_and_search_schemas_are_exact_and_scalar(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        plan = deep_plan_for(research).model_dump()
        for field, value in (
            ("target_chars", 400),
            ("deliverables", ["echo"]),
            ("source_ids", ["S1"]),
        ):
            invalid = json.loads(json.dumps(plan))
            invalid["sections"][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValidationError):
                rt.PlanDraft.model_validate(invalid)
        plan["query_seeds"] = []
        with self.assertRaises(ValidationError):
            rt.PlanDraft.model_validate(plan)

        schema = rt.SearchBatchEntry.model_json_schema()
        self.assertEqual(set(schema["properties"]), {"query", "purpose", "requirement_id"})
        self.assertEqual(set(schema["required"]), {"query", "purpose", "requirement_id"})
        for payload in (
            {"query": "q", "purpose": "p"},
            {"query": "q", "purpose": "p", "requirement_ids": ["R1"]},
            {"query": "q", "purpose": "p", "requirement_id": ["R1"]},
        ):
            with self.subTest(payload=payload), self.assertRaises(ValidationError):
                rt.SearchBatchEntry.model_validate(payload)

        state = make_state(1)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="Need direct evidence", kind="direct", fragment_ids=["F1"]
            )
        ]
        unknown = rt.SearchBatchEntry(query="q", purpose="p", requirement_id="R2")
        with self.assertRaisesRegex(ValueError, "active requirement"):
            rt.validated_query_entry(state, unknown)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        covered = rt.SearchBatchEntry(query="q", purpose="p", requirement_id="R1")
        self.assertEqual(rt.validated_query_entry(state, covered), covered)

    def test_enrichment_helpers_compute_floor_score_target_and_bonus_order(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence", focus="compare vendors", depth="deep"
        )
        state = make_state(4)
        rt.store_initial_plan(state, research, deep_plan_for(research))
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1-a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], url="https://r2-a.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R2"], url="https://r2-b.example/3"
        )
        self.assertEqual(rt.total_required_hosts(state), 3)
        self.assertEqual(rt.enrichment_target_hosts(state), 4)
        self.assertEqual(rt.enrichment_host_score(state), 3)
        self.assertEqual(rt.active_requirement_ids(state), ["R1", "R2"])
        self.assertEqual(
            rt.requirement_excerpt_chars(state, "R2"),
            len(state.evidence[1].excerpt) * 2,
        )

    def test_one_requirement_cannot_satisfy_soft_target_alone(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(4)
        fragments = rt.explicit_request_fragments(research)
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
                    rt.PlanSection(heading="First", requirement_ids=["R1"]),
                    rt.PlanSection(heading="Second", requirement_ids=["R2"]),
                ],
            ),
        )
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://r1-a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R1"], url="https://r1-b.example/2"
        )
        state.evidence[2] = replace(
            state.evidence[2], relevance=0.9, requirement_ids=["R1"], url="https://r1-c.example/3"
        )
        state.evidence[3] = replace(
            state.evidence[3], relevance=0.9, requirement_ids=["R1"], url="https://r1-d.example/4"
        )
        capped_limit = rt.requirement_floor(state.requirements[0]) + 1
        self.assertLessEqual(
            rt.capped_requirement_host_score(state, state.requirements[0]), capped_limit
        )
        self.assertLess(rt.enrichment_host_score(state), rt.enrichment_target_hosts(state))

    def test_enrichment_prioritizes_the_thinner_excerpt_material(self) -> None:
        research = rt.ResearchRequest(query="first fact; second fact", depth="deep")
        state = make_state(2)
        fragments = rt.explicit_request_fragments(research)
        rt.store_initial_plan(
            state,
            research,
            rt.PlanDraft(
                requirements=[
                    rt.RequirementModel(
                        id="R1", summary="first", kind="direct", fragment_ids=[fragments[0].id]
                    ),
                    rt.RequirementModel(
                        id="R2", summary="second", kind="direct", fragment_ids=[fragments[-1].id]
                    ),
                ],
                sections=[
                    rt.PlanSection(heading="First", requirement_ids=["R1"]),
                    rt.PlanSection(heading="Second", requirement_ids=["R2"]),
                ],
            ),
        )
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], excerpt="rich " * 100
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R2"], excerpt="thin"
        )

        self.assertEqual(rt.active_requirement_ids(state), ["R2", "R1"])

    def test_compare_fragment_kind_is_upgraded_by_runtime(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        fragments = rt.explicit_request_fragments(research)
        draft = rt.PlanDraft(
            requirements=[
                rt.RequirementModel(
                    id="R1",
                    summary="compare vendors",
                    kind="direct",
                    fragment_ids=[fragments[0].id],
                )
            ],
            sections=[
                rt.PlanSection(
                    heading="Comparison",
                    requirement_ids=["R1"],
                )
            ],
        )
        _fragments, requirements, _sections = rt.validated_initial_plan(research, draft)
        self.assertEqual(requirements[0].kind, "comparison")
        state = make_state(1)
        state.request_fragments = fragments
        state.requirements = requirements
        state.evidence[0] = replace(
            state.evidence[0], requirement_ids=["R1"], url="https://a.example/1"
        )
        self.assertFalse(rt.requirement_is_covered(state, requirements[0]))

    def test_gap_context_and_prompt_disclose_gap_and_forbid_unsupported_claims(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        fragments = rt.explicit_request_fragments(research)
        state.request_fragments = fragments
        state.requirements = [
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
        ]
        state.evidence[0] = replace(state.evidence[0], requirement_ids=["R1"], relevance=0.9)
        state.report_plan = [
            rt.PlanSection(
                heading="Compare",
                requirement_ids=["R2"],
            )
        ]
        contract = rt.build_section_contract(research, state, "Compare")
        context = rt.build_section_context(research, state, contract)
        self.assertEqual(
            context["section_contract"]["requirements"],
            [
                {
                    "id": "R2",
                    "summary": "compare vendors",
                    "kind": "comparison",
                    "required_independent_host_count": 2,
                    "assigned_source_ids": [],
                }
            ],
        )
        self.assertEqual(context["coverage_gaps"][0]["required_hosts"], 2)
        prompt = rt.build_section_prompt(research, state, contract)
        prompt_payload = json.loads(prompt)
        self.assertIn("unsupported claims", prompt)
        self.assertIn("assigned_evidence", prompt)
        self.assertNotIn("body_markdown", prompt)
        self.assertTrue(any("paragraphs.text" in item for item in prompt_payload["requirements"]))
        self.assertTrue(
            any("Use source_ids only" in item for item in prompt_payload["requirements"])
        )
        self.assertNotIn(
            "requirement_ids", rt.SectionContentDraft.model_json_schema()["properties"]
        )
        self.assertTrue(
            any(
                "required_independent_host_count distinct hosts" in item
                for item in prompt_payload["requirements"]
            )
        )
        self.assertTrue(
            any(
                "assigned_evidence.requirement_ids" in item and "assigned_evidence.url" in item
                for item in prompt_payload["requirements"]
            )
        )
        self.assertTrue(
            any(
                "runtime renders all headings, bullets, tables" in item
                for item in prompt_payload["requirements"]
            )
        )
        self.assertTrue(
            any(
                "aim for about 8 non-duplicate cited information units" in item
                and "paragraphs, substantive bullet items, and table rows" in item
                and "Prefer fewer units over padding" in item
                for item in prompt_payload["requirements"]
            )
        )
        self.assertNotIn("hard 8", prompt)
        self.assertNotIn("validator", prompt)

    def test_standard_and_quick_section_prompts_receive_usable_evidence(self) -> None:
        for depth in ("standard", "quick"):
            with self.subTest(depth=depth):
                research = rt.ResearchRequest(query="Evidence", depth=depth)
                state = make_state(1, depth)
                contract = rt.build_section_contract(research, state)
                prompt_payload = json.loads(rt.build_section_prompt(research, state, contract))
                self.assertNotIn("body_markdown", json.dumps(prompt_payload, ensure_ascii=False))
                self.assertFalse(
                    any(
                        "aim for about 8 non-duplicate cited information units" in item
                        for item in prompt_payload["requirements"]
                    )
                )
                self.assertNotIn("hard 8", json.dumps(prompt_payload, ensure_ascii=False))
                self.assertNotIn("validator", json.dumps(prompt_payload, ensure_ascii=False))
                self.assertEqual(
                    [item["id"] for item in prompt_payload["assigned_evidence"]], ["S1"]
                )
                self.assertEqual(contract.heading, "Summary")
                state.last_inspected_revision = state.evidence_revision
                before = rt.run_state_snapshot(state)
                with self.assertRaisesRegex(rt.ModelOutputError, "section contract"):
                    rt.store_report_section(
                        state,
                        contract,
                        section(cited("Unseen", "S2")),
                    )
                self.assertEqual(rt.run_state_snapshot(state), before)
                comparison = rt.build_section_contract(
                    rt.ResearchRequest(query="compare vendors", depth=depth), state
                )
                self.assertTrue(comparison.requires_comparison_table)
                before = rt.run_state_snapshot(state)
                with self.assertRaisesRegex(rt.ModelOutputError, "requires a table"):
                    rt.store_report_section(
                        state,
                        comparison,
                        section(cited("Free text", "S1")),
                    )
                self.assertEqual(rt.run_state_snapshot(state), before)

    def test_runtime_limitations_are_bounded_neutralized_and_deduplicated(self) -> None:
        state = make_state(1, "deep")
        state.requirements = [
            rt.RequirementModel(
                id="R1",
                summary="[S999] **missing**",
                kind="direct",
                fragment_ids=["F1"],
            )
        ]
        state.report_sections = [
            rt.ReportSection(
                "Fallback",
                "Body [S1]",
                state.evidence_revision,
                "summary",
                ["R1"],
                ["S1"],
                "extractive",
            ),
            rt.ReportSection(
                "Fallback",
                "Body [S1]",
                state.evidence_revision,
                "summary",
                ["R1"],
                ["S1"],
                "extractive",
            ),
        ]
        limitations = rt.runtime_limitations(state)
        self.assertEqual(len(limitations), 2)
        self.assertTrue(all(len(item) <= rt.MAX_LIMITATION_CHARS for item in limitations))
        self.assertNotIn("[S999]", " ".join(limitations))
        self.assertNotIn("**missing**", " ".join(limitations))

    def test_model_output_error_retries_but_checkpoint_corruption_stays_integrity_error(
        self,
    ) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        with self.assertRaises(rt.ModelOutputError):
            rt.store_report_section(
                state,
                rt.build_section_contract(research, state, "Section 1"),
                section(cited("Bad citation", "S9")),
            )
        corrupt = rt.run_state_snapshot(state)
        corrupt["report_sections"] = [
            {
                "heading": "Section 1",
                "body": "Bad citation [S9]",
                "ledger_revision": state.evidence_revision,
                "summary": "summary",
                "requirement_ids": ["R1"],
                "source_ids": ["S9"],
                "mode": "structured",
            }
        ]
        loaded = rt.load_run_state(
            corrupt,
            depth="deep",
            budget=rt.make_budget("deep"),
            wall_limit=rt.wall_budget_seconds("deep"),
        )
        with self.assertRaises(rt.IntegrityError):
            rt.validate_checkpoint_state(loaded, research)

    def test_extraction_provenance_and_status_invariants(self) -> None:
        async def run() -> None:
            raw = (
                b"<html><body><article>Performance evidence with enough substantive text."
                b"</article></body></html>"
            )
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

            request = rt.ResearchRequest(query="sample", depth="quick")
            key = rt.normalize_idempotency_key("message")
            research_id, request_hash, cached, snapshot = await rt.reserve_run(
                self.runtime, request, key
            )
            self.assertIsNone(cached)
            self.assertIsNone(snapshot)
            state = make_state(1, "quick")
            with self.assertRaisesRegex(rt.IntegrityError, "versioned checkpoint"):
                await rt.checkpoint_run(
                    self.runtime,
                    key,
                    "running",
                    research_id,
                    request_hash,
                    state={},
                )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "failed_with_output",
                research_id,
                request_hash,
                error="no_progress",
                state=rt.run_state_snapshot(state),
            )
            resumed_id, _, resumed_cached, resumed_snapshot = await rt.reserve_run(
                self.runtime, request, key
            )
            self.assertEqual(resumed_id, research_id)
            self.assertIsNone(resumed_cached)
            self.assertIsNotNone(resumed_snapshot)

        asyncio.run(run())

    def test_checkpoint_version_rejects_missing_and_wrong_before_loading_state(self) -> None:
        snapshot = rt.run_state_snapshot(make_state(1, "quick"))
        self.assertEqual(snapshot["checkpoint_version"], 2)
        for version in (None, 1, 3):
            invalid = dict(snapshot)
            if version is None:
                invalid.pop("checkpoint_version")
            else:
                invalid["checkpoint_version"] = version
            invalid.pop("evidence_ledger")
            with (
                self.subTest(version=version),
                self.assertRaisesRegex(rt.IntegrityError, "unsupported checkpoint version"),
            ):
                rt.load_run_state(
                    invalid,
                    depth="quick",
                    budget=rt.make_budget("quick"),
                    wall_limit=rt.wall_budget_seconds("quick"),
                )
        loaded = rt.load_run_state(
            snapshot,
            depth="quick",
            budget=rt.make_budget("quick"),
            wall_limit=rt.wall_budget_seconds("quick"),
        )
        rt.validate_checkpoint_state(loaded, rt.ResearchRequest(query="Evidence", depth="quick"))

    def test_checkpoint_shape_nested_state_and_stats_are_strict(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.set_collection_decision(state, "coverage_complete")
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Section 1"),
            section(cited("Supported", "S1")),
        )
        state.candidate_queue = [
            rt.Candidate(
                url="https://candidate.example/1",
                title="candidate",
                snippet="snippet",
                engine="engine",
                search_query="query",
                purpose="purpose",
                requirement_id="R1",
            )
        ]
        state.failed_candidates = [
            rt.FailedCandidate("https://failed.example/1", "timeout", "fetch")
        ]
        state.searched_queries = {"q001"}
        valid = rt.run_state_snapshot(state)
        self.assertEqual(
            set(valid),
            {
                "checkpoint_version",
                "evidence_ledger",
                "searched_queries",
                "evidence_revision",
                "last_inspected_revision",
                "stats",
                "request_fragments",
                "requirements",
                "report_plan",
                "report_sections",
                "candidate_queue",
                "failed_candidates",
                "phase",
                "collection_decision",
            },
        )

        tampered_stats = json.loads(json.dumps(valid))
        tampered_stats["stats"].update(
            depth="quick",
            wall_limit_s=1.0,
            search_target=0,
            search_budget=0,
            evidence_budget=0,
            minimum_evidence=0,
            target_evidence=0,
            model_turn_budget=0,
            searches=0,
            documents=0,
            evidence=99,
            usable_evidence=99,
            evidence_revision=99,
            report_plan_sections=99,
            report_sections=99,
            report_chars=99,
            requirement_coverage={"tampered": {}},
        )
        loaded = rt.load_run_state(
            tampered_stats,
            depth="deep",
            budget=rt.make_budget("deep"),
            wall_limit=rt.wall_budget_seconds("deep"),
        )
        fresh = rt.default_stats("deep", rt.make_budget("deep"), rt.wall_budget_seconds("deep"))
        for key in (
            "depth",
            "wall_limit_s",
            "search_target",
            "search_budget",
            "evidence_budget",
            "minimum_evidence",
            "target_evidence",
            "model_turn_budget",
        ):
            self.assertEqual(loaded.stats[key], fresh[key])
        self.assertEqual(loaded.stats["evidence"], 1)
        self.assertEqual(loaded.stats["documents"], 1)
        self.assertEqual(loaded.stats["searches"], 1)
        self.assertEqual(loaded.stats["usable_evidence"], 1)
        self.assertEqual(loaded.stats["evidence_revision"], 1)
        self.assertEqual(loaded.stats["report_plan_sections"], 1)
        self.assertEqual(loaded.stats["report_sections"], 1)
        self.assertEqual(
            loaded.stats["report_chars"], len(rt.assemble_report_sections(loaded.report_sections))
        )
        self.assertEqual(
            loaded.stats["requirement_coverage"], rt.requirement_coverage_snapshot(loaded)
        )

        invalid: dict[str, dict[str, Any]] = {}
        item = json.loads(json.dumps(valid))
        item["query_seed_queue"] = []
        invalid["removed top-level field"] = item
        item = json.loads(json.dumps(valid))
        item.pop("request_fragments")
        invalid["missing top-level field"] = item
        item = json.loads(json.dumps(valid))
        item["report_plan"][0]["target_chars"] = 400
        invalid["old plan field"] = item
        item = json.loads(json.dumps(valid))
        item["report_plan"][0].pop("requirement_ids")
        invalid["missing plan field"] = item
        item = json.loads(json.dumps(valid))
        item["evidence_ledger"][0]["relevance"] = "high"
        invalid["evidence type"] = item
        item = json.loads(json.dumps(valid))
        item["evidence_ledger"][0]["url"] = "http://[bad"
        invalid["malformed mapped evidence URL"] = item
        item = json.loads(json.dumps(valid))
        candidate = item["candidate_queue"][0]
        candidate["requirement_ids"] = [candidate.pop("requirement_id")]
        invalid["old candidate shape"] = item
        item = json.loads(json.dumps(valid))
        item["failed_candidates"][0]["reason"] = "raw failure text"
        invalid["unsafe failed reason"] = item
        item = json.loads(json.dumps(valid))
        item["failed_candidates"][0]["stage"] = "download"
        invalid["invalid failed stage"] = item
        item = json.loads(json.dumps(valid))
        item["report_sections"][0]["ledger_revision"] = "1"
        invalid["report section type"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["requirements_calls"] = 99
        invalid["unknown stats field"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["report_plan_target_chars"] = 99
        invalid["deleted stats field"] = item
        item = json.loads(json.dumps(valid))
        item["stats"].pop("query_batch_calls")
        invalid["missing stats field"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["query_batch_calls"] = "oops"
        invalid["wrong stats type"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["searches"] = True
        invalid["bool stats counter"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["searches"] = -1
        invalid["negative stats counter"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["operation_failure_reasons"] = {"timeout": -1}
        invalid["negative stats reason count"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["model_transient_events"] = ["timeout"]
        invalid["invalid stats event"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["operation_failure_events"] = [
            {} for _ in range(rt.OPERATION_FAILURE_EVENT_LIMIT + 1)
        ]
        invalid["oversized stats events"] = item
        item = json.loads(json.dumps(valid))
        item["stats"]["fatal_error"] = []
        invalid["invalid stats dictionary"] = item
        for label, snapshot in invalid.items():
            with self.subTest(label=label), self.assertRaises(rt.IntegrityError):
                rt.load_run_state(
                    snapshot,
                    depth="deep",
                    budget=rt.make_budget("deep"),
                    wall_limit=rt.wall_budget_seconds("deep"),
                )

    def test_checkpoint_rejects_noncanonical_searched_queries(self) -> None:
        research = rt.ResearchRequest(query="Evidence", depth="quick")
        budget = rt.make_budget("quick")
        valid = rt.run_state_snapshot(make_state(0, "quick"))
        invalid = {
            "duplicate": ["same query", "same query"],
            "out of order": ["z query", "a query"],
            "blank": [""],
            "nonnormalized": [" padded query "],
        }
        for label, searched_queries in invalid.items():
            snapshot = json.loads(json.dumps(valid))
            snapshot["searched_queries"] = searched_queries
            with self.subTest(label=label), self.assertRaises(rt.IntegrityError):
                rt.load_run_state(
                    snapshot,
                    depth="quick",
                    budget=budget,
                    wall_limit=rt.wall_budget_seconds("quick"),
                )

        negative_revision = json.loads(json.dumps(valid))
        negative_revision["last_inspected_revision"] = -1
        loaded = rt.load_run_state(
            negative_revision,
            depth="quick",
            budget=budget,
            wall_limit=rt.wall_budget_seconds("quick"),
        )
        with self.assertRaises(rt.IntegrityError):
            rt.validate_checkpoint_state(loaded, research)

        over_budget = json.loads(json.dumps(valid))
        over_budget["searched_queries"] = [
            f"q{index:03d}" for index in range(budget.search_limit + 1)
        ]
        loaded = rt.load_run_state(
            over_budget,
            depth="quick",
            budget=budget,
            wall_limit=rt.wall_budget_seconds("quick"),
        )
        with self.assertRaises(rt.IntegrityError):
            rt.validate_checkpoint_state(loaded, research)

    def test_checkpoint_plan_must_match_request_owned_contract(self) -> None:
        research = rt.ResearchRequest(
            query="Need direct evidence",
            focus="compare vendors",
            depth="deep",
        )
        state = make_state(0)
        rt.store_initial_plan(state, research, deep_plan_for(research))
        valid = rt.run_state_snapshot(state)

        retry = make_state(0)
        retry.phase = "planning"
        retry.request_fragments = rt.explicit_request_fragments(research)
        loaded_retry = rt.load_run_state(
            rt.run_state_snapshot(retry),
            depth="deep",
            budget=rt.make_budget("deep"),
            wall_limit=rt.wall_budget_seconds("deep"),
        )
        rt.validate_checkpoint_state(loaded_retry, research)
        self.assertEqual(loaded_retry.request_fragments, retry.request_fragments)
        self.assertEqual(loaded_retry.requirements, [])
        self.assertEqual(loaded_retry.report_plan, [])

        invalid: dict[str, dict[str, Any]] = {}
        item = json.loads(json.dumps(valid))
        item["request_fragments"][0]["text"] = "Different request"
        invalid["request mismatch"] = item
        item = json.loads(json.dumps(valid))
        item["requirements"][1]["id"] = "R1"
        item["report_plan"][1]["requirement_ids"] = ["R1"]
        invalid["duplicate requirement ID"] = item
        item = json.loads(json.dumps(valid))
        item["requirements"][1]["fragment_ids"] = ["F1"]
        invalid["unmapped fragment"] = item
        item = json.loads(json.dumps(valid))
        item["report_plan"] = []
        invalid["requirements without plan"] = item
        item = json.loads(json.dumps(valid))
        item["requirements"] = []
        invalid["plan without requirements"] = item
        for label, snapshot in invalid.items():
            with self.subTest(label=label), self.assertRaises(rt.IntegrityError):
                loaded = rt.load_run_state(
                    snapshot,
                    depth="deep",
                    budget=rt.make_budget("deep"),
                    wall_limit=rt.wall_budget_seconds("deep"),
                )
                rt.validate_checkpoint_state(loaded, research)

        quick_research = rt.ResearchRequest(query="Evidence", depth="quick")
        nondeep = make_state(0, "quick")
        nondeep.request_fragments = rt.explicit_request_fragments(quick_research)
        with self.assertRaises(rt.IntegrityError):
            loaded = rt.load_run_state(
                rt.run_state_snapshot(nondeep),
                depth="quick",
                budget=rt.make_budget("quick"),
                wall_limit=rt.wall_budget_seconds("quick"),
            )
            rt.validate_checkpoint_state(loaded, quick_research)

    def test_checkpoint_rejects_candidate_urls_outside_runtime_invariants(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(0)
        rt.store_initial_plan(state, research, deep_plan_for(research))
        state.candidate_queue = [
            rt.Candidate(
                url="https://candidate.example/1",
                title="candidate",
                snippet="snippet",
                engine="engine",
                search_query="query",
                purpose="purpose",
                requirement_id="R1",
            )
        ]
        state.failed_candidates = [
            rt.FailedCandidate("https://failed.example/1", "timeout", "fetch")
        ]
        valid = rt.run_state_snapshot(state)
        rt.validate_checkpoint_state(state, research)

        for queue, url in (
            ("candidate_queue", "http://127.0.0.1/private"),
            ("candidate_queue", "https://candidate.example"),
            ("failed_candidates", "http://127.0.0.1/private"),
            ("failed_candidates", "https://failed.example"),
        ):
            snapshot = json.loads(json.dumps(valid))
            snapshot[queue][0]["url"] = url
            with self.subTest(queue=queue, url=url), self.assertRaises(rt.IntegrityError):
                loaded = rt.load_run_state(
                    snapshot,
                    depth="deep",
                    budget=rt.make_budget("deep"),
                    wall_limit=rt.wall_budget_seconds("deep"),
                )
                rt.validate_checkpoint_state(loaded, research)

    def test_summary_and_stats_cannot_change_mode_or_outcome(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.evidence[0] = replace(state.evidence[0], requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.set_collection_decision(state, "coverage_complete")
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Section 1"),
            section(cited("Body", "S1")),
        )
        state.report_sections[0] = replace(
            state.report_sections[0], summary="検証済み証拠台帳からの抽出要約"
        )
        state.stats["research_salvages"] = 99
        snapshot = rt.run_state_snapshot(state)
        loaded = rt.load_run_state(
            snapshot,
            depth="deep",
            budget=rt.make_budget("deep"),
            wall_limit=rt.wall_budget_seconds("deep"),
        )
        self.assertEqual(rt.finalize_report(loaded, research).outcome, "completed")
        loaded.report_sections[0] = replace(loaded.report_sections[0], mode="extractive")
        self.assertEqual(rt.finalize_report(loaded, research).outcome, "degraded")

    def test_relevance_refresh_and_prune_unusable_sections(self) -> None:
        table = "\n".join(f"試行{index}回 性能{300 + index}点" for index in range(12))
        state = make_state(2, "quick")
        state.evidence[0] = replace(state.evidence[0], excerpt=table, relevance=0, search_query="")
        self.assertTrue(
            rt.refresh_evidence_relevance(
                state, rt.ResearchRequest(query="性能 指標", depth="quick")
            )
        )
        state.evidence[1] = replace(
            state.evidence[1],
            relevance=0,
            excerpt="This unrelated document has enough text but no requested lexical term.",
        )
        state.report_sections = [
            rt.ReportSection(
                "Saved", "Claim [S1]", state.evidence_revision, "one", [], ["S1"], "structured"
            ),
            rt.ReportSection(
                "Unsafe", "Claim [S2]", state.evidence_revision, "two", [], ["S2"], "structured"
            ),
        ]
        self.assertTrue(rt.prune_unusable_report_sections(state))

    def test_per_requirement_independent_host_citation_validation(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        state = make_state(2)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="compare vendors", kind="comparison", fragment_ids=["F1"]
            )
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Comparison",
                requirement_ids=["R1"],
            )
        ]
        state.evidence[0] = replace(
            state.evidence[0], requirement_ids=["R1"], url="https://a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], requirement_ids=["R1"], url="https://b.example/2"
        )
        state.last_inspected_revision = state.evidence_revision
        contract = rt.build_section_contract(research, state, "Comparison")
        before = rt.run_state_snapshot(state)
        with self.assertRaisesRegex(rt.ModelOutputError, "requires a table"):
            rt.store_report_section(
                state,
                contract,
                section(cited("Free-text comparison", "S1", "S2")),
            )
        self.assertEqual(rt.run_state_snapshot(state), before)
        with self.assertRaisesRegex(rt.ModelOutputError, "independent hosts"):
            rt.store_report_section(
                state,
                contract,
                section(
                    cited("Comparison intro", "S1"),
                    tables=[
                        table(
                            ["Option", "Result"],
                            [table_row(["A", "Only one host"], "S1")],
                        )
                    ],
                ),
            )
        self.assertEqual(rt.run_state_snapshot(state), before)
        state.requirements = [state.requirements[0].model_copy(update={"kind": "benchmark"})]
        benchmark = rt.build_section_contract(research, state, "Comparison")
        self.assertFalse(benchmark.requires_comparison_table)
        rt.validate_section_draft(
            benchmark,
            section(cited("Benchmark prose", "S1", "S2")),
        )

    def test_checkpoint_rejects_invalid_section_mode_sources_and_revision(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        state = make_state(2)
        state.request_fragments = rt.explicit_request_fragments(research)
        state.requirements = [
            rt.RequirementModel(
                id="R1", summary="compare vendors", kind="comparison", fragment_ids=["F1"]
            )
        ]
        state.report_plan = [
            rt.PlanSection(
                heading="Comparison",
                requirement_ids=["R1"],
            )
        ]
        state.evidence[0] = replace(
            state.evidence[0], relevance=0.9, requirement_ids=["R1"], url="https://a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], relevance=0.9, requirement_ids=["R1"], url="https://b.example/2"
        )
        state.last_inspected_revision = state.evidence_revision
        rt.set_collection_decision(state, "coverage_complete")
        state.report_sections = [
            rt.ReportSection(
                "Comparison",
                "Comparison [S1] [S2]",
                state.evidence_revision,
                "summary",
                ["R1"],
                ["S1", "S2"],
                "structured",
            )
        ]
        valid = rt.run_state_snapshot(state)
        mutations = {
            "mode": {"mode": "invalid"},
            "source mismatch": {"source_ids": ["S1"]},
            "unknown source": {"body": "Comparison [S9]", "source_ids": ["S9"]},
            "stale revision": {"ledger_revision": state.evidence_revision - 1},
        }
        for label, update in mutations.items():
            snapshot = json.loads(json.dumps(valid))
            snapshot["report_sections"][0].update(update)
            loaded = rt.load_run_state(
                snapshot,
                depth="deep",
                budget=rt.make_budget("deep"),
                wall_limit=rt.wall_budget_seconds("deep"),
            )
            with self.subTest(label=label), self.assertRaises(rt.IntegrityError):
                rt.validate_checkpoint_state(loaded, research)
        unusable = json.loads(json.dumps(valid))
        unusable["evidence_ledger"][1]["relevance"] = 0
        with self.assertRaises(rt.IntegrityError):
            loaded = rt.load_run_state(
                unusable,
                depth="deep",
                budget=rt.make_budget("deep"),
                wall_limit=rt.wall_budget_seconds("deep"),
            )
            rt.validate_checkpoint_state(loaded, research)
        invalid_phase = rt.load_run_state(
            {**valid, "phase": "submission"},
            depth="deep",
            budget=rt.make_budget("deep"),
            wall_limit=rt.wall_budget_seconds("deep"),
        )
        with self.assertRaisesRegex(rt.IntegrityError, "phase"):
            rt.validate_checkpoint_state(invalid_phase, research)

    def test_deterministic_extractive_section_sets_mode_and_degraded_outcome(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; need another fact", depth="deep")
        state = make_state(1)
        fragments = rt.explicit_request_fragments(research)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(
            state.evidence[0],
            relevance=0.9,
            requirement_ids=["R1", "R2"],
            excerpt="Verified comparison | --- | --- | remains plain text.",
        )
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
                        summary="need another fact",
                        kind="direct",
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
            ),
        )
        rt.store_report_section(
            state,
            rt.build_section_contract(research, state, "Direct evidence"),
            section(cited("Supported claim", "S1")),
        )
        rt.set_collection_decision(state, "coverage_complete")
        rt._store_extractive_section(
            state, rt.build_section_contract(research, state, "Comparison")
        )
        response = rt.finalize_report(state, research)
        self.assertEqual(
            [item.mode for item in state.report_sections], ["structured", "extractive"]
        )
        self.assertEqual(response.outcome, "degraded")
        self.assertIn("Runtime extractive section", response.answer_markdown)
        self.assertNotIn("|", state.report_sections[-1].body)


if __name__ == "__main__":
    unittest.main(verbosity=2)
