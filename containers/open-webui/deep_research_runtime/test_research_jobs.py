from __future__ import annotations

import asyncio
import json
import time
import unittest
from typing import Any, Literal
from unittest.mock import AsyncMock, patch

import httpx

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


def completion(
    content: str,
    state: Literal["not_sent", "succeeded", "known_failed", "unknown"] = "succeeded",
) -> ResearchCompletion:
    return ResearchCompletion(
        content if state == "succeeded" else "",
        AttemptOutcome(state, 200 if state != "unknown" else None, "stop", 10, 10, 20, 100),
    )


def request(action_id: str = "action-1", **changes: Any) -> rt.ResearchJobRequest:
    return rt.ResearchJobRequest(
        action_id=action_id,
        query="Need a source-grounded answer",
        depth="deep",
        **changes,
    )


def ledger_json(units: int = 1, *, context: bool = False) -> str:
    return json.dumps(
        {
            "entries": [
                {
                    "id": "K-FACT",
                    "statement": "The primary finding must retain its measured condition.",
                    "metric": "finding",
                    "unit": "text",
                    "comparator": "source",
                    "direction": "match",
                    "mode_stage": "report",
                    "condition": "public evidence",
                    "kind": "source_fact",
                    "reference_ids": ["S1:P0-80"],
                    "conflict_status": "none",
                }
            ],
            "outline": [
                {
                    "unit": unit,
                    "heading": f"Unit {unit}",
                    "purpose": f"Write bounded unit {unit}",
                    "ledger_ids": ["K-FACT"],
                    "passage_ids": ["S1:P0-80"],
                    "context_units": [1] if context and unit == 2 else [],
                    "handoff": f"Carry the finding through unit {unit}",
                }
                for unit in range(1, units + 1)
            ],
        },
        separators=(",", ":"),
    )


def research_outputs() -> list[ResearchCompletion]:
    return [
        completion('{"action":"search","query":"primary evidence"}'),
        completion('{"action":"fetch","url":"https://example.com/source","purpose":"verify"}'),
        completion('{"action":"read","source_id":"S1","start":0,"end":80}'),
        completion(
            '{"action":"finish","findings":[{"text":"Supported finding",'
            '"passage_ids":["S1:P0-80"]}],"gaps":[]}'
        ),
    ]


class FakeProvider:
    def __init__(self, outputs: list[ResearchCompletion]) -> None:
        self.outputs = list(outputs)
        self.bodies: list[bytes] = []
        self.leases: list[Any] = []

    async def __call__(
        self, _base_url: str, _api_key: str, body: bytes, lease: Any
    ) -> ResearchCompletion:
        self.bodies.append(body)
        self.leases.append(lease)
        if not self.outputs:
            raise AssertionError("unexpected provider call")
        return self.outputs.pop(0)


