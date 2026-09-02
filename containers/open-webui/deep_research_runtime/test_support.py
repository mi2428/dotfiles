from __future__ import annotations

import asyncio
import json
import os
import tempfile
import unittest
from collections.abc import AsyncIterator
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace, TracebackType
from typing import Any, cast

os.environ.setdefault("DEEP_RESEARCH_RUNTIME_API_KEY", "test-api-key")
os.environ.setdefault("DEEP_RESEARCH_LLM_BASE_URL", "http://llm.local/v1")
os.environ.setdefault("DEEP_RESEARCH_LLM_API_KEY", "llm-key")
os.environ.setdefault("DEEP_RESEARCH_MODEL", "preview/Kimi-K2.7-Code")
os.environ.setdefault("DEEP_RESEARCH_KIMI_TIMEOUT_SECONDS", "1800")
os.environ.setdefault("SEARXNG_URL", "http://searxng.local")
os.environ.setdefault(
    "DEEP_RESEARCH_DB_PATH",
    str(Path(tempfile.gettempdir()) / "deep-research-runtime-test.db"),
)

import deep_research_runtime as rt


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
    def __init__(self, response: FakeResponse) -> None:
        self.response = response

    async def __aenter__(self) -> FakeResponse:
        return self.response

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> bool:
        return False


class FakeSession:
    def __init__(self, response: FakeResponse) -> None:
        self.response = response

    def get(self, *_args: object, **_kwargs: object) -> FakeHTTPResponseContext:
        return FakeHTTPResponseContext(self.response)


class StructuredAgent:
    def __init__(self, outputs: list[rt.StrictModel | Exception]) -> None:
        self.outputs = outputs
        self.models: list[type[rt.StrictModel]] = []
        self.limits: list[dict[str, int]] = []

    async def invoke_async(self, _prompt: str, **kwargs: Any) -> SimpleNamespace:
        model = cast(type[rt.StrictModel], kwargs["structured_output_model"])
        output = self.outputs.pop(0)
        self.models.append(model)
        self.limits.append(kwargs["limits"])
        if isinstance(output, Exception):
            raise output
        if not isinstance(output, model):
            raise AssertionError(f"expected {model.__name__}, got {type(output).__name__}")
        return SimpleNamespace(
            stop_reason="tool_use",
            structured_output=output,
            message={"role": "assistant", "content": []},
        )


class RuntimeTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        os.environ["DEEP_RESEARCH_DB_PATH"] = str(Path(self.tmpdir.name) / "runtime.db")
        settings = rt.Settings.from_environment()
        self.runtime = rt.Runtime(settings, rt.open_db(settings.db_path), asyncio.Lock())
        rt.app.state.runtime = self.runtime

    def tearDown(self) -> None:
        self.runtime.db.close()
        self.tmpdir.cleanup()


def parse_tool_payload(result: dict[str, Any]) -> dict[str, Any]:
    return json.loads(result["content"][0]["text"])


def make_evidence(count: int, *, relevance: float = 0.7) -> list[rt.Evidence]:
    return [
        rt.Evidence(
            id=f"S{index}",
            url=f"https://example.com/{index}",
            title=f"Source {index}",
            publisher="Publisher",
            published_at="2026-01-01",
            excerpt=(
                f"Evidence {index} contains enough substantive alphabetic source content "
                "to support a directly relevant research claim."
            ),
            hash=f"{index:064x}",
            relevance=relevance,
            source_quality=0.5,
            search_query="Evidence research",
            purpose="support claim",
        )
        for index in range(1, count + 1)
    ]


def make_state(count: int, depth: str = "deep") -> rt.RunState:
    budget = rt.make_budget(depth)
    evidence = make_evidence(count)
    stats = rt.default_stats(depth, budget, rt.wall_budget_seconds(depth))
    stats.update(evidence=count, usable_evidence=count, evidence_revision=count)
    return rt.RunState(
        evidence=evidence,
        searched_queries=set(),
        evidence_revision=count,
        last_inspected_revision=count,
        stats=stats,
    )


def deep_answer(source_count: int) -> str:
    return "\n\n".join(
        f"## Section {index}\n\n{deep_section_body(source_count)}"
        for index in range(1, rt.DEEP_MIN_SECTIONS + 1)
    )


def deep_findings(source_count: int) -> list[dict[str, Any]]:
    groups = [[] for _ in range(rt.DEEP_MIN_FINDINGS)]
    for index in range(1, source_count + 1):
        groups[(index - 1) % len(groups)].append(f"S{index}")
    return [
        {"claim": f"Finding {index}", "source_ids": source_ids}
        for index, source_ids in enumerate(groups, 1)
    ]


def report_sections(source_count: int) -> list[rt.ReportSection]:
    body = deep_section_body(source_count)
    return [
        rt.ReportSection(f"Section {index}", body, source_count)
        for index in range(1, rt.DEEP_MIN_SECTIONS + 1)
    ]


def deep_section_body(source_count: int) -> str:
    citations = " ".join(f"[S{index}]" for index in range(1, source_count + 1))
    sentence = "Detailed evidence and analysis. "
    repetitions = (rt.STRUCTURED_DEEP_SECTION_CHARS + len(sentence) - 1) // len(sentence)
    return sentence * repetitions + citations


def stable_quick_state(count: int = 2) -> rt.RunState:
    state = make_state(count, "quick")
    state.evidence = [
        replace(item, relevance=0.6, search_query="Evidence", purpose="") for item in state.evidence
    ]
    state.stats["usable_evidence"] = count
    return state
