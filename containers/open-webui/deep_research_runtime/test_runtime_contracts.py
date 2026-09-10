from __future__ import annotations

import asyncio
import json
from typing import cast
from unittest.mock import AsyncMock, patch

import aiohttp
from pydantic import ValidationError

import test_research_jobs as research_jobs
from test_research_jobs import (
    FakeProvider,
    assessment_json,
    completion,
    ledger_json,
    plan_json,
    request,
    selection_json,
    unit_markdown,
)
from test_support import FakeResponse, FakeSession, RuntimeTestCase, rt


def follow_up_queries(round_no: int) -> list[dict[str, object]]:
    return [
        {
            "query": f"follow up round {round_no} query {index}",
            "purpose": "resolve the essential evidence gap",
            "checklist_ids": ["C1"],
        }
        for index in range(1, 4)
    ]


def material_review(candidate: int, *, regenerate: bool) -> str:
    return json.dumps(
        {
            "patches": [
                {
                    "block_ids": [f"D:c{candidate}:r1:b002"],
                    "checklist_ids": ["C1"],
                    "ledger_ids": ["K-FACT"],
                    "source_ids": ["S1:P0-80"],
                    "reason": "The supported condition is material and remains misleading.",
                }
            ],
            "notes": [],
            "unsupported": [],
            "regenerate_reason": (
                "The essential synthesis remains misleading." if regenerate else None
            ),
        },
        separators=(",", ":"),
    )


