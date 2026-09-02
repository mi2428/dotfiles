from __future__ import annotations

import asyncio
import os
import unittest
from dataclasses import replace
from typing import cast
from unittest.mock import AsyncMock, patch

import aiohttp
import httpx
from openai import APIStatusError
from strands.agent.conversation_manager import SlidingWindowConversationManager
from strands.tools.executors import SequentialToolExecutor

from test_support import FakeResponse, FakeSession, RuntimeTestCase, make_state, rt


def deep_plan_for(research: rt.ResearchRequest) -> rt.InitialPlanDraft:
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
        rt.InitialPlanSection(
            heading=f"Section {index}",
            target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
            requirement_ids=[requirement.id],
            deliverables=[requirement.summary],
        )
        for index, requirement in enumerate(requirements, 1)
    ]
    return rt.InitialPlanDraft(
        fragments=fragments,
        requirements=requirements,
        sections=sections,
        query_seeds=[],
    )


class RuntimeContractTests(RuntimeTestCase):
    def test_openapi_auth_and_cached_markdown(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                self.assertEqual(
                    (await client.post("/research", json={"query": "x"})).status_code, 401
                )
                cached = rt.ResearchResponse(
                    research_id="rid",
                    answer_markdown="done [S1]",
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
                        "/research",
                        headers={"Authorization": "Bearer test-api-key"},
                        json={"query": "cached"},
                    )
                self.assertEqual(response.text, "done [S1]")
                self.assertEqual(response.headers["x-openwebui-direct-output"], "true")

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

    def test_target_evidence_environment_override_stays_between_minimum_and_cap(self) -> None:
        with patch.dict(
            os.environ,
            {
                "DEEP_RESEARCH_TARGET_EVIDENCE_DEEP": "25",
                "DEEP_RESEARCH_EVIDENCE_TARGET_DEEP": "40",
            },
        ):
            self.assertEqual(rt.make_budget("deep").target_evidence, 25)
        for invalid in (19, 61):
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
            response = rt.ResearchResponse(
                research_id=research_id,
                answer_markdown="done [S1]",
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
            )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "completed",
                research_id,
                request_hash,
                response=response.model_dump(),
            )
            with self.assertRaises(rt.HTTPException):
                await rt.reserve_run(
                    self.runtime,
                    rt.ResearchRequest(query="different", depth="quick"),
                    key,
                )
            self.runtime.db.execute(
                "UPDATE research_runs SET response_json='{}' WHERE idempotency_key=?",
                (key,),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
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

    def test_structured_timeout_keeps_provider_240s_inside_existing_envelope(self) -> None:
        self.assertEqual(rt.structured_role_timeout_seconds(self.runtime.settings, 1800), 1500)
        self.assertGreater(rt.structured_role_timeout_seconds(self.runtime.settings, 1800), 240)
        self.assertEqual(rt.structured_role_timeout_seconds(self.runtime.settings, 300), 300)

    def test_kimi_adapter_and_shared_agent_retry_contracts(self) -> None:
        standard = rt.ResearchRequest(query="standard coverage", depth="standard")
        agent = rt.build_research_agent(self.runtime.settings, standard, [])
        model = cast(rt.SakuraKimiModel, agent.model)
        manager = cast(SlidingWindowConversationManager, agent.conversation_manager)
        self.assertEqual(model.client_args["timeout"], 1800)
        self.assertEqual(model.client_args["max_retries"], 0)
        self.assertIsInstance(manager, SlidingWindowConversationManager)
        self.assertIsInstance(agent.tool_executor, SequentialToolExecutor)
        self.assertEqual(manager.window_size, 30)

        request = httpx.Request("POST", "http://llm.local/v1/chat/completions")
        response = httpx.Response(503, request=request)
        wrapped = rt.EventLoopException(
            APIStatusError("provider error", response=response, body={})
        )
        self.assertEqual(rt.model_retry_delay(wrapped, 0), 2)
        self.assertTrue(rt.is_expected_provider_failure(wrapped))

    def test_validated_requirements_plan_maps_every_explicit_fragment(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence; compare vendors", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        draft = deep_plan_for(research)
        fragments, requirements, sections, query_seeds = rt.validated_initial_plan(research, draft)
        self.assertEqual("".join(item.text for item in fragments), research.query)
        self.assertEqual(
            {fragment_id for item in requirements for fragment_id in item.fragment_ids},
            {item.id for item in fragments},
        )
        self.assertEqual([item.requirement_ids for item in sections], [["R1"]])
        self.assertEqual(query_seeds, [])

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

    def test_deep_submit_allows_short_complete_report_and_rejects_missing_requirements(
        self,
    ) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.store_report_section(
            state,
            research,
            state.evidence_revision,
            "Section 1",
            ["R1"],
            "Supported claim [S1]",
            "summary",
        )
        response = rt.validate_submit_report(
            "rid",
            state,
            state.evidence_revision,
            rt.assemble_report_sections(state.report_sections),
            [{"claim": "Claim", "source_ids": ["S1"]}],
            ["Known constraint"],
            rt.make_budget("deep"),
            "deep",
            research.query,
        )
        self.assertIn("## Sources", response.answer_markdown)
        broken = replace(state, report_sections=[])
        with self.assertRaisesRegex((ValueError, rt.IntegrityError), "requirement"):
            rt.validate_submit_report(
                "rid",
                broken,
                state.evidence_revision,
                "## Section 1\n\nUnsupported [S1]",
                [{"claim": "claim", "source_ids": ["S1"]}],
                ["Known constraint"],
                rt.make_budget("deep"),
                "deep",
                research.query,
            )

    def test_next_report_action_does_not_char_repair_successful_sections(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        state = make_state(1)
        state.last_inspected_revision = state.evidence_revision
        state.evidence[0] = replace(state.evidence[0], relevance=0.9, requirement_ids=["R1"])
        rt.store_initial_plan(state, research, deep_plan_for(research))
        rt.store_report_section(
            state,
            research,
            state.evidence_revision,
            "Section 1",
            ["R1"],
            "Short but cited [S1]",
            "summary",
        )
        self.assertEqual(rt.next_report_action(state, research)[0], "submit")

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
            rt.ReportPlanSection(
                heading="Section 1",
                target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                requirement_ids=["R1"],
                source_ids=[],
                deliverables=["Need direct evidence"],
            )
        ]
        state.report_sections = [
            rt.ReportSection("Done", "Claim [S1]", state.evidence_revision, "summary", ["R1"])
        ]
        state.candidate_queue = [
            rt.Candidate(
                url="https://other.example/4",
                title="Other",
                snippet="noise",
                engine="engine",
                search_query="noise",
                purpose="noise",
                requirement_ids=["R1"],
            )
        ]
        query_payload = rt.build_query_context(research, state)
        section_payload = rt.build_section_context(
            research,
            state,
            "missing_plan_section",
            "Section 1",
        )
        submission_payload = rt.build_submission_context(research, state)
        self.assertNotIn("evidence", query_payload)
        self.assertNotIn("candidate_queue", query_payload)
        self.assertEqual(len(section_payload["assigned_evidence"]), 3)
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
        self.assertEqual([item["id"] for item in submission_payload["evidence"]], ["S1"])

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

    def test_invalid_query_seeds_are_rejected_at_plan_validation(self) -> None:
        research = rt.ResearchRequest(query="Need direct evidence", depth="deep")
        fragments = rt.explicit_request_fragments(research)
        draft = rt.InitialPlanDraft(
            fragments=fragments,
            requirements=[
                rt.RequirementModel(
                    id="R1",
                    summary="Need direct evidence",
                    kind="direct",
                    fragment_ids=[fragments[0].id],
                ),
                rt.RequirementModel(
                    id="R2",
                    summary="Need direct evidence followup",
                    kind="direct",
                    fragment_ids=[fragments[0].id],
                ),
            ],
            sections=[
                rt.InitialPlanSection(
                    heading="Section 1",
                    target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                    requirement_ids=["R1", "R2"],
                    deliverables=["Need direct evidence"],
                )
            ],
            query_seeds=[
                rt.QuerySeedModel(
                    query="seed",
                    purpose="bad",
                    requirement_ids=["R1", "R2"],
                )
            ],
        )
        with self.assertRaisesRegex(ValueError, "exactly one requirement"):
            rt.validated_initial_plan(research, draft)

    def test_compare_fragment_kind_is_upgraded_by_runtime(self) -> None:
        research = rt.ResearchRequest(query="compare vendors", depth="deep")
        fragments = rt.explicit_request_fragments(research)
        draft = rt.InitialPlanDraft(
            fragments=fragments,
            requirements=[
                rt.RequirementModel(
                    id="R1",
                    summary="compare vendors",
                    kind="direct",
                    fragment_ids=[fragments[0].id],
                )
            ],
            sections=[
                rt.InitialPlanSection(
                    heading="Comparison",
                    target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                    requirement_ids=["R1"],
                    deliverables=["compare vendors"],
                )
            ],
            query_seeds=[],
        )
        _fragments, requirements, _sections, _query_seeds = rt.validated_initial_plan(
            research, draft
        )
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
            rt.ReportPlanSection(
                heading="Compare",
                target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                requirement_ids=["R2"],
                source_ids=[],
                deliverables=["compare vendors"],
            )
        ]
        context = rt.build_section_context(research, state, "missing_plan_section", "Compare")
        self.assertEqual(context["coverage_gaps"][0]["required_hosts"], 2)
        prompt = rt.build_section_prompt(
            research, state, "missing_plan_section", repair_heading="Compare"
        )
        self.assertIn("unsupported claims", prompt)
        self.assertIn("assigned_evidence", prompt)

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
                research,
                state.evidence_revision,
                "Section 1",
                ["R1"],
                "Bad citation [S9]",
                "summary",
            )
        corrupt = rt.run_state_snapshot(state)
        corrupt["report_sections"] = [
            {
                "heading": "Section 1",
                "body": "Bad citation [S9]",
                "ledger_revision": state.evidence_revision,
                "summary": "summary",
                "requirement_ids": ["R1"],
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
            rt.ReportSection("Saved", "Claim [S1]", state.evidence_revision),
            rt.ReportSection("Unsafe", "Claim [S2]", state.evidence_revision),
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
            rt.ReportPlanSection(
                heading="Comparison",
                target_chars=rt.DEEP_PLAN_MIN_SECTION_CHARS,
                requirement_ids=["R1"],
                source_ids=["S1", "S2"],
                deliverables=["compare vendors"],
            )
        ]
        state.evidence[0] = replace(
            state.evidence[0], requirement_ids=["R1"], url="https://a.example/1"
        )
        state.evidence[1] = replace(
            state.evidence[1], requirement_ids=["R1"], url="https://b.example/2"
        )
        state.last_inspected_revision = state.evidence_revision
        with self.assertRaisesRegex(rt.ModelOutputError, "independent hosts"):
            rt.store_report_section(
                state,
                research,
                state.evidence_revision,
                "Comparison",
                ["R1"],
                "Only one host cited [S1]",
                "summary",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
