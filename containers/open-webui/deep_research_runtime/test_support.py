from __future__ import annotations

import asyncio
import os
import tempfile
import unittest
from collections.abc import AsyncIterator
from pathlib import Path
from types import TracebackType

os.environ.setdefault("DEEP_RESEARCH_RUNTIME_API_KEY", "test-api-key")
os.environ.setdefault("DEEP_RESEARCH_LLM_BASE_URL", "http://llm.local/v1")
os.environ.setdefault("DEEP_RESEARCH_LLM_API_KEY", "llm-key")
os.environ.setdefault("DEEP_RESEARCH_MODEL", "preview/Kimi-K2.7-Code")
os.environ.setdefault("DEEP_RESEARCH_KIMI_TIMEOUT_SECONDS", "3600")
os.environ.setdefault("DEEP_RESEARCH_OPERATOR_API_KEY", "test-operator-key")
os.environ.setdefault("DEEP_RESEARCH_OPERATOR_ID", "test-operator")
os.environ.setdefault("SEARXNG_URL", "http://searxng.local")
os.environ.setdefault(
    "DEEP_RESEARCH_DB_PATH",
    str(Path(tempfile.gettempdir()) / "deep-research-runtime-test.db"),
)

import deep_research_runtime as rt


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