class RuntimeContractTests(RuntimeTestCase):
    def test_physical_attempt_deadline_allows_provider_timeout(self) -> None:
        self.assertEqual(rt.JOB_ATTEMPT_SECONDS, 360)

    def test_stable_fragments_and_plan_require_every_clause_to_remain_essential(self) -> None:
        job_request = request(query="Identify evidence; compare alternatives. Explain uncertainty")
        fragments = rt.explicit_request_fragments(job_request)
        self.assertEqual([item.id for item in fragments], ["F1", "F2", "F3"])
        plan = rt.ResearchPlan.model_validate_json(plan_json())
        invalid = plan.model_copy(
            update={
                "checklist": [
                    plan.checklist[0].model_copy(
                        update={"fragment_ids": [item.id for item in fragments]}
                    )
                ]
            }
        )
        _, accepted = rt.validate_research_plan(job_request, invalid)
        self.assertEqual(accepted.checklist[0].fragment_ids, ["F1", "F2", "F3"])
        weakened = invalid.model_copy(
            update={"checklist": [invalid.checklist[0].model_copy(update={"essential": False})]}
        )
        with self.assertRaisesRegex(ValueError, "remain essential"):
            rt.validate_research_plan(job_request, weakened)

    def test_outline_rejects_missing_checklist_mapping_and_noncanonical_title(self) -> None:
        job_request = request()
        fragments, plan = rt.validate_research_plan(
            job_request, rt.ResearchPlan.model_validate_json(plan_json())
        )
        state = {
            "request_fragments": [item.model_dump() for item in fragments],
            "plan": plan.model_dump(),
            "assessment": json.loads(assessment_json("S1:P0-80")),
            "passages": [{"id": "S1:P0-80", "checklist_ids": ["C1"]}],
            "searched_queries": [],
        }
        ledger = rt.DecisionLedger.model_validate_json(ledger_json("S1:P0-80"))
        missing = ledger.model_copy(
            update={
                "outline": [
                    item.model_copy(update={"checklist_ids": ["C2"]}) for item in ledger.outline
                ]
            }
        )
        with self.assertRaisesRegex(ValueError, "map every checklist"):
            rt.validate_report_outline(missing, job_request, state)
        with self.assertRaisesRegex(ValueError, "title is not normalized"):
            rt.validate_report_outline(
                ledger.model_copy(update={"title": f" {ledger.title} "}),
                job_request,
                state,
            )

    def test_follow_up_query_count_is_zero_or_three_to_six(self) -> None:
        payload = json.loads(assessment_json("S1:P0-80"))
        payload["follow_up_queries"] = follow_up_queries(1)[:1]
        payload["stop_reason"] = None
        with self.assertRaises(ValidationError):
            rt.EvidenceAssessment.model_validate(payload)
        payload["follow_up_queries"] = follow_up_queries(1)
        value = rt.EvidenceAssessment.model_validate(payload)
        self.assertEqual(len(value.follow_up_queries), 3)
        with self.assertRaisesRegex(ValueError, "must be new"):
            rt.validate_evidence_assessment(
                value,
                rt.ResearchPlan.model_validate_json(plan_json()),
                {"S1:P0-80"},
                {value.follow_up_queries[0].query.upper()},
            )

    def test_adaptive_research_runs_at_most_four_rounds(self) -> None:
        async def run() -> None:
            outputs = [completion(plan_json())]
            for round_no in range(1, 5):
                outputs.append(completion(selection_json(f"W{round_no}-1")))
                if round_no < 4:
                    outputs.append(
                        completion(
                            assessment_json(
                                f"S{round_no}:P0-80",
                                status="unresolved",
                                limitation="More evidence is required.",
                                follow_ups=follow_up_queries(round_no),
                                stop_reason=None,
                            )
                        )
                    )
                else:
                    outputs.append(completion(assessment_json("S1:P0-80")))
            provider = FakeProvider(outputs)
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            self.assertTrue(await rt.claim_research_job(self.runtime, submitted["job_id"]))
            search_count = 0

            async def search(*_args: object, **_kwargs: object) -> list[rt.SearchResult]:
                nonlocal search_count
                search_count += 1
                return [
                    rt.SearchResult(
                        f"https://same.example/source-{search_count}",
                        f"Source {search_count}",
                        "Evidence",
                        "engine",
                    )
                ]

            async def fetch(result: rt.SearchResult) -> rt.FetchedSourceBlob:
                return rt.FetchedSourceBlob(
                    result.url,
                    result.url,
                    result.title,
                    "Publisher",
                    "text/plain",
                    result.url.encode(),
                )

            async def extract(source: rt.FetchedSourceBlob) -> rt.ExtractedSource:
                text = (source.raw_bytes.decode() + " supports the finding. " * 8)[:80]
                return rt.ExtractedSource(text, [{"page": 1, "start": 0, "end": len(text)}], [])

            with (
                patch.object(rt, "complete_research", new=provider),
                patch.object(rt, "search_searxng", new=search),
                patch.object(rt, "fetch_source_blob", new=fetch),
                patch.object(rt, "extract_source_blob", new=extract),
            ):
                state = await rt.run_job_research(self.runtime, submitted["job_id"], request())
            self.assertEqual(len(state["research_rounds"]), 4)
            self.assertEqual(len(state["searched_queries"]), 12)
            self.assertEqual(len(provider.bodies), 9)
            assessment_system = json.loads(provider.bodies[2])["messages"][0]["content"]
            for rule in (
                "qualified or unresolved items require a non-empty limitation",
                "new unique queries not already searched",
                "non-empty stop_reason whenever follow_up_queries is empty",
            ):
                self.assertIn(rule, assessment_system)

        asyncio.run(run())

    def test_research_failure_preserves_saved_evidence_gaps(self) -> None:
        async def run() -> None:
            provider = FakeProvider(
                [
                    completion(plan_json()),
                    completion(selection_json("W1-1")),
                    completion(
                        assessment_json(
                            "S1:P0-80",
                            status="unresolved",
                            limitation="A primary source is still missing.",
                            stop_reason="Further searches are unlikely to resolve the gap.",
                        )
                    ),
                ]
            )
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            fixture = research_jobs.ResearchJobTests()
            fixture.runtime = self.runtime
            contexts = fixture.patches(provider)
            with contexts[0], contexts[1], contexts[2], contexts[3]:
                await rt.execute_research_job(self.runtime, submitted["job_id"])
            status = await rt.research_job_status(self.runtime, "owner-1", submitted["job_id"])
            self.assertEqual(status["error_code"], "source_collection_failed")
            self.assertEqual(status["gaps"], ["C1: A primary source is still missing."])

        asyncio.run(run())

    def test_same_host_documents_are_admitted_and_content_is_deduplicated(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            first = await rt.store_source_blob(
                self.runtime,
                submitted["job_id"],
                rt.FetchedSourceBlob(
                    "https://same.example/a",
                    "https://same.example/a",
                    "A",
                    "Publisher",
                    "text/plain",
                    b"same content",
                ),
            )
            duplicate = await rt.store_source_blob(
                self.runtime,
                submitted["job_id"],
                rt.FetchedSourceBlob(
                    "https://same.example/b",
                    "https://same.example/b",
                    "B",
                    "Publisher",
                    "text/plain",
                    b"same content",
                ),
            )
            distinct = await rt.store_source_blob(
                self.runtime,
                submitted["job_id"],
                rt.FetchedSourceBlob(
                    "https://same.example/c",
                    "https://same.example/c",
                    "C",
                    "Publisher",
                    "text/plain",
                    b"different content",
                ),
            )
            self.assertEqual((first, duplicate, distinct), ("S1", "S1", "S2"))

        asyncio.run(run())

    def test_one_document_can_supply_distinct_checklist_passages(self) -> None:
        async def run() -> None:
            url = "https://example.com/rfc"
            round_value = {
                "results": [
                    {
                        "id": "W1-1",
                        "url": url,
                        "title": "Specification",
                        "snippet": "cache rules",
                        "engine": "engine",
                        "query": "cache rules",
                    }
                ],
                "fetches": [],
            }
            state = {
                "plan": {
                    "checklist": [
                        {"id": "C1", "question": "authorization shared cache permission"},
                        {"id": "C2", "question": "vary cache key matching"},
                    ]
                },
                "passages": [],
                "last_result": None,
            }
            paragraphs = (
                "Authorization shared cache permission public s-maxage " * 20
                + "\n"
                + "Vary cache key matching selected request header fields " * 20
            )
            source = rt.FetchedSourceBlob(
                url, url, "Specification", "Publisher", "text/plain", b"source"
            )
            extraction = rt.ExtractedSource(
                paragraphs,
                [{"page": 1, "start": 0, "end": len(paragraphs)}],
                [],
            )
            selection = rt.CandidateSelection.model_validate(
                {
                    "documents": [
                        {
                            "result_id": "W1-1",
                            "purpose": "collect normative cache evidence",
                            "checklist_ids": ["C1", "C2"],
                        }
                    ]
                }
            )
            with (
                patch.object(
                    rt,
                    "stored_source_blob",
                    new=AsyncMock(return_value=("S1", source)),
                ),
                patch.object(
                    rt,
                    "stored_extraction",
                    new=AsyncMock(return_value=(1, extraction)),
                ),
                patch.object(rt, "save_research_state", new=AsyncMock()),
            ):
                await rt.collect_selected_candidates(
                    self.runtime, "job", request(), state, round_value, selection
                )
            self.assertEqual(len(state["passages"]), 2)
            self.assertEqual(
                [item["checklist_ids"] for item in state["passages"]], [["C1"], ["C2"]]
            )

        asyncio.run(run())

    def test_stored_source_and_extraction_hashes_fail_closed(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            source = rt.FetchedSourceBlob(
                "https://example.com/source",
                "https://example.com/source",
                "Source",
                "Publisher",
                "text/plain",
                b"immutable bytes",
            )
            source_id = await rt.store_source_blob(self.runtime, job_id, source)
            await rt.store_source_extraction(
                self.runtime,
                job_id,
                source_id,
                rt.ExtractedSource(
                    "immutable extracted text",
                    [{"page": 1, "start": 0, "end": 24}],
                    [],
                ),
            )
            source_row = self.runtime.db.execute(
                "SELECT title, publisher, retrieved_at_ms FROM source_blobs "
                "WHERE job_id = ? AND source_id = ?",
                (job_id, source_id),
            ).fetchone()
            for column, statement, changed in (
                (
                    "title",
                    "UPDATE source_blobs SET title = ? WHERE job_id = ? AND source_id = ?",
                    "changed title",
                ),
                (
                    "publisher",
                    "UPDATE source_blobs SET publisher = ? WHERE job_id = ? AND source_id = ?",
                    "changed publisher",
                ),
                (
                    "retrieved_at_ms",
                    "UPDATE source_blobs SET retrieved_at_ms = ? "
                    "WHERE job_id = ? AND source_id = ?",
                    1,
                ),
            ):
                self.runtime.db.execute(statement, (changed, job_id, source_id))
                with self.subTest(column=column), self.assertRaises(rt.IntegrityError):
                    await rt.stored_source_blob(self.runtime, job_id, source.canonical_url)
                self.runtime.db.execute(statement, (source_row[column], job_id, source_id))
            self.runtime.db.execute(
                "UPDATE source_blobs SET raw_bytes = ? WHERE job_id = ? AND source_id = ?",
                (b"changed bytes", job_id, source_id),
            )
            with self.assertRaisesRegex(rt.IntegrityError, "stored source blob"):
                await rt.stored_source_blob(self.runtime, job_id, source.canonical_url)
            extraction = self.runtime.db.execute(
                "SELECT extractor_version, page_map_json, limitations_json "
                "FROM source_extractions WHERE job_id = ? AND source_id = ?",
                (job_id, source_id),
            ).fetchone()
            for column, statement, changed in (
                (
                    "extractor_version",
                    "UPDATE source_extractions SET extractor_version = ? "
                    "WHERE job_id = ? AND source_id = ?",
                    "mutated-version",
                ),
                (
                    "page_map_json",
                    "UPDATE source_extractions SET page_map_json = ? "
                    "WHERE job_id = ? AND source_id = ?",
                    '[{"page":999,"start":0,"end":24}]',
                ),
                (
                    "limitations_json",
                    "UPDATE source_extractions SET limitations_json = ? "
                    "WHERE job_id = ? AND source_id = ?",
                    '["mutated limitation"]',
                ),
            ):
                self.runtime.db.execute(statement, (changed, job_id, source_id))
                with self.subTest(column=column), self.assertRaises(rt.IntegrityError):
                    await rt.stored_extraction(self.runtime, job_id, source_id)
                self.runtime.db.execute(statement, (extraction[column], job_id, source_id))
            self.runtime.db.execute(
                "UPDATE source_extractions SET extracted_text = ? "
                "WHERE job_id = ? AND source_id = ?",
                ("changed text", job_id, source_id),
            )
            with self.assertRaisesRegex(rt.IntegrityError, "stored extraction"):
                await rt.stored_extraction(self.runtime, job_id, source_id)

        asyncio.run(run())

    def test_nonexplicit_short_unit_is_rejected_but_explicit_short_is_allowed(self) -> None:
        outline = rt.DecisionLedger.model_validate_json(ledger_json("S1:P0-80")).outline[0]
        short = "## Unit 1\n\nShort supported answer [S1:P0-80]"
        with self.assertRaisesRegex(ValueError, "shorter than 1200"):
            rt.validate_author_unit(request(), outline, short, {"S1:P0-80"})
        accepted = rt.validate_author_unit(
            request(query="Give a brief answer"), outline, short, {"S1:P0-80"}
        )
        self.assertEqual(accepted, short)

    def test_numeric_derivation_ignores_directive_assignment_as_arithmetic(self) -> None:
        rt.validate_numeric_derivations("Use s-maxage=60 as specified. [S1:P0-80]")
        with self.assertRaisesRegex(ValueError, "containing a digit"):
            rt.validate_numeric_derivations("The 2024 result is final.")
        with self.assertRaisesRegex(ValueError, "assumptions or sensitivity"):
            rt.validate_numeric_derivations("The result is 10 * 20 = 200. [S1:P0-80]")

    def test_repeated_filler_and_content_before_the_unit_heading_are_rejected(self) -> None:
        outline = rt.DecisionLedger.model_validate_json(ledger_json("S1:P0-80")).outline[0]
        repeated = "## Unit 1\n\n" + ("Repeated filler sentence. " * 100) + "[S1:P0-80]"
        with self.assertRaisesRegex(ValueError, "shorter than 1200"):
            rt.validate_author_unit(request(), outline, repeated, {"S1:P0-80"})
        with self.assertRaisesRegex(ValueError, "does not match"):
            rt.validate_author_unit(
                request(),
                outline,
                "Preamble that must not precede the unit.\n\n" + unit_markdown(1, "S1:P0-80"),
                {"S1:P0-80"},
            )

    def test_review_and_edit_receive_outline_and_finding_relevant_passages(self) -> None:
        plan = rt.ResearchPlan.model_validate_json(plan_json())
        ledger = rt.DecisionLedger.model_validate_json(ledger_json("S1:P0-80", "S2:P0-80"))
        markdown = unit_markdown(1, "S1:P0-80")
        blocks = rt.draft_blocks(markdown, 1, 1)
        passages = [
            {"id": f"S{index}:P0-80", "text": "evidence", "checklist_ids": ["C1"]}
            for index in range(1, 25)
        ]
        assessed = rt.selected_assessment_passages(plan, passages)
        self.assertEqual(len(assessed), 12)
        with self.assertRaisesRegex(ValueError, "passage references"):
            rt.validate_evidence_assessment(
                rt.EvidenceAssessment(
                    items=[
                        rt.ChecklistEvidence(
                            checklist_id="C1",
                            status="covered",
                            passage_ids=["S13:P0-80"],
                            origin="example.com",
                            authority="authoritative",
                        )
                    ],
                    stop_reason="Covered",
                ),
                plan,
                {item["id"] for item in assessed},
                set(),
            )
        reviewed = rt.relevant_review_passages(blocks, ledger, passages, markdown)
        self.assertEqual({item["id"] for item in reviewed}, {"S1:P0-80", "S2:P0-80"})
        findings = [
            {
                "id": "F001",
                "block_ids": [blocks[1].id],
                "source_ids": ["S2:P0-80"],
            }
        ]
        edited = rt.relevant_editor_passages(findings, blocks, passages)
        self.assertEqual({item["id"] for item in edited}, {"S1:P0-80", "S2:P0-80"})
        bounded = rt.bounded_prompt_text("証" * 4_000)
        self.assertLessEqual(len(bounded.encode()), rt.MAX_PROMPT_PASSAGE_BYTES)
        self.assertTrue(("証" * 4_000).startswith(bounded))
        self.assertEqual(rt.safe_job_error_code("provider_known_failed"), "provider_known_failed")
        self.assertEqual(rt.safe_job_error_code("provider_not_sent"), "provider_not_sent")
        with self.assertRaisesRegex(ValueError, "one admitted block"):
            rt.apply_editor_result(
                markdown,
                blocks,
                rt.EditResult(
                    base_revision=1,
                    replacements=[
                        rt.EditReplacement(
                            block_id=blocks[1].id,
                            finding_ids=["F001"],
                            markdown="Unsupported replacement [S3:P0-80]",
                        )
                    ],
                ),
                findings,
                {item["id"] for item in edited},
            )

    def test_stop_prevents_later_search_fetch_and_extraction_dispatch(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            state = await rt.load_research_state(self.runtime, job_id)
            provider = FakeProvider([completion(plan_json())])
            with patch.object(rt, "complete_research", new=provider):
                await rt.create_research_plan(self.runtime, job_id, request(), state)
            await rt.cancel_research_job(self.runtime, "owner-1", job_id)
            search = patch.object(rt, "search_searxng")
            with search as search_mock, self.assertRaises(asyncio.CancelledError):
                await rt.run_job_research(self.runtime, job_id, request())
            search_mock.assert_not_awaited()

            second = await rt.submit_research_job(
                self.runtime, "owner-1", request(action_id="cancel-fetch")
            )
            second_id = second["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, second_id))
            round_value = {
                "round": 1,
                "queries": [],
                "completed_queries": [],
                "results": [
                    {
                        "id": "W1-1",
                        "url": "https://example.com/one",
                        "title": "One",
                        "snippet": "Evidence",
                        "engine": "engine",
                        "query": "query",
                    },
                    {
                        "id": "W1-2",
                        "url": "https://example.com/two",
                        "title": "Two",
                        "snippet": "Evidence",
                        "engine": "engine",
                        "query": "query",
                    },
                ],
                "selection": None,
                "fetches": [],
                "assessment": None,
            }
            selection = rt.CandidateSelection.model_validate(
                {
                    "documents": [
                        {
                            "result_id": result_id,
                            "purpose": "evidence",
                            "checklist_ids": ["C1"],
                        }
                        for result_id in ("W1-1", "W1-2")
                    ]
                }
            )

            async def fetch(result: rt.SearchResult) -> rt.FetchedSourceBlob:
                await rt.cancel_research_job(self.runtime, "owner-1", second_id)
                return rt.FetchedSourceBlob(
                    result.url,
                    result.url,
                    result.title,
                    "example.com",
                    "text/plain",
                    b"source",
                )

            fetch_mock = AsyncMock(side_effect=fetch)
            extract = patch.object(rt, "extract_source_blob")
            with (
                patch.object(rt, "fetch_source_blob", new=fetch_mock),
                extract as extract_mock,
                self.assertRaises(asyncio.CancelledError),
            ):
                await rt.collect_selected_candidates(
                    self.runtime,
                    second_id,
                    request(action_id="cancel-fetch"),
                    rt.initial_research_state(),
                    round_value,
                    selection,
                )
            self.assertEqual(fetch_mock.call_count, 1)
            extract_mock.assert_not_awaited()

        asyncio.run(run())

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

    def test_material_edit_is_bounded_and_rechecked_before_publication(self) -> None:
        async def run() -> None:
            replacement = unit_markdown(1, "S1:P0-80", label="Edited").split("\n\n", 1)[1]
            outputs = [
                completion(plan_json()),
                completion(selection_json("W1-1")),
                completion(assessment_json("S1:P0-80")),
                completion(ledger_json("S1:P0-80")),
                completion(unit_markdown(1, "S1:P0-80")),
                completion(unit_markdown(2, "S1:P0-80")),
                completion(material_review(1, regenerate=False)),
                completion(
                    json.dumps(
                        {
                            "base_revision": 1,
                            "replacements": [
                                {
                                    "block_id": "D:c1:r1:b002",
                                    "finding_ids": ["F001"],
                                    "markdown": replacement,
                                }
                            ],
                            "dismissals": [],
                        },
                        separators=(",", ":"),
                    )
                ),
                completion('{"resolved":true,"reason":null}'),
            ]
            fixture = research_jobs.ResearchJobTests()
            fixture.runtime = self.runtime
            job_id, provider = await fixture.run_path(outputs)
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (result["status"], result["quality_outcome"]), ("completed", "publish")
            )
            self.assertIn("Edited", result["answer_markdown"])
            self.assertEqual(len(provider.bodies), 9)
            systems = [json.loads(body)["messages"][0]["content"] for body in provider.bodies]
            for assignment, phrase in (
                (0, "schema and semantic constraint"),
                (1, "document_slots"),
                (3, "schema and semantic constraint"),
                (4, "citation in a neighboring block does not count"),
                (6, "Every patch requires checklist and source IDs"),
                (7, "never both"),
                (8, "resolved=true only when every"),
            ):
                with self.subTest(assignment=assignment):
                    self.assertIn(phrase, systems[assignment])
            stages = self.runtime.db.execute(
                "SELECT stage FROM review_records WHERE job_id = ? ORDER BY id", (job_id,)
            ).fetchall()
            self.assertEqual([row["stage"] for row in stages], ["initial", "recheck"])

        asyncio.run(run())

    def test_restart_reuses_committed_author_unit(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            self.assertTrue(await rt.claim_research_job(self.runtime, submitted["job_id"]))
            setup_provider = FakeProvider(
                [
                    completion(plan_json()),
                    completion(selection_json("W1-1")),
                    completion(assessment_json("S1:P0-80")),
                    completion(ledger_json("S1:P0-80")),
                ]
            )
            fixture = research_jobs.ResearchJobTests()
            fixture.runtime = self.runtime
            contexts = fixture.patches(setup_provider)
            with contexts[0], contexts[1], contexts[2], contexts[3]:
                state = await rt.run_job_research(self.runtime, submitted["job_id"], request())
                await rt.set_candidate(self.runtime, submitted["job_id"], 1)
                _, ledger = await rt.create_report_outline(
                    self.runtime, submitted["job_id"], 1, request(), state, []
                )
            outline_request = json.loads(setup_provider.bodies[3])
            outline_contract = json.loads(outline_request["messages"][1]["content"])["contract"]
            self.assertIn("semantic_validation", outline_contract)
            self.assertIn("semantic constraint", outline_request["messages"][0]["content"].lower())

            unit = unit_markdown(1, "S1:P0-80")
            blocks = rt.draft_blocks(unit, 1, 1)
            outline = ledger.outline[0]
            await rt.insert_editorial_revision(
                self.runtime,
                submitted["job_id"],
                1,
                1,
                "raw_unit",
                unit_no=1,
                markdown=unit,
                data={
                    "unit": 1,
                    "heading": outline.heading,
                    "handoff": outline.handoff,
                    "checklist_ids": outline.checklist_ids,
                    "passage_ids": outline.passage_ids,
                    "substantive_chars": rt.substantive_character_count(unit),
                    "block_ids": [item.id.replace(":r1:", ":u1:") for item in blocks],
                    "lookup_block": {
                        "id": blocks[-1].id.replace(":r1:", ":u1:"),
                        "text": blocks[-1].text[:1200],
                    },
                },
                manifest=rt.block_manifest(blocks),
                next_phase="writing",
            )
            ledger = ledger.model_copy(
                update={
                    "outline": [
                        ledger.outline[0],
                        ledger.outline[1].model_copy(update={"passage_ids": ["S2:P0-80"]}),
                    ]
                }
            )
            resumed_provider = FakeProvider([completion(unit_markdown(2, "S2:P0-80"))])
            with (
                patch.object(rt, "complete_research", new=resumed_provider),
                patch.object(
                    rt,
                    "passage_workspace",
                    new=AsyncMock(
                        return_value=[
                            {
                                "id": "S2:P0-80",
                                "text": "admitted evidence",
                                "checklist_ids": ["C1"],
                                "origin": "example.com",
                                "authority": "authoritative",
                                "title": "Source 2",
                            }
                        ]
                    ),
                ),
            ):
                await rt.create_raw_candidate(
                    self.runtime,
                    submitted["job_id"],
                    1,
                    request(),
                    state,
                    ledger,
                    [],
                )
            self.assertEqual(len(resumed_provider.bodies), 1)
            resumed_body = resumed_provider.bodies[0].decode()
            self.assertNotIn("S1:P0-80", resumed_body)
            self.assertIn("S2:P0-80", resumed_body)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM editorial_revisions "
                    "WHERE job_id = ? AND kind = 'raw_unit'",
                    (submitted["job_id"],),
                ).fetchone()[0],
                2,
            )

        asyncio.run(run())

    def test_two_materially_poor_candidates_end_in_needs_review(self) -> None:
        async def run() -> None:
            outputs = [
                completion(plan_json()),
                completion(selection_json("W1-1")),
                completion(assessment_json("S1:P0-80")),
                completion(ledger_json("S1:P0-80")),
                completion(unit_markdown(1, "S1:P0-80", label="First")),
                completion(unit_markdown(2, "S1:P0-80", label="First")),
                completion(material_review(1, regenerate=True)),
                completion(ledger_json("S1:P0-80")),
                completion(unit_markdown(1, "S1:P0-80", label="Second")),
                completion(unit_markdown(2, "S1:P0-80", label="Second")),
                completion(material_review(2, regenerate=True)),
            ]
            fixture = research_jobs.ResearchJobTests()
            fixture.runtime = self.runtime
            job_id, provider = await fixture.run_path(outputs)
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (status["status"], status["delivery_status"]),
                ("incomplete", "needs_review"),
            )
            job = await rt.load_job(self.runtime, job_id)
            self.assertEqual(
                (status["error_code"], job["quality_outcome"]),
                ("material_findings_remain", "retryable_quality_failure"),
            )
            self.assertEqual(len(provider.bodies), 11)
            ledgers = self.runtime.db.execute(
                "SELECT candidate_no FROM editorial_revisions "
                "WHERE job_id = ? AND kind = 'ledger' ORDER BY candidate_no",
                (job_id,),
            ).fetchall()
            self.assertEqual([row["candidate_no"] for row in ledgers], [1, 2])
            second_ledger_prompt = json.loads(
                json.loads(provider.bodies[7])["messages"][1]["content"]
            )
            self.assertTrue(second_ledger_prompt["prior_candidate_failure_feedback"])
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM publications WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                0,
            )

        asyncio.run(run())

    def test_numeric_derivation_requires_citation_and_assumptions(self) -> None:
        with self.assertRaisesRegex(ValueError, "citation"):
            rt.validate_numeric_derivations("## Result\n\nThe measured value is 12.")
        with self.assertRaisesRegex(ValueError, "assumptions"):
            rt.validate_numeric_derivations(
                "## Result\n\nThe estimate = 12 based on inputs [S1:P0-80]."
            )
        rt.validate_numeric_derivations(
            "## Result\n\nUnder the stated assumption, the estimate = 12 with a range "
            "of outcomes [S1:P0-80]."
        )

    def test_review_schema_requires_material_checklist_and_source_references(self) -> None:
        ledger = rt.DecisionLedger.model_validate_json(ledger_json("S1:P0-80"))
        blocks = rt.draft_blocks(unit_markdown(1, "S1:P0-80"), 1, 1)
        invalid = rt.ReviewResult(
            patches=[rt.ReviewItem(block_ids=[blocks[1].id], reason="Material consequence")]
        )
        with self.assertRaisesRegex(ValueError, "checklist and source"):
            rt.validate_review_result(
                invalid, blocks, ledger, [{"id": "S1:P0-80", "text": "evidence"}]
            )
        with self.assertRaisesRegex(ValueError, "base revision is stale"):
            rt.apply_editor_result(
                unit_markdown(1, "S1:P0-80"),
                blocks,
                rt.EditResult(base_revision=2),
                [],
                {"S1:P0-80"},
            )

    def test_only_evidence_caveats_change_the_publication_outcome(self) -> None:
        async def run() -> None:
            fixture = research_jobs.ResearchJobTests()
            fixture.runtime = self.runtime
            for action_id, public_caveat, expected in (
                ("style-note", False, "publish"),
                ("evidence-note", True, "publish_with_caveats"),
            ):
                reason = f"{action_id} explanation"
                note_review = json.dumps(
                    {
                        "patches": [],
                        "notes": [
                            {
                                "block_ids": ["D:c1:r1:b002"],
                                "checklist_ids": ["C1"],
                                "ledger_ids": ["K-FACT"],
                                "source_ids": ["S1:P0-80"],
                                "reason": reason,
                                "public_caveat": public_caveat,
                            }
                        ],
                        "unsupported": [],
                        "regenerate_reason": None,
                    },
                    separators=(",", ":"),
                )
                outputs = [
                    *research_jobs.research_outputs(),
                    completion(ledger_json("S1:P0-80")),
                    completion(unit_markdown(1, "S1:P0-80")),
                    completion(unit_markdown(2, "S1:P0-80")),
                    completion(note_review),
                ]
                job_id, _provider = await fixture.run_path(outputs, request(action_id=action_id))
                _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
                self.assertEqual(result["quality_outcome"], expected)
                self.assertEqual(reason in result["answer_markdown"], public_caveat)

        asyncio.run(run())

    def test_publication_labels_reserve_localized_headings_and_honor_explicit_language(
        self,
    ) -> None:
        plan = rt.ResearchPlan.model_validate_json(plan_json(language="ja"))
        self.assertEqual(
            rt.publication_labels(request(query="公開情報を調査してください"), plan),
            ("限界", "情報源", "なし", "取得日"),
        )
        self.assertEqual(
            rt.publication_labels(request(query="公開情報を調査してください", language="en"), plan),
            ("Limitations", "Sources", "None", "retrieved"),
        )
        for heading in ("情報源", "来源", "Quellen", "Fuentes", "출처"):
            with self.subTest(heading=heading), self.assertRaisesRegex(ValueError, "reserved"):
                rt.validated_report_heading(heading)


if __name__ == "__main__":
    import unittest

    unittest.main(verbosity=2)
