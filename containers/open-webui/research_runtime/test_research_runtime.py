from __future__ import annotations

import asyncio
import json
import os
import tempfile
import time
import unittest
from collections.abc import AsyncIterator
from pathlib import Path
from types import TracebackType
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import aiohttp
import httpx

os.environ.setdefault("RESEARCH_RUNTIME_API_KEY", "test-api-key")
os.environ.setdefault("RESEARCH_LLM_BASE_URL", "http://llm.local/v1")
os.environ.setdefault("RESEARCH_LLM_API_KEY", "llm-key")
os.environ.setdefault("RESEARCH_PLANNER_MODEL", "planner")
os.environ.setdefault("RESEARCH_SYNTHESIZER_MODEL", "synth")
os.environ.setdefault("SEARXNG_URL", "http://searxng.local")
os.environ.setdefault(
    "RESEARCH_DB_PATH", str(Path(tempfile.gettempdir()) / "research-runtime-test.db")
)

import research_runtime as rt


class FakeRequest:
    def __init__(self, disconnected: bool = False) -> None:
        self._disconnected = disconnected

    async def is_disconnected(self) -> bool:
        return self._disconnected


class FakeResponse:
    def __init__(
        self,
        *,
        status: int = 200,
        headers: dict[str, str] | None = None,
        chunks: list[bytes] | None = None,
    ) -> None:
        self.status = status
        self.headers = headers or {"Content-Type": "application/json"}
        self._chunks = chunks or [b"{}"]

    @property
    def content(self) -> FakeResponse:
        return self

    async def iter_chunked(self, size: int) -> AsyncIterator[bytes]:
        for chunk in self._chunks:
            yield chunk


class FakeHTTPResponseContext:
    def __init__(self, resp: FakeResponse) -> None:
        self.resp = resp

    async def __aenter__(self) -> FakeResponse:
        return self.resp

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> bool:
        return False


class FakeSession:
    def __init__(self, resp: FakeResponse) -> None:
        self.resp = resp

    def get(self, *_args: object, **_kwargs: object) -> FakeHTTPResponseContext:
        return FakeHTTPResponseContext(self.resp)


class ResearchRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        os.environ["RESEARCH_DB_PATH"] = str(Path(self.tmpdir.name) / "runtime.db")
        settings = rt.Settings.from_environment()
        self.runtime = rt.Runtime(settings, rt.open_db(settings.db_path), asyncio.Lock())
        rt.app.state.runtime = self.runtime

    def tearDown(self) -> None:
        self.runtime.db.close()
        self.tmpdir.cleanup()

    def test_openapi_only_research_and_security_scheme(self) -> None:
        spec = rt.app.openapi()
        self.assertEqual(sorted(spec["paths"].keys()), ["/research"])
        op = spec["paths"]["/research"]["post"]
        self.assertEqual(op["operationId"], "deep_research")
        self.assertIn("internal research pass", op["description"])
        self.assertIn("HTTPBearer", spec["components"]["securitySchemes"])
        self.assertTrue(op["security"])
        self.assertNotIn("parameters", op)

    def test_response_schema_and_source_ids(self) -> None:
        response = rt.ResearchResponse(
            research_id="r1",
            answer_markdown="line 1\nline 2 [S1]",
            findings=[rt.CitationModel(claim="claim", source_ids=["S1"])],
            sources=[
                rt.SourceModel(
                    id="S1",
                    url="http://example.com",
                    title="t",
                    publisher="p",
                    published_at="2026-01-01",
                    hash="a" * 64,
                    relevance=1.0,
                    source_quality=0.8,
                )
            ],
            limitations=["none"],
            stats={"depth": "quick"},
        )
        self.assertEqual(response.findings[0].source_ids, ["S1"])
        self.assertEqual(response.answer_markdown.splitlines(), ["line 1", "line 2 [S1]"])
        self.assertEqual(
            rt.SourceModel.model_json_schema()["properties"]["id"]["pattern"], "^S\\d+$"
        )

    def test_auth_and_validation(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                response = await client.post("/research", json={"query": "x"})
                self.assertEqual(response.status_code, 401)
                headers = {"Authorization": "Bearer test-api-key"}
                response = await client.post("/research", headers=headers, json={"query": ""})
                self.assertEqual(response.status_code, 422)
                response = await client.post(
                    "/research",
                    headers=headers,
                    json={"query": "ok", "depth": "bad"},
                )
                self.assertEqual(response.status_code, 422)
                response = await client.post("/research", headers=headers, json={"query": 1})
                self.assertEqual(response.status_code, 422)

            with self.assertRaises(ValueError):
                rt.Plan.model_validate(
                    {
                        "queries": ["q"],
                        "summary": "",
                        "open_questions": [],
                        "contradictions": [],
                        "stop": "false",
                    }
                )

        asyncio.run(run())

    def test_idempotency_completed_retry(self) -> None:
        payload = {
            "query": "sample query",
            "depth": "quick",
            "language": "auto",
            "focus": "focus",
            "recency_days": 7,
        }
        result = rt.ResearchResponse(
            research_id="r1",
            answer_markdown="done [S1]",
            findings=[rt.CitationModel(claim="c", source_ids=["S1"])],
            sources=[
                rt.SourceModel(
                    id="S1",
                    url="http://example.com",
                    title="t",
                    publisher="p",
                    published_at="",
                    hash="a" * 64,
                    relevance=1.0,
                    source_quality=1.0,
                )
            ],
            limitations=["none"],
            stats={"depth": "quick"},
        )

        async def run() -> None:
            key = rt.normalize_idempotency_key("msg-1")
            request = rt.ResearchRequest.model_validate(payload)
            rid, request_hash, cached = await rt.reserve_run(self.runtime, request, key)
            self.assertIsNone(cached)
            self.assertEqual(len(key), 64)
            await rt.checkpoint_run(
                self.runtime,
                key,
                "completed",
                rid,
                request_hash,
                response=result.model_dump(),
            )
            cached_rid, _, cached_payload = await rt.reserve_run(self.runtime, request, key)
            self.assertEqual(cached_rid, rid)
            cached_payload = cast(dict[str, Any], cached_payload)
            self.assertEqual(cached_payload["answer_markdown"], "done [S1]")

            with self.assertRaises(rt.HTTPException) as ctx:
                await rt.reserve_run(
                    self.runtime,
                    rt.ResearchRequest.model_validate({**payload, "query": "different"}),
                    key,
                )
            self.assertEqual(ctx.exception.status_code, 409)

            random_key1 = rt.normalize_idempotency_key(None)
            random_key2 = rt.normalize_idempotency_key(None)
            self.assertNotEqual(random_key1, random_key2)
            rid1, _, cached1 = await rt.reserve_run(self.runtime, request, random_key1)
            rid2, _, cached2 = await rt.reserve_run(self.runtime, request, random_key2)
            self.assertIsNone(cached1)
            self.assertIsNone(cached2)
            self.assertNotEqual(rid1, rid2)

        asyncio.run(run())

    def test_html_text_preserves_source_metadata(self) -> None:
        text, metadata = rt.extract_html_text(
            b"""<html><head><title>Release notes</title>
            <meta property="og:site_name" content="Official Project">
            <meta property="article:published_time" content="2026-08-25T00:00:00Z">
            </head><body><article><p>This release adds a documented feature
            with enough text for extraction.</p>
            <p>The details are factual source content.</p></article></body></html>"""
        )
        self.assertIn("documented feature", text)
        self.assertEqual(metadata["title"], "Release notes")
        self.assertEqual(metadata["publisher"], "Official Project")
        self.assertEqual(metadata["published_at"], "2026-08-25")
        self.assertTrue(rt.is_verbatim_excerpt("documented  feature", text))
        self.assertFalse(rt.is_verbatim_excerpt("released in 2025", text))
        excerpt, relevance = rt.select_relevant_excerpt(text, "documented feature", None)
        self.assertTrue(rt.is_verbatim_excerpt(excerpt, text))
        self.assertGreaterEqual(relevance, 0.7)
        self.assertEqual(rt.source_quality("https://github.com/org/repo/releases/tag/v1"), 0.9)

    def test_budget_round_allocation_and_stop(self) -> None:
        self.assertEqual(rt.distribute_budget(4, 2), [2, 2])
        self.assertEqual(rt.distribute_budget(6, 3), [2, 2, 2])
        self.assertEqual(rt.recency_time_range(1), "day")
        self.assertEqual(rt.recency_time_range(14), "month")
        self.assertEqual(rt.recency_time_range(180), "year")
        compacted = rt.Compaction(
            summary="",
            open_questions=[],
            contradictions=[],
            next_queries=[],
            coverage=0.96,
            information_gain=1.0,
            stop=False,
        )
        self.assertTrue(rt.should_stop_compaction(compacted, time.monotonic()))
        compacted.coverage = 0.1
        compacted.information_gain = 0.1
        self.assertTrue(rt.should_stop_compaction(compacted, float("inf")))

    def test_run_research_persists_state_and_completed_result(self) -> None:
        async def run() -> None:
            planner = rt.Plan(
                queries=["example query"],
                summary="s",
                open_questions=[],
                contradictions=[],
                stop=False,
            )
            synth = rt.Synthesis(answer_markdown="answer [S1]\nnext line", limitations=["lim"])
            responses: list[rt.Plan | rt.Synthesis] = [planner, synth]

            async def fake_call(*_args: object, **_kwargs: object) -> rt.Plan | rt.Synthesis:
                return responses.pop(0)

            search_result = rt.SearchResult("http://example.com", "t", "c", "e")
            evidence = rt.Evidence(
                url="http://example.com",
                title="t",
                publisher="pub",
                published_at="2026-01-01",
                excerpt="excerpt",
                hash="a" * 64,
                relevance=0.8,
                source_quality=0.7,
            )
            with (
                patch.object(rt, "call_llm_json", side_effect=fake_call),
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(return_value=[search_result]),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(return_value=evidence),
                ),
            ):
                result = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(
                        query="q",
                        depth="quick",
                        language="auto",
                        focus="f",
                        recency_days=1,
                    ),
                    "rid",
                    "kid",
                )
                self.assertEqual(result.answer_markdown, "answer [S1]\nnext line")
                self.assertEqual(result.findings[0].source_ids, ["S1"])
                row = self.runtime.db.execute(
                    "SELECT status, state_json, response_json "
                    "FROM research_runs WHERE idempotency_key = ?",
                    ("kid",),
                ).fetchone()
                self.assertIsNotNone(row)
                self.assertEqual(row["status"], "completed")
                state = json.loads(row["state_json"])
                self.assertIn("working_state", state)
                self.assertTrue(
                    json.loads(row["response_json"])["answer_markdown"].startswith("answer")
                )

        asyncio.run(run())

    def test_run_research_wall_timeout_cancels_and_checkpoints(self) -> None:
        cancelled = False

        async def slow_call(*_args: object, **_kwargs: object) -> None:
            nonlocal cancelled
            try:
                await asyncio.sleep(1)
            finally:
                cancelled = True

        async def run() -> None:
            with (
                patch.object(rt, "wall_budget_seconds", return_value=0.01),
                patch.object(rt, "call_llm_json", side_effect=slow_call),
                self.assertRaises(TimeoutError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(
                        query="q", depth="quick", language="auto", focus="f", recency_days=1
                    ),
                    "rid-timeout",
                    "kid-timeout",
                )
            self.assertTrue(cancelled)
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key = ?",
                ("kid-timeout",),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "failed")
            state = json.loads(row["state_json"])
            self.assertTrue(state["stats"]["wall_exhausted"])
            self.assertEqual(state["stats"]["stop_reason"], "wall")

        asyncio.run(run())

    def test_iteration_checkpoint_and_stale_recovery(self) -> None:
        async def run() -> None:
            await rt.checkpoint_run(
                self.runtime,
                "k1",
                "running",
                "r1",
                "h1",
                state={
                    "working_state": {},
                    "evidence_ledger": [],
                    "stats": {"a": 1},
                },
            )
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key = ?",
                ("k1",),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "running")
            self.assertIn("evidence_ledger", json.loads(row["state_json"]))
            self.runtime.db.execute(
                """
                INSERT INTO research_runs (
                    idempotency_key, request_hash, research_id,
                    status, created_at, updated_at
                ) VALUES (?, ?, ?, 'running', 1, 1)
                """,
                ("stale", "h", "r2"),
            )
            self.runtime.db.commit()
            await rt.recover_stale_runs(self.runtime)
            stale = self.runtime.db.execute(
                "SELECT status FROM research_runs WHERE idempotency_key = ?",
                ("stale",),
            ).fetchone()
            self.assertIsNotNone(stale)
            self.assertEqual(stale["status"], "interrupted")

        asyncio.run(run())

    def test_ssrf_private_and_userinfo_block(self) -> None:
        with self.assertRaises(ValueError):
            rt.validate_public_url("http://127.0.0.1/x")
        with self.assertRaises(ValueError):
            rt.validate_public_url("http://user:pass@example.com/x")

    def test_disallowed_content_type_and_byte_cap(self) -> None:
        async def run() -> None:
            with self.assertRaises(ValueError):
                session = cast(
                    aiohttp.ClientSession,
                    FakeSession(
                        FakeResponse(
                            headers={"Content-Type": "text/xml"},
                            chunks=[b"<xml/>"],
                        )
                    ),
                )
                await rt.fetch_bytes(session, "http://example.com", 100)
            with self.assertRaises(ValueError):
                response = cast(
                    aiohttp.ClientResponse,
                    FakeResponse(chunks=[b"a" * 5, b"b" * 5]),
                )
                await rt.read_bytes_with_cap(response, 5)

        asyncio.run(run())

    def test_outer_cancellation_child_cleanup(self) -> None:
        cleaned = False

        async def slow() -> str:
            nonlocal cleaned
            try:
                await asyncio.sleep(1)
            finally:
                cleaned = True
            return "ok"

        async def run() -> None:
            task = asyncio.create_task(rt.request_guard(FakeRequest(), slow()))
            await asyncio.sleep(0)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            self.assertTrue(cleaned)

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main(verbosity=2)
