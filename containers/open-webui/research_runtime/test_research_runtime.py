from __future__ import annotations

import asyncio
import json
import os
import tempfile
import unittest
from collections.abc import AsyncIterator
from pathlib import Path
from types import SimpleNamespace, TracebackType
from typing import Any, cast
from unittest.mock import AsyncMock, patch

import aiohttp
import httpx
from strands.agent.conversation_manager import SlidingWindowConversationManager
from strands.tools.executors import SequentialToolExecutor

os.environ.setdefault("RESEARCH_RUNTIME_API_KEY", "test-api-key")
os.environ.setdefault("RESEARCH_LLM_BASE_URL", "http://llm.local/v1")
os.environ.setdefault("RESEARCH_LLM_API_KEY", "llm-key")
os.environ.setdefault("RESEARCH_MODEL", "preview/Kimi-K2.7-Code")
os.environ.setdefault("RESEARCH_KIMI_TIMEOUT_SECONDS", "290")
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

    async def iter_chunked(self, _size: int) -> AsyncIterator[bytes]:
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


def parse_tool_payload(result: dict[str, Any]) -> dict[str, Any]:
    return json.loads(result["content"][0]["text"])


class FakeAgent:
    def __init__(self, tools: list[Any]) -> None:
        self.tools = {tool.tool_name: tool for tool in tools}

    async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
        search = parse_tool_payload(await self.tools["search_web"]("query one"))
        if len(search["results"]) < 2:
            raise AssertionError("missing search results")
        fetch_one = parse_tool_payload(
            await self.tools["fetch_source"](search["results"][0]["url"], "support")
        )
        fetch_two = parse_tool_payload(
            await self.tools["fetch_source"](search["results"][1]["url"], "support")
        )
        if "evidence" not in fetch_one or "evidence" not in fetch_two:
            raise AssertionError("missing evidence")
        inspected = parse_tool_payload(await self.tools["inspect_evidence_ledger"]())
        await self.tools["submit_report"](
            inspected["ledger_revision"],
            "Answer with citations [S1] [S2]",
            [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
            ["none"],
        )
        return SimpleNamespace(
            stop_reason="end_turn",
            message={"role": "assistant", "content": [{"text": "done"}]},
        )


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
        self.assertIn("inspect", op["description"])
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
        self.assertEqual(
            rt.SourceModel.model_json_schema()["properties"]["id"]["pattern"], "^S\\d+$"
        )
        self.assertEqual(rt.MAX_SOURCES, 40)
        self.assertEqual(rt.MAX_FINDINGS, 20)

    def test_sources_section_normalizes_title_whitespace_and_wraps_url(self) -> None:
        text = rt.append_sources_section(
            "Answer [S1]",
            [
                rt.SourceModel(
                    id="S1",
                    url="https://example.com/a_(b)",
                    title="Line 1\n  Line 2",
                    publisher="p",
                    published_at="",
                    hash="a" * 64,
                    relevance=1.0,
                    source_quality=0.8,
                )
            ],
        )
        self.assertIn("[S1] Line 1 Line 2 — <https://example.com/a_(b)>", text)

    def test_deep_report_requires_long_structured_ten_source_answer(self) -> None:
        budget = rt.make_budget("deep")
        self.assertEqual(budget.turns, 120)
        evidence = [
            rt.Evidence(
                id=f"S{index}",
                url=f"https://example.com/{index}",
                title=f"Source {index}",
                publisher="Publisher",
                published_at="2026-01-01",
                excerpt="Evidence",
                hash=f"{index:064x}",
                relevance=1.0,
                source_quality=0.8,
            )
            for index in range(1, 11)
        ]
        state = rt.RunState(
            evidence=evidence,
            searched_queries=set(),
            evidence_revision=10,
            last_inspected_revision=10,
            stats=rt.default_stats("deep", budget, rt.wall_budget_seconds("deep")),
        )
        citations = " ".join(f"[S{index}]" for index in range(1, 11))
        findings = [
            {"claim": "First finding", "source_ids": [f"S{index}" for index in range(1, 6)]},
            {"claim": "Second finding", "source_ids": [f"S{index}" for index in range(6, 11)]},
        ]

        with self.assertRaisesRegex(ValueError, "deep report too short"):
            rt.validate_submit_report(
                "rid", state, 10, f"Short report {citations}", findings, ["none"], budget, "deep"
            )

        unstructured = ("Detailed comparison and evidence. " * 300) + citations
        with self.assertRaisesRegex(ValueError, "at least five sections"):
            rt.validate_submit_report(
                "rid", state, 10, unstructured, findings, ["none"], budget, "deep"
            )

        sections = "\n\n".join(
            [
                "## 要約",
                "## 調査方法",
                "## 詳細分析",
                "## 反証と不確実性",
                "## 提言と限界",
            ]
        )
        nine_citations = " ".join(f"[S{index}]" for index in range(1, 10))
        nine_findings = [
            {"claim": "First finding", "source_ids": [f"S{index}" for index in range(1, 6)]},
            {"claim": "Second finding", "source_ids": [f"S{index}" for index in range(6, 10)]},
        ]
        with self.assertRaisesRegex(ValueError, "at least ten cited sources"):
            rt.validate_submit_report(
                "rid",
                state,
                10,
                sections + "\n\n" + ("Detailed evidence. " * 500) + nine_citations,
                nine_findings,
                ["none"],
                budget,
                "deep",
            )

        answer = sections + "\n\n" + ("根拠を比較し、含意と不確実性を分析する。" * 500) + citations
        response = rt.validate_submit_report(
            "rid", state, 10, answer, findings, ["none"], budget, "deep"
        )
        self.assertGreaterEqual(len(response.answer_markdown), rt.DEEP_MIN_ANSWER_CHARS)
        self.assertEqual(len(response.sources), rt.DEEP_MIN_CITED_SOURCES)

    def test_auth_and_validation(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
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

        asyncio.run(run())

    def test_searxng_language_accepts_codes_and_broadens_names(self) -> None:
        self.assertEqual(rt.searxng_language("ja"), "ja")
        self.assertEqual(rt.searxng_language("ja-jp"), "ja-JP")
        self.assertEqual(rt.searxng_language("auto"), "all")
        self.assertEqual(rt.searxng_language("Japanese"), "all")

    def test_idempotency_resume_and_completed_retry(self) -> None:
        async def run() -> None:
            request = rt.ResearchRequest.model_validate(
                {"query": "sample query", "depth": "quick", "language": "auto", "focus": "f"}
            )
            key = rt.normalize_idempotency_key("msg-1")
            rid, request_hash, cached, state = await rt.reserve_run(self.runtime, request, key)
            self.assertIsNone(cached)
            self.assertIsNone(state)

            budget = rt.make_budget("quick")
            snapshot = rt.run_state_snapshot(
                rt.RunState(
                    evidence=[
                        rt.Evidence(
                            id="S1",
                            url="http://example.com",
                            title="t",
                            publisher="p",
                            published_at="2026-01-01",
                            excerpt="excerpt",
                            hash="a" * 64,
                            relevance=1.0,
                            source_quality=0.8,
                        )
                    ],
                    searched_queries={"sample query"},
                    evidence_revision=1,
                    last_inspected_revision=1,
                    stats=rt.default_stats("quick", budget, rt.wall_budget_seconds("quick")),
                )
            )
            await rt.checkpoint_run(
                self.runtime,
                key,
                "failed",
                rid,
                request_hash,
                error="failed",
                state=snapshot,
            )
            resumed_rid, _, resumed_cached, resumed_state = await rt.reserve_run(
                self.runtime,
                request,
                key,
            )
            self.assertEqual(resumed_rid, rid)
            self.assertIsNone(resumed_cached)
            self.assertEqual(cast(dict[str, Any], resumed_state)["evidence_revision"], 1)

            response = rt.ResearchResponse(
                research_id=rid,
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
            await rt.checkpoint_run(
                self.runtime,
                key,
                "completed",
                rid,
                request_hash,
                response=response.model_dump(),
            )
            cached_rid, _, cached_payload, cached_state = await rt.reserve_run(
                self.runtime,
                request,
                key,
            )
            self.assertEqual(cached_rid, rid)
            self.assertIsNone(cached_state)
            self.assertEqual(cast(dict[str, Any], cached_payload)["answer_markdown"], "done [S1]")

            with self.assertRaises(rt.HTTPException) as ctx:
                await rt.reserve_run(
                    self.runtime,
                    rt.ResearchRequest.model_validate(
                        {
                            "query": "different query",
                            "depth": "quick",
                            "language": "auto",
                            "focus": "f",
                        }
                    ),
                    key,
                )
            self.assertEqual(ctx.exception.status_code, 409)

        asyncio.run(run())

    def test_resumed_state_requires_reinspection_without_final_response(self) -> None:
        budget = rt.make_budget("quick")
        loaded = rt.load_run_state(
            {
                "evidence_ledger": [
                    {
                        "id": "S1",
                        "url": "http://example.com",
                        "title": "t",
                        "publisher": "p",
                        "published_at": "2026-01-01",
                        "excerpt": "excerpt",
                        "hash": "a" * 64,
                        "relevance": 1.0,
                        "source_quality": 0.8,
                    }
                ],
                "searched_queries": ["q"],
                "evidence_revision": 1,
                "last_inspected_revision": 1,
                "stats": {"depth": "quick"},
                "final_response": None,
            },
            depth="quick",
            budget=budget,
            wall_limit=rt.wall_budget_seconds("quick"),
        )
        self.assertIsNone(loaded.last_inspected_revision)

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
        excerpt, relevance = rt.select_relevant_excerpt(text, "documented feature", None)
        self.assertTrue(rt.is_verbatim_excerpt(excerpt, text))
        self.assertGreaterEqual(relevance, 0.7)

    def test_search_and_fetch_type_errors_are_nonfatal_expected_failures(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f")
            state = rt.load_run_state(
                None,
                depth="quick",
                budget=rt.make_budget("quick"),
                wall_limit=1,
            )
            with patch.object(
                rt,
                "search_searxng",
                new=AsyncMock(side_effect=TypeError("bad search")),
            ):
                tools, _allowlist, fatal_errors = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "kid-type-errors",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                search = await tool_map["search_web"]("q2")
                self.assertEqual(search["status"], "error")
                self.assertFalse(fatal_errors)

            with (
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/1", "One", "snippet", "engine")
                        ]
                    ),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(side_effect=TypeError("bad doc")),
                ),
            ):
                tools, _allowlist, fatal_errors = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "kid-type-errors-2",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                await tool_map["search_web"]("q3")
                fetched = await tool_map["fetch_source"]("http://example.com/1", "support")
                self.assertEqual(fetched["status"], "error")
                self.assertFalse(fatal_errors)

        asyncio.run(run())

    def test_build_research_agent_uses_expected_model_manager_and_executor(self) -> None:
        agent = rt.build_research_agent(
            self.runtime.settings,
            rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f"),
            [],
        )
        model = cast(rt.SakuraKimiModel, agent.model)
        conversation_manager = cast(SlidingWindowConversationManager, agent.conversation_manager)
        system_prompt = cast(str, agent.system_prompt)
        model_config = cast(dict[str, Any], model.config)
        model_params = cast(dict[str, Any], model_config["params"])
        self.assertEqual(model.client_args["max_retries"], 0)
        self.assertEqual(model_params["max_tokens"], rt.KIMI_MAX_TOKENS)
        self.assertEqual(agent._retry_strategy._max_attempts, 1)
        self.assertIsInstance(agent.tool_executor, SequentialToolExecutor)
        self.assertEqual(conversation_manager.window_size, 30)
        self.assertEqual(conversation_manager.pin_first, 1)
        self.assertTrue(conversation_manager.per_turn)
        self.assertIsNotNone(conversation_manager._compression_threshold)
        self.assertIn("same language as the user's query", system_prompt)
        self.assertIn("ledger_revision", system_prompt)

    def test_run_research_completes_via_search_fetch_inspect_submit(self) -> None:
        async def run() -> None:
            search_results = [
                rt.SearchResult("http://example.com/1", "t1", "snippet 1", "engine"),
                rt.SearchResult("http://example.com/2", "t2", "snippet 2", "engine"),
            ]
            evidence_items = [
                rt.Evidence(
                    url="http://example.com/1",
                    title="Title 1",
                    publisher="Publisher",
                    published_at="2026-01-01",
                    excerpt="verbatim excerpt 1",
                    hash="a" * 64,
                    relevance=0.8,
                    source_quality=0.7,
                ),
                rt.Evidence(
                    url="http://example.com/2",
                    title="Title 2",
                    publisher="Publisher",
                    published_at="2026-01-02",
                    excerpt="verbatim excerpt 2",
                    hash="b" * 64,
                    relevance=0.9,
                    source_quality=0.8,
                ),
            ]

            async def fake_extract(
                result: rt.SearchResult,
                query: str,
                focus: str | None,
            ) -> rt.Evidence:
                self.assertEqual(query, "q")
                self.assertEqual(focus, "f; support")
                return evidence_items.pop(0)

            with (
                patch.object(
                    rt,
                    "build_research_agent",
                    side_effect=lambda *_args: FakeAgent(_args[2]),
                ),
                patch.object(rt, "search_searxng", new=AsyncMock(return_value=search_results)),
                patch.object(rt, "extract_evidence", new=AsyncMock(side_effect=fake_extract)),
            ):
                result = await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f"),
                    "rid",
                    "kid",
                )
            self.assertIn("Answer with citations [S1] [S2]", result.answer_markdown)
            self.assertIn("## Sources", result.answer_markdown)
            self.assertEqual(result.findings[0].source_ids, ["S1", "S2"])
            self.assertEqual([source.id for source in result.sources], ["S1", "S2"])
            row = self.runtime.db.execute(
                (
                    "SELECT status, state_json, response_json FROM research_runs "
                    "WHERE idempotency_key = ?"
                ),
                ("kid",),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "completed")
            self.assertIn("## Sources", json.loads(row["response_json"])["answer_markdown"])

        asyncio.run(run())

    def test_tools_reject_unallowlisted_urls_and_invalid_submit_before_accepting(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f")
            budget = rt.make_budget("quick")
            state = rt.load_run_state(
                None,
                depth="quick",
                budget=budget,
                wall_limit=rt.wall_budget_seconds("quick"),
            )
            state.evidence = [
                rt.Evidence(
                    id="S1",
                    url="http://example.com/1",
                    title="One",
                    publisher="P1",
                    published_at="2026-01-01",
                    excerpt="excerpt 1",
                    hash="a" * 64,
                    relevance=0.8,
                    source_quality=0.7,
                ),
                rt.Evidence(
                    id="S2",
                    url="http://example.com/2",
                    title="Two",
                    publisher="P2",
                    published_at="2026-01-02",
                    excerpt="excerpt 2",
                    hash="b" * 64,
                    relevance=0.9,
                    source_quality=0.8,
                ),
            ]
            state.evidence_revision = 2
            state.stats["evidence"] = 2
            state.stats["evidence_revision"] = 2
            with patch.object(
                rt,
                "search_searxng",
                new=AsyncMock(
                    return_value=[
                        rt.SearchResult("http://example.com/3", "Three", "snippet", "engine")
                    ]
                ),
            ):
                tools, _allowlist, fatal_errors = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "kid-tools",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}

                searched = await tool_map["search_web"]("extra query")
                self.assertEqual(searched["status"], "success")
                duplicate = await tool_map["search_web"]("extra query")
                self.assertEqual(duplicate["status"], "error")
                row = self.runtime.db.execute(
                    "SELECT state_json FROM research_runs WHERE idempotency_key = ?",
                    ("kid-tools",),
                ).fetchone()
                self.assertIsNotNone(row)
                saved_state = json.loads(row["state_json"])
                self.assertIn("extra query", saved_state["searched_queries"])

                rejected = await tool_map["fetch_source"]("http://not-allowed.example", "why")
                self.assertEqual(rejected["status"], "error")
                self.assertEqual(parse_tool_payload(rejected)["code"], "url_not_allowlisted")

                bad_purpose = await tool_map["fetch_source"]("http://example.com/1", "")
                self.assertEqual(bad_purpose["status"], "error")

                uninspected = await tool_map["submit_report"](
                    2,
                    "Claim [S1] [S2]",
                    [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
                    ["none"],
                )
                self.assertEqual(uninspected["status"], "error")

                inspected = await tool_map["inspect_evidence_ledger"]()
                inspected_payload = parse_tool_payload(inspected)
                self.assertEqual(inspected_payload["revision"], 2)
                self.assertEqual(inspected_payload["ledger_revision"], 2)

                unknown = await tool_map["submit_report"](
                    2,
                    "Claim [S3]",
                    [{"claim": "Claim", "source_ids": ["S3"]}],
                    ["none"],
                )
                self.assertEqual(unknown["status"], "error")

                mismatch = await tool_map["submit_report"](
                    2,
                    "Claim [S1] [S2]",
                    [{"claim": "Claim", "source_ids": ["S1"]}],
                    ["none"],
                )
                self.assertEqual(mismatch["status"], "error")

                stale_revision = await tool_map["submit_report"](
                    1,
                    "Claim [S1] [S2]",
                    [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
                    ["none"],
                )
                self.assertEqual(stale_revision["status"], "error")

                accepted = await tool_map["submit_report"](
                    2,
                    "Claim [S1] [S2]",
                    [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
                    ["none"],
                )
                self.assertEqual(accepted["status"], "success")
                self.assertFalse(fatal_errors)

        asyncio.run(run())

    def test_new_evidence_invalidates_saved_report_and_requires_reinspection(self) -> None:
        async def run() -> None:
            research = rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f")
            budget = rt.make_budget("quick")
            state = rt.load_run_state(None, depth="quick", budget=budget, wall_limit=1)
            state.evidence = [
                rt.Evidence(
                    id="S1",
                    url="http://example.com/1",
                    title="One",
                    publisher="P1",
                    published_at="2026-01-01",
                    excerpt="excerpt 1",
                    hash="a" * 64,
                    relevance=0.8,
                    source_quality=0.7,
                )
            ]
            state.evidence_revision = 1
            state.last_inspected_revision = 1
            state.stats["evidence"] = 1
            state.stats["evidence_revision"] = 1
            state.final_response = {"cached": True}

            with (
                patch.object(
                    rt,
                    "search_searxng",
                    new=AsyncMock(
                        return_value=[
                            rt.SearchResult("http://example.com/2", "Two", "snippet", "engine")
                        ]
                    ),
                ),
                patch.object(
                    rt,
                    "extract_evidence",
                    new=AsyncMock(
                        return_value=rt.Evidence(
                            url="http://example.com/2",
                            title="Two",
                            publisher="P2",
                            published_at="2026-01-02",
                            excerpt="excerpt 2",
                            hash="b" * 64,
                            relevance=0.9,
                            source_quality=0.8,
                        )
                    ),
                ),
            ):
                tools, _allowlist, _fatal = rt.build_research_tools(
                    self.runtime,
                    research,
                    "rid",
                    "kid-invalidate",
                    rt.query_hash(research.model_dump()),
                    state,
                )
                tool_map = {tool.tool_name: tool for tool in tools}
                await tool_map["search_web"]("next query")
                fetched = await tool_map["fetch_source"]("http://example.com/2", "support")
                self.assertEqual(fetched["status"], "success")
                self.assertIsNone(state.final_response)
                self.assertIsNone(state.last_inspected_revision)
                submit = await tool_map["submit_report"](
                    2,
                    "Claim [S1] [S2]",
                    [{"claim": "Claim", "source_ids": ["S1", "S2"]}],
                    ["none"],
                )
                self.assertEqual(submit["status"], "error")

        asyncio.run(run())

    def test_run_research_wall_timeout_cancels_and_checkpoints(self) -> None:
        cancelled = False

        class SlowAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                nonlocal cancelled
                try:
                    await asyncio.sleep(1)
                finally:
                    cancelled = True
                return SimpleNamespace(
                    stop_reason="end_turn",
                    message={"role": "assistant", "content": []},
                )

        async def run() -> None:
            with (
                patch.object(rt, "wall_budget_seconds", return_value=0.01),
                patch.object(rt, "build_research_agent", return_value=SlowAgent()),
                self.assertRaises(TimeoutError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f"),
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

    def test_run_research_inner_timeout_before_deadline_is_normal_failure(self) -> None:
        class TimeoutAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                raise TimeoutError("upstream timeout")

        async def run() -> None:
            with (
                patch.object(rt, "build_research_agent", return_value=TimeoutAgent()),
                self.assertRaises(RuntimeError),
            ):
                await rt.run_research(
                    self.runtime,
                    FakeRequest(),
                    rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f"),
                    "rid-inner-timeout",
                    "kid-inner-timeout",
                )
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key = ?",
                ("kid-inner-timeout",),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "failed")
            state = json.loads(row["state_json"])
            self.assertFalse(state["stats"]["wall_exhausted"])
            self.assertEqual(state["stats"]["stop_reason"], "TimeoutError")

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
                    "evidence_ledger": [],
                    "searched_queries": [],
                    "evidence_revision": 0,
                    "last_inspected_revision": None,
                    "stats": {"a": 1},
                    "final_response": None,
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
                    idempotency_key, request_hash, research_id, status, created_at, updated_at
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
                        FakeResponse(headers={"Content-Type": "text/xml"}, chunks=[b"<xml/>"])
                    ),
                )
                await rt.fetch_bytes(session, "http://example.com", 100)
            with self.assertRaises(ValueError):
                response = cast(aiohttp.ClientResponse, FakeResponse(chunks=[b"a" * 5, b"b" * 5]))
                await rt.read_bytes_with_cap(response, 5)

        asyncio.run(run())

    def test_run_research_external_cancel_saves_cancelled_state(self) -> None:
        cleaned = False

        class SlowAgent:
            async def invoke_async(self, _prompt: str, **_kwargs: Any) -> SimpleNamespace:
                nonlocal cleaned
                try:
                    await asyncio.sleep(1)
                finally:
                    cleaned = True
                return SimpleNamespace(
                    stop_reason="end_turn",
                    message={"role": "assistant", "content": []},
                )

        async def run() -> None:
            with patch.object(rt, "build_research_agent", return_value=SlowAgent()):
                task = asyncio.create_task(
                    rt.run_research(
                        self.runtime,
                        FakeRequest(),
                        rt.ResearchRequest(query="q", depth="quick", language="auto", focus="f"),
                        "rid-cancel",
                        "kid-cancel",
                    )
                )
                await asyncio.sleep(0)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            self.assertTrue(cleaned)
            row = self.runtime.db.execute(
                "SELECT status, state_json FROM research_runs WHERE idempotency_key = ?",
                ("kid-cancel",),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["status"], "cancelled")
            self.assertIn("stats", json.loads(row["state_json"]))

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main(verbosity=2)