class ResearchJobTests(RuntimeTestCase):
    def patches(self, provider: FakeProvider) -> tuple[Any, ...]:
        source_text = "Evidence supports the measured finding and its condition. " * 5
        return (
            patch.object(rt, "complete_research", new=provider),
            patch.object(
                rt,
                "search_searxng",
                new=AsyncMock(
                    return_value=[
                        rt.SearchResult(
                            "https://example.com/source",
                            "Primary Source",
                            "Evidence",
                            "engine",
                        )
                    ]
                ),
            ),
            patch.object(
                rt,
                "fetch_source_blob",
                new=AsyncMock(
                    return_value=rt.FetchedSourceBlob(
                        "https://example.com/source",
                        "https://example.com/source",
                        "Primary Source",
                        "Publisher",
                        "text/html",
                        b"complete raw source",
                    )
                ),
            ),
            patch.object(
                rt,
                "extract_source_blob",
                new=AsyncMock(
                    return_value=rt.ExtractedSource(
                        source_text,
                        [{"page": 1, "start": 0, "end": len(source_text)}],
                        [],
                    )
                ),
            ),
        )

    async def run_path(
        self, outputs: list[ResearchCompletion], job_request: rt.ResearchJobRequest | None = None
    ) -> tuple[str, FakeProvider]:
        submitted = await rt.submit_research_job(self.runtime, "owner-1", job_request or request())
        provider = FakeProvider(outputs)
        contexts = self.patches(provider)
        with contexts[0], contexts[1], contexts[2], contexts[3]:
            await rt.execute_research_job(self.runtime, submitted["job_id"])
        return str(submitted["job_id"]), provider

    def test_public_api_requires_auth_owner_and_action_and_attaches(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            auth = {"Authorization": "Bearer test-api-key", "X-Research-Owner": "owner-1"}
            body = request().model_dump()
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                self.assertEqual(
                    (
                        await client.post(
                            "/research/jobs", headers={"X-Research-Owner": "o"}, json=body
                        )
                    ).status_code,
                    401,
                )
                self.assertEqual(
                    (
                        await client.post(
                            "/research/jobs",
                            headers={"Authorization": "Bearer test-api-key"},
                            json=body,
                        )
                    ).status_code,
                    422,
                )
                first = await client.post("/research/jobs", headers=auth, json=body)
                attached = await client.post("/research/jobs", headers=auth, json=body)
                self.assertEqual((first.status_code, attached.status_code), (202, 202))
                self.assertEqual(first.json()["job_id"], attached.json()["job_id"])
                changed = await client.post(
                    "/research/jobs", headers=auth, json={**body, "query": "changed"}
                )
                self.assertEqual(changed.status_code, 409)
                job_id = first.json()["job_id"]
                self.assertEqual(
                    (
                        await client.get(
                            f"/research/jobs/{job_id}",
                            headers={**auth, "X-Research-Owner": "owner-2"},
                        )
                    ).status_code,
                    404,
                )
                self.assertEqual(
                    (await client.post("/research", headers=auth, json={})).status_code, 404
                )
                schema = (await client.get("/openapi.json")).json()
                self.assertNotIn("/research", schema["paths"])
                self.assertFalse(any(path.startswith("/research/jobs") for path in schema["paths"]))
                with patch.object(
                    rt,
                    "complete_research",
                    new=AsyncMock(side_effect=AssertionError("read dispatched")),
                ):
                    status_response = await client.get(f"/research/jobs/{job_id}", headers=auth)
                    result_response = await client.get(
                        f"/research/jobs/{job_id}/result", headers=auth
                    )
                self.assertEqual(status_response.status_code, 200)
                self.assertEqual(result_response.status_code, 202)

        asyncio.run(run())

    def test_status_and_result_expose_only_fixed_safe_error_codes(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'failed', error_code = ? WHERE job_id = ?",
                ("private exception text", job_id),
            )
            self.runtime.db.commit()
            status_payload = await rt.research_job_status(self.runtime, "owner-1", job_id)
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(status_payload["error_code"], "internal_error")
            self.assertEqual(result["error_code"], "internal_error")

        asyncio.run(run())

    def test_model_json_boundary_does_not_weaken_integrity_errors(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            with (
                patch.object(
                    rt,
                    "invoke_job_model",
                    new=AsyncMock(side_effect=rt.IntegrityError("receipt corrupt")),
                ),
                self.assertRaises(rt.IntegrityError),
            ):
                await rt.run_job_research(self.runtime, submitted["job_id"], request())

        asyncio.run(run())

    def test_all_saved_editorial_record_parts_are_verified_before_reuse(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            unit = "## Unit 1\n\nUnit evidence [S1:P0-80]"
            raw = "## Unit 1\n\nRaw evidence [S1:P0-80]"
            edited = "## Unit 1\n\nEdited evidence [S1:P0-80]"
            await rt.insert_editorial_revision(
                self.runtime,
                job_id,
                1,
                1,
                "raw_unit",
                unit_no=1,
                markdown=unit,
                data={"unit": 1},
                manifest=rt.block_manifest(rt.draft_blocks(unit, 1, 1)),
                next_phase="writing",
            )
            await rt.insert_editorial_revision(
                self.runtime,
                job_id,
                1,
                1,
                "raw",
                markdown=raw,
                manifest=rt.block_manifest(rt.draft_blocks(raw, 1, 1)),
                next_phase="supervising",
            )
            await rt.insert_editorial_revision(
                self.runtime,
                job_id,
                1,
                2,
                "edited",
                markdown=edited,
                data={"dismissals": [], "changed_ordinals": [2]},
                manifest=rt.block_manifest(rt.draft_blocks(edited, 1, 2)),
                next_phase="supervising",
            )
            for kind, unit_no, column, value in (
                ("raw_unit", 1, "data_json", "{}"),
                ("raw", 0, "manifest_json", "[]"),
                ("edited", 0, "data_json", "{}"),
            ):
                with self.subTest(kind=kind, column=column):
                    self.runtime.db.execute(
                        f"UPDATE editorial_revisions SET {column} = ? "
                        "WHERE job_id = ? AND candidate_no = 1 AND kind = ? AND unit_no = ?",
                        (value, job_id, kind, unit_no),
                    )
                    self.runtime.db.commit()
                    with self.assertRaises(rt.IntegrityError):
                        await rt.editorial_revision(self.runtime, job_id, 1, kind, unit_no=unit_no)

        asyncio.run(run())

    def test_full_single_author_path_persists_source_raw_and_publication(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nSupported finding [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
            ]
            job_id, provider = await self.run_path(outputs)
            status_payload = await rt.research_job_status(self.runtime, "owner-1", job_id)
            code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (code, status_payload["status"], result["candidate"]), (200, "completed", 1)
            )
            self.assertEqual(len(provider.bodies), 7)
            first_prompt = json.loads(json.loads(provider.bodies[0])["messages"][1]["content"])
            self.assertEqual(
                first_prompt["limits"],
                {
                    "attempts_remaining": 18,
                    "editorial_attempt_reserve": 6,
                    "research_actions_remaining": 12,
                    "read_chars": rt.MAX_READ_CHARS,
                },
            )
            blob = self.runtime.db.execute(
                "SELECT raw_bytes FROM source_blobs WHERE job_id = ?", (job_id,)
            ).fetchone()
            extraction = self.runtime.db.execute(
                "SELECT extracted_text FROM source_extractions WHERE job_id = ?", (job_id,)
            ).fetchone()
            raw = self.runtime.db.execute(
                "SELECT markdown FROM editorial_revisions WHERE job_id = ? AND kind = 'raw'",
                (job_id,),
            ).fetchone()
            self.assertEqual(blob["raw_bytes"], b"complete raw source")
            self.assertGreater(len(extraction["extracted_text"]), 80)
            self.assertNotEqual(raw["markdown"], result["answer_markdown"])
            self.assertIn("## Sources", result["answer_markdown"])
            assignments = self.runtime.db.execute(
                "SELECT assignment_key FROM research_attempts WHERE job_id = ?", (job_id,)
            ).fetchall()
            self.assertEqual(len(assignments), len({row["assignment_key"] for row in assignments}))

        asyncio.run(run())

    def test_recoverable_action_error_is_feedback_not_a_terminal_job_error(self) -> None:
        async def run() -> None:
            outputs = [
                completion('{"action":"search","query":"primary evidence"}'),
                completion('{"action":"read","source_id":"S1","start":0,"end":80}'),
                *research_outputs()[1:],
                completion(ledger_json()),
                completion("## Unit 1\n\nSupported finding [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
            ]
            job_id, provider = await self.run_path(outputs)
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(status["status"], "completed")
            prompt_after_error = json.loads(
                json.loads(provider.bodies[2])["messages"][1]["content"]
            )
            self.assertEqual(
                prompt_after_error["last_result"],
                {"action": "read", "error": "source_not_found"},
            )

        asyncio.run(run())

    def test_search_obeys_absolute_job_deadline_and_research_preserves_editorial_reserve(
        self,
    ) -> None:
        async def slow_search(*_args: Any, **_kwargs: Any) -> list[Any]:
            await asyncio.sleep(1)
            return []

        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            self.runtime.db.execute(
                "UPDATE research_jobs SET deadline_at_ms = ? WHERE job_id = ?",
                (rt.unix_ms() + 5_020, job_id),
            )
            self.runtime.db.commit()
            provider = FakeProvider([completion('{"action":"search","query":"primary evidence"}')])
            started = time.monotonic()
            with (
                patch.object(rt, "complete_research", new=provider),
                patch.object(rt, "search_searxng", new=slow_search),
            ):
                await rt.execute_research_job(self.runtime, job_id)
            self.assertLess(time.monotonic() - started, 0.5)
            row = self.runtime.db.execute(
                "SELECT status, error_code, quality_outcome FROM research_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            self.assertEqual(
                (row["status"], row["error_code"], row["quality_outcome"]),
                ("incomplete", "deadline_expired", None),
            )

            submitted = await rt.submit_research_job(
                self.runtime, "owner-1", request("reserve-action")
            )
            self.runtime.db.execute(
                "UPDATE research_jobs SET max_attempts = 6 WHERE job_id = ?",
                (submitted["job_id"],),
            )
            self.runtime.db.commit()
            no_call = AsyncMock(side_effect=AssertionError("research consumed editorial reserve"))
            with patch.object(rt, "complete_research", new=no_call):
                await rt.execute_research_job(self.runtime, submitted["job_id"])
            reserved = self.runtime.db.execute(
                "SELECT status, error_code, attempts_used FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            self.assertEqual(
                (reserved["status"], reserved["error_code"], reserved["attempts_used"]),
                ("incomplete", "editorial_attempt_reserve_reached", 0),
            )

        asyncio.run(run())

    def test_material_finding_is_dismissed_once_and_rechecked_once(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nSupported finding [S1:P0-80]"),
                completion(
                    '{"patches":[{"block_ids":["D:c1:r1:b002"],'
                    '"ledger_ids":["K-FACT"],"source_ids":["S1:P0-80"],'
                    '"reason":"Verify the material condition."}],"notes":[],'
                    '"regenerate_reason":null}'
                ),
                completion(
                    '{"base_revision":1,"replacements":[],"dismissals":[{'
                    '"finding_id":"F001","reason":"The source already supports it.",'
                    '"source_ids":["S1:P0-80"]}]}'
                ),
                completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
            ]
            job_id, _provider = await self.run_path(outputs)
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(result["quality_outcome"], "publish_with_caveats")
            assignments = [
                row["assignment_key"]
                for row in self.runtime.db.execute(
                    "SELECT assignment_key FROM research_attempts WHERE job_id = ?", (job_id,)
                )
            ]
            self.assertEqual(sum("_edit" in item for item in assignments), 1)
            self.assertEqual(sum("review_recheck" in item for item in assignments), 1)
            raw, edited = self.runtime.db.execute(
                "SELECT kind, markdown FROM editorial_revisions WHERE job_id = ? "
                "AND kind IN ('raw', 'edited') ORDER BY id",
                (job_id,),
            ).fetchall()
            self.assertEqual(raw["markdown"], edited["markdown"])

        asyncio.run(run())

    def test_material_failure_uses_exactly_two_candidates_and_selects_second(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nFirst candidate [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":"Material omission"}'),
                completion(ledger_json()),
                completion("## Unit 1\n\nSecond candidate [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
            ]
            job_id, provider = await self.run_path(outputs)
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(result["candidate"], 2)
            self.assertIn("Second candidate", result["answer_markdown"])
            self.assertNotIn("First candidate", result["answer_markdown"])
            candidates = self.runtime.db.execute(
                "SELECT candidate_no, markdown FROM editorial_revisions "
                "WHERE job_id = ? AND kind = 'raw' ORDER BY candidate_no",
                (job_id,),
            ).fetchall()
            self.assertEqual([row["candidate_no"] for row in candidates], [1, 2])
            second_ledger_prompt = json.loads(
                json.loads(provider.bodies[7])["messages"][1]["content"]
            )
            self.assertEqual(
                second_ledger_prompt["previous_failure_feedback"][0]["reason"],
                "Material omission",
            )
            self.assertIn(
                "First candidate",
                "\n".join(
                    item["text"] for item in second_ledger_prompt["previous_candidate_blocks"]
                ),
            )

        asyncio.run(run())

    def test_single_profile_fits_three_sources_and_two_full_editorial_rounds(self) -> None:
        async def run() -> None:
            urls = [f"https://example.com/source-{index}" for index in range(1, 4)]
            results = [
                rt.SearchResult(url, f"Source {index}", "Evidence", "engine", "comparison")
                for index, url in enumerate(urls, 1)
            ]

            async def fetch(result: rt.SearchResult) -> rt.FetchedSourceBlob:
                return rt.FetchedSourceBlob(
                    result.url,
                    result.url,
                    result.title,
                    result.engine,
                    "text/plain",
                    result.url.encode(),
                )

            async def extract(source: rt.FetchedSourceBlob) -> rt.ExtractedSource:
                label = source.raw_bytes.decode().rsplit("-", 1)[1]
                text = f"Source {label} evidence " + "supports comparison " * 20
                return rt.ExtractedSource(
                    text,
                    [{"page": 1, "start": 0, "end": len(text)}],
                    [],
                )

            outputs = [completion('{"action":"search","query":"three source comparison"}')]
            for index, url in enumerate(urls, 1):
                outputs.extend(
                    [
                        completion(
                            json.dumps({"action": "fetch", "url": url, "purpose": "comparison"})
                        ),
                        completion(
                            json.dumps(
                                {
                                    "action": "read",
                                    "source_id": f"S{index}",
                                    "start": 0,
                                    "end": 80,
                                }
                            )
                        ),
                    ]
                )
            outputs.extend(
                [
                    completion(
                        '{"action":"finish","findings":[{"text":"Three-source finding",'
                        '"passage_ids":["S1:P0-80","S2:P0-80","S3:P0-80"]}],"gaps":[]}'
                    ),
                    completion(ledger_json()),
                    completion("## Unit 1\n\nFirst candidate [S1:P0-80]"),
                    completion(
                        '{"patches":[{"block_ids":["D:c1:r1:b002"],'
                        '"ledger_ids":["K-FACT"],"source_ids":["S1:P0-80"],'
                        '"reason":"Revise candidate one."}],"notes":[],"regenerate_reason":null}'
                    ),
                    completion(
                        '{"base_revision":1,"replacements":[{"block_id":"D:c1:r1:b002",'
                        '"finding_ids":["F001"],"markdown":"Revised first [S1:P0-80]"}],'
                        '"dismissals":[]}'
                    ),
                    completion('{"patches":[],"notes":[],"regenerate_reason":"Still incomplete"}'),
                    completion(ledger_json()),
                    completion("## Unit 1\n\nSecond candidate [S1:P0-80]"),
                    completion(
                        '{"patches":[{"block_ids":["D:c2:r1:b002"],'
                        '"ledger_ids":["K-FACT"],"source_ids":["S1:P0-80"],'
                        '"reason":"Revise candidate two."}],"notes":[],"regenerate_reason":null}'
                    ),
                    completion(
                        '{"base_revision":1,"replacements":[{"block_id":"D:c2:r1:b002",'
                        '"finding_ids":["F001"],"markdown":"Revised second [S1:P0-80]"}],'
                        '"dismissals":[]}'
                    ),
                    completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
                ]
            )
            provider = FakeProvider(outputs)
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            with (
                patch.object(rt, "complete_research", new=provider),
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=results)),
                patch.object(rt, "fetch_source_blob", new=fetch),
                patch.object(rt, "extract_source_blob", new=extract),
            ):
                await rt.execute_research_job(self.runtime, submitted["job_id"])
            row = self.runtime.db.execute(
                "SELECT status, max_attempts, attempts_used FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            self.assertEqual(
                (row["status"], row["max_attempts"], row["attempts_used"]),
                ("completed", 18, 18),
            )
            self.assertEqual(len(provider.bodies), 18)
            author_system = json.loads(provider.bodies[9])["messages"][0]["content"]
            self.assertIn("explicit user language and length", author_system)
            self.assertIn("softly target about 3,000-4,000 characters", author_system)
            self.assertIn("not a hard gate", author_system)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) AS count FROM source_extractions WHERE job_id = ?",
                    (submitted["job_id"],),
                ).fetchone()["count"],
                3,
            )
            _code, result = await rt.research_job_result(
                self.runtime, "owner-1", submitted["job_id"]
            )
            self.assertEqual(result["candidate"], 2)
            self.assertIn("Revised second", result["answer_markdown"])

        asyncio.run(run())

    def test_long_profile_uses_derived_research_budget_beyond_eight_actions(self) -> None:
        async def run() -> None:
            provider = FakeProvider(
                [
                    completion(json.dumps({"action": "search", "query": f"distinct query {index}"}))
                    for index in range(22)
                ]
            )
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                request(profile="sequential_long", units=4, action_id="long-budget-action"),
            )
            before = self.runtime.db.execute(
                "SELECT created_at_ms, deadline_at_ms FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            with (
                patch.object(rt, "complete_research", new=provider),
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=[])),
            ):
                await rt.execute_research_job(self.runtime, submitted["job_id"])
            row = self.runtime.db.execute(
                "SELECT status, error_code, max_attempts, attempts_used, deadline_at_ms "
                "FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            self.assertEqual(
                (row["status"], row["error_code"], row["max_attempts"], row["attempts_used"]),
                ("incomplete", "editorial_attempt_reserve_reached", 40, 22),
            )
            self.assertEqual(row["deadline_at_ms"], before["deadline_at_ms"])
            self.assertEqual(before["deadline_at_ms"] - before["created_at_ms"], 10_800_000)
            self.assertEqual(len(provider.bodies), 22)
            first_limits = json.loads(json.loads(provider.bodies[0])["messages"][1]["content"])[
                "limits"
            ]
            ninth_limits = json.loads(json.loads(provider.bodies[8])["messages"][1]["content"])[
                "limits"
            ]
            self.assertEqual(
                (
                    first_limits["research_actions_remaining"],
                    ninth_limits["research_actions_remaining"],
                ),
                (22, 14),
            )

        asyncio.run(run())

    def test_unfinished_review_keeps_raw_best_with_null_quality(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nUsable raw draft [S1:P0-80]"),
                completion("not review JSON"),
                completion("still not review JSON"),
            ]
            job_id, _provider = await self.run_path(outputs)
            row = self.runtime.db.execute(
                "SELECT status, error_code, quality_outcome, best_revision_id "
                "FROM research_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            self.assertEqual(
                (row["status"], row["error_code"], row["quality_outcome"]),
                ("incomplete", "assignment_result_invalid", None),
            )
            code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(code, 200)
            self.assertEqual(result["error_code"], "assignment_result_invalid")
            self.assertIn("Usable raw draft", result["answer_markdown"])
            status_payload = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(status_payload["error_code"], "assignment_result_invalid")
            self.runtime.db.execute(
                "UPDATE editorial_revisions SET markdown = 'corrupt' WHERE id = ?",
                (row["best_revision_id"],),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
                await rt.research_job_result(self.runtime, "owner-1", job_id)

        asyncio.run(run())

    def test_late_review_completion_cannot_overwrite_cancellation(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nDraft before cancellation [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
            ]
            review_started = asyncio.Event()
            release_review = asyncio.Event()
            fake = FakeProvider(outputs)

            async def provider(
                base_url: str, api_key: str, body: bytes, lease: Any
            ) -> ResearchCompletion:
                if len(fake.bodies) == 6:
                    review_started.set()
                    await release_review.wait()
                return await fake(base_url, api_key, body, lease)

            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            contexts = self.patches(fake)
            with (
                patch.object(rt, "complete_research", new=provider),
                contexts[1],
                contexts[2],
                contexts[3],
            ):
                task = asyncio.create_task(rt.execute_research_job(self.runtime, job_id))
                await asyncio.wait_for(review_started.wait(), timeout=1)
                cancelled = await rt.cancel_research_job(self.runtime, "owner-1", job_id)
                self.assertTrue(cancelled["cancel_requested"])
                release_review.set()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            status_payload = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (status_payload["status"], status_payload["error_code"]),
                ("cancelled", "cancelled"),
            )
            self.assertIsNone(
                self.runtime.db.execute(
                    "SELECT 1 FROM publications WHERE job_id = ?", (job_id,)
                ).fetchone()
            )

        asyncio.run(run())

    def test_candidate_two_execution_error_preserves_evaluated_best_and_error(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("## Unit 1\n\nFirst evaluated draft [S1:P0-80]"),
                completion('{"patches":[],"notes":[],"regenerate_reason":"Material omission"}'),
                completion(ledger_json()),
                completion("本文。 </think> 以下が本文"),
                completion("本文。 </think> 以下が本文"),
            ]
            job_id, _provider = await self.run_path(outputs)
            row = self.runtime.db.execute(
                "SELECT status, error_code, quality_outcome FROM research_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            self.assertEqual(
                (row["status"], row["error_code"], row["quality_outcome"]),
                (
                    "incomplete",
                    "assignment_result_invalid",
                    "retryable_quality_failure",
                ),
            )
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertIn("First evaluated draft", result["answer_markdown"])

        asyncio.run(run())

    def test_internal_marker_is_never_saved_as_receipt_or_draft(self) -> None:
        async def run() -> None:
            outputs = [
                *research_outputs(),
                completion(ledger_json()),
                completion("<think>\nprivate material\n</think>"),
                completion("<think>\nprivate material\n</think>"),
            ]
            job_id, _provider = await self.run_path(outputs)
            row = self.runtime.db.execute(
                "SELECT status, error_code FROM research_jobs WHERE job_id = ?", (job_id,)
            ).fetchone()
            self.assertEqual(
                (row["status"], row["error_code"]), ("incomplete", "assignment_result_invalid")
            )
            self.assertIsNone(
                self.runtime.db.execute(
                    "SELECT 1 FROM editorial_revisions WHERE job_id = ? AND kind = 'raw'",
                    (job_id,),
                ).fetchone()
            )
            receipts = self.runtime.db.execute(
                "SELECT result_receipt FROM research_attempts WHERE job_id = ?", (job_id,)
            ).fetchall()
            self.assertNotIn(
                "private material", "".join(str(row["result_receipt"] or "") for row in receipts)
            )

        asyncio.run(run())

    def test_unknown_attempt_blocks_all_dispatch_and_survives_recovery(self) -> None:
        async def run() -> None:
            first_id, provider = await self.run_path([completion("", "unknown")])
            first = await rt.research_job_status(self.runtime, "owner-1", first_id)
            self.assertEqual(
                (first["status"], first["blocked_reason"]), ("paused", "unknown_attempt")
            )
            second = await rt.submit_research_job(self.runtime, "owner-1", request("action-2"))
            self.assertIsNone(await rt.next_queued_job(self.runtime))
            await rt.recover_research_jobs(self.runtime)
            self.assertIsNone(await rt.next_queued_job(self.runtime))
            second_status = await rt.research_job_status(self.runtime, "owner-1", second["job_id"])
            self.assertEqual(
                (second_status["status"], second_status["dispatch_blocked"]), ("queued", True)
            )
            with self.assertRaises(rt.HTTPException) as blocked:
                await rt.resume_research_job(self.runtime, "owner-1", first_id, first["revision"])
            self.assertEqual(blocked.exception.status_code, 409)
            self.assertEqual(len(provider.bodies), 1)

        asyncio.run(run())

    def test_success_receipt_prevents_resend_and_lease_includes_commit_delay(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            self.runtime.db.create_function("attempt_commit_delay", 0, lambda: time.sleep(0.05))
            self.runtime.db.execute(
                "CREATE TEMP TRIGGER slow_attempt AFTER INSERT ON research_attempts "
                "BEGIN SELECT attempt_commit_delay(); END"
            )
            provider = FakeProvider([completion("safe receipt")])
            started = asyncio.get_running_loop().time()
            with patch.object(rt, "complete_research", new=provider):
                first = await rt.invoke_job_model(
                    self.runtime,
                    job_id,
                    "stable_assignment",
                    "system",
                    "user",
                    rt.validate_visible_markdown,
                )
            self.assertEqual(first, "safe receipt")
            self.assertLessEqual(provider.leases[0].deadline_monotonic, started + 240.02)
            with patch.object(
                rt, "complete_research", new=AsyncMock(side_effect=AssertionError("resent"))
            ):
                second = await rt.invoke_job_model(
                    self.runtime,
                    job_id,
                    "stable_assignment",
                    "system",
                    "user",
                    rt.validate_visible_markdown,
                )
            self.assertEqual(second, first)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) AS count FROM research_attempts WHERE job_id = ?", (job_id,)
                ).fetchone()["count"],
                1,
            )

        asyncio.run(run())

    def test_raw_blob_survives_extraction_failure(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            blob = rt.FetchedSourceBlob(
                "https://example.com/source",
                "https://example.com/source",
                "Source",
                "Publisher",
                "application/pdf",
                b"raw-before-extraction",
            )
            source_id = await rt.store_source_blob(self.runtime, submitted["job_id"], blob)
            with (
                patch.object(
                    rt,
                    "extract_document",
                    new=AsyncMock(side_effect=ValueError("EXTRACTION_PARSE_FAILED")),
                ),
                self.assertRaises(ValueError),
            ):
                await rt.extract_source_blob(blob)
            saved = self.runtime.db.execute(
                "SELECT raw_bytes FROM source_blobs WHERE job_id = ? AND source_id = ?",
                (submitted["job_id"], source_id),
            ).fetchone()
            self.assertEqual(saved["raw_bytes"], b"raw-before-extraction")
            self.assertIsNone(
                self.runtime.db.execute(
                    "SELECT 1 FROM source_extractions WHERE job_id = ? AND source_id = ?",
                    (submitted["job_id"], source_id),
                ).fetchone()
            )

        asyncio.run(run())

    def test_prompt_schemas_bounded_unit_context_and_relevant_review_passages(self) -> None:
        async def run() -> None:
            system = rt.research_system_prompt()
            for field in ("purpose", "source_id", "start", "end", "findings", "passage_ids"):
                self.assertIn(field, system)
            long_request = request(profile="sequential_long", units=2, action_id="long-action")
            submitted = await rt.submit_research_job(self.runtime, "owner-1", long_request)
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            text = "Evidence " * 30
            blob = rt.FetchedSourceBlob(
                "https://example.com/source",
                "https://example.com/source",
                "Source",
                "Publisher",
                "text/html",
                b"raw",
            )
            source_id = await rt.store_source_blob(self.runtime, job_id, blob)
            await rt.store_source_extraction(
                self.runtime,
                job_id,
                source_id,
                rt.ExtractedSource(text, [{"page": 1, "start": 0, "end": len(text)}], []),
            )
            state_value = rt.initial_research_state()
            state_value["passages"] = [
                {
                    "id": "S1:P0-80",
                    "source_id": "S1",
                    "start": 0,
                    "end": 80,
                    "hash": rt.hashlib.sha256(text[:80].encode()).hexdigest(),
                }
            ]
            state_value["findings"] = [{"text": "finding", "passage_ids": ["S1:P0-80"]}]
            await rt.save_research_state(self.runtime, job_id, state_value, phase="writing")
            ledger = rt.DecisionLedger.model_validate(json.loads(ledger_json(2, context=True)))
            unique = "前段だけの固有本文" + "あ" * 1800
            provider = FakeProvider(
                [
                    completion(
                        f"## Unit 1\n\n{unique} [S1:P0-80]\n\n"
                        "```python\n# コード内見出し\nvalue = 1\n\nvalue += 1\n```"
                    ),
                    completion("## Unit 2\n\n次の節です [S1:P0-80]"),
                ]
            )
            with patch.object(rt, "complete_research", new=provider):
                await rt.create_raw_candidate(
                    self.runtime, job_id, 1, long_request, state_value, ledger, []
                )
            second_prompt = json.loads(json.loads(provider.bodies[1])["messages"][1]["content"])
            self.assertNotIn("accepted_prior_units", second_prompt)
            self.assertNotIn(unique, json.dumps(second_prompt))
            self.assertEqual(second_prompt["unit_scope"]["heading"], "Unit 2")
            self.assertLessEqual(len(second_prompt["selected_prior_blocks"][0]["text"]), 1200)

            blocks = rt.draft_blocks("## A\n\nClaim [S1:P0-80]", 1, 1)
            passages = [
                {"id": "S1:P0-80", "text": "one"},
                {"id": "S2:P0-80", "text": "unrelated"},
            ]
            review_prompt = json.loads(
                rt.review_user_prompt(long_request, 1, 1, "## A", blocks, ledger, passages)
            )
            self.assertEqual(
                [item["id"] for item in review_prompt["source_passages"]], ["S1:P0-80"]
            )

        asyncio.run(run())

    def test_review_ranges_use_actual_utf8_body_and_cover_every_block_once(self) -> None:
        ledger = rt.DecisionLedger.model_validate(json.loads(ledger_json()))
        body = "\n\n".join(f"Paragraph {index} " + "日" * 7000 for index in range(4))
        blocks = rt.draft_blocks(body, 1, 1)
        ranges = rt.pack_review_ranges(
            self.runtime.settings.model,
            request(),
            1,
            1,
            body,
            blocks,
            ledger,
            [],
        )
        self.assertGreater(len(ranges), 1)
        self.assertEqual(
            [block.id for group in ranges for block in group], [block.id for block in blocks]
        )
        for group in ranges:
            prompt = rt.review_user_prompt(request(), 1, 1, body, group, ledger, [])
            self.assertLessEqual(
                len(
                    rt.prepare_research_request(
                        self.runtime.settings.model, rt.review_system_prompt(), prompt
                    )
                ),
                rt.JOB_REQUEST_BYTES,
            )

    def test_markdown_boundary_rejects_unframed_inline_markers_but_understands_code(self) -> None:
        with self.assertRaisesRegex(ValueError, "internal generation marker"):
            rt.validate_visible_markdown("## 本文\n\n説明。 </think> 以下が本文")
        report = (
            "## 通常見出し\n\n"
            "`</think>` は文字列例です。\n\n"
            '```json\n{"action":"search"}\n\n# code heading\n```\n\n'
            "結論 [S1:P0-80]"
        )
        self.assertEqual(rt.validate_visible_markdown(report), report)
        blocks = rt.draft_blocks(report, 1, 1)
        code_blocks = [block for block in blocks if "```json" in block.text]
        self.assertEqual(len(code_blocks), 1)
        self.assertIn("\n\n# code heading\n", code_blocks[0].text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
