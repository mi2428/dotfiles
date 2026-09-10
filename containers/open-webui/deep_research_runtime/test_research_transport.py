from __future__ import annotations

import asyncio
import json
import time
import unittest
from typing import cast
from unittest.mock import patch

from aiohttp import web

import sakura_kimi_model as adapter
from sakura_kimi_model import (
    RESEARCH_MAX_RESPONSE_BYTES,
    AttemptLease,
    AttemptOutcome,
    ResearchCompletion,
    complete_research,
    prepare_research_request,
)


def event(payload: object) -> bytes:
    return b"data: " + json.dumps(payload, separators=(",", ":")).encode() + b"\n\n"


class ResearchTransportTests(unittest.IsolatedAsyncioTestCase):
    def test_physical_attempt_deadline_allows_provider_timeout(self) -> None:
        self.assertEqual(adapter.RESEARCH_MAX_SECONDS, 360.0)

    async def asyncSetUp(self) -> None:
        self.mode = "success"
        self.calls: list[tuple[str, bytes, dict[str, str]]] = []
        self.started = asyncio.Event()
        app = web.Application()
        app.router.add_route("*", "/{path:.*}", self.handle)
        self.runner = web.AppRunner(app)
        await self.runner.setup()
        self.site = web.TCPSite(self.runner, "127.0.0.1", 0)
        await self.site.start()
        server = cast(asyncio.Server | None, self.site._server)
        assert server is not None and server.sockets
        self.base_url = f"http://127.0.0.1:{server.sockets[0].getsockname()[1]}/v1"
        self.body = prepare_research_request("public-model", "system", "user")

    async def asyncTearDown(self) -> None:
        await self.runner.cleanup()

    def lease(self, seconds: float = 2) -> AttemptLease:
        return AttemptLease(
            "attempt-1",
            asyncio.get_running_loop().time() + seconds,
            int((time.time() + seconds) * 1000),
        )

    def response_headers(self, state: str = "sent") -> dict[str, str]:
        return {
            "X-Sakura-Attempt-Id": "attempt-1",
            "X-Sakura-Upstream-Send": state,
        }

    def stream_body(
        self,
        *,
        content: str = "visible",
        finish: str = "stop",
        usage: object = None,
        done: bool = True,
        after_finish: bool = False,
    ) -> bytes:
        chunks = [
            event(
                {
                    "choices": [
                        {
                            "delta": {"content": content},
                            "finish_reason": None,
                            "index": 0,
                        }
                    ],
                    "usage": None,
                }
            ),
            event(
                {
                    "choices": [{"delta": {}, "finish_reason": finish, "index": 0}],
                    "usage": None,
                }
            ),
        ]
        if after_finish:
            chunks.append(
                event(
                    {
                        "choices": [
                            {
                                "delta": {"content": "late"},
                                "finish_reason": None,
                                "index": 0,
                            }
                        ]
                    }
                )
            )
        if usage is not None:
            chunks.append(event({"choices": [], "usage": usage}))
        if done:
            chunks.append(b"data: [DONE]\n\n")
        return b"".join(chunks)

    async def handle(self, request: web.Request) -> web.StreamResponse:
        body = await request.read()
        self.calls.append((request.path, body, dict(request.headers)))
        self.started.set()
        if self.mode == "not_sent":
            return web.Response(status=400, headers=self.response_headers("not-sent"), body=b"{}")
        if self.mode == "redirect":
            return web.Response(
                status=307,
                headers={**self.response_headers(), "Location": "/research/v1/chat/completions"},
            )
        if self.mode == "oversize":
            return web.Response(
                headers=self.response_headers(), body=b"x" * (RESEARCH_MAX_RESPONSE_BYTES + 1)
            )
        if self.mode in {"drip", "cancel"}:
            response = web.StreamResponse(headers=self.response_headers())
            await response.prepare(request)
            await response.write(event({"choices": []}))
            await asyncio.sleep(0.2)
            return response
        bodies: dict[str, bytes] = {
            "success": self.stream_body(
                usage={"prompt_tokens": 1, "completion_tokens": 2, "total_tokens": 3}
            ),
            "usage_missing": self.stream_body(),
            "length": self.stream_body(finish="length"),
            "empty": self.stream_body(content=""),
            "incomplete": self.stream_body(done=False),
            "unknown_finish": self.stream_body(finish="provider-private-value"),
            "after_finish": self.stream_body(after_finish=True),
            "invalid_json": b"data: {\n\ndata: [DONE]\n\n",
            "truncated_json": b'data: {"choices":[',
            "truncated_error": b'data: {"error":',
            "explicit_error": event({"error": {"code": "timeout", "message": "request timed out"}}),
        }
        return web.Response(headers=self.response_headers(), body=bodies[self.mode])

    async def test_prepare_contract_and_imported_dtos(self) -> None:
        decoded = json.loads(self.body)
        self.assertEqual(
            set(decoded), {"max_tokens", "messages", "model", "stream", "stream_options"}
        )
        self.assertEqual(decoded["max_tokens"], 16_384)
        self.assertIs(decoded["stream"], True)
        self.assertEqual(decoded["stream_options"], {"include_usage": True})
        self.assertNotIn(b"reasoning_effort", self.body)
        self.assertNotIn(b"tool_choice", self.body)
        self.assertEqual(self.body, prepare_research_request("public-model", "system", "user"))
        with self.assertRaisesRegex(ValueError, "RESEARCH_REQUEST_TOO_LARGE"):
            prepare_research_request("public-model", "system", "x" * 65_536)
        self.assertEqual(
            ResearchCompletion("", AttemptOutcome("not_sent", None, None, None, None, None, 0)),
            ResearchCompletion("", AttemptOutcome("not_sent", None, None, None, None, None, 0)),
        )

    async def test_success_uses_exact_body_expiry_and_nullable_usage_chunks(self) -> None:
        lease = self.lease()
        result = await complete_research(self.base_url, "internal-key", self.body, lease)
        self.assertEqual(result.content, "visible")
        self.assertEqual(result.outcome.state, "succeeded")
        self.assertEqual(result.outcome.finish_reason, "stop")
        self.assertEqual(
            (
                result.outcome.prompt_tokens,
                result.outcome.completion_tokens,
                result.outcome.total_tokens,
            ),
            (1, 2, 3),
        )
        self.assertEqual(len(self.calls), 1)
        path, body, headers = self.calls[0]
        self.assertEqual(path, "/research/v1/chat/completions")
        self.assertEqual(body, self.body)
        self.assertEqual(headers["X-Sakura-Deadline-Unix-Ms"], str(lease.expires_at_unix_ms))
        self.assertEqual(headers["X-Sakura-Attempt-Id"], lease.attempt_id)

    async def test_usage_may_be_missing(self) -> None:
        self.mode = "usage_missing"
        result = await complete_research(self.base_url, "internal-key", self.body, self.lease())
        self.assertEqual(result.outcome.state, "succeeded")
        self.assertEqual(result.outcome.prompt_tokens, None)

    async def test_complete_invalid_results_are_known_failed_with_safe_finish(self) -> None:
        for mode, finish in (
            ("length", "length"),
            ("empty", "stop"),
            ("unknown_finish", "unknown"),
            ("after_finish", None),
            ("invalid_json", None),
            ("explicit_error", None),
        ):
            with self.subTest(mode=mode):
                self.mode = mode
                result = await complete_research(
                    self.base_url, "internal-key", self.body, self.lease()
                )
                self.assertEqual(result.content, "")
                self.assertEqual(result.outcome.state, "known_failed")
                self.assertEqual(result.outcome.finish_reason, finish)

    async def test_incomplete_stream_timeout_and_oversize_are_unknown(self) -> None:
        for mode in ("incomplete", "truncated_json", "truncated_error"):
            with self.subTest(mode=mode):
                self.mode = mode
                result = await complete_research(
                    self.base_url, "internal-key", self.body, self.lease()
                )
                self.assertEqual(result.outcome.state, "unknown")
        self.mode = "oversize"
        result = await complete_research(self.base_url, "internal-key", self.body, self.lease())
        self.assertEqual(result.outcome.state, "unknown")
        self.assertEqual(result.outcome.response_bytes, RESEARCH_MAX_RESPONSE_BYTES)
        self.mode = "drip"
        result = await complete_research(self.base_url, "internal-key", self.body, self.lease(0.05))
        self.assertEqual(result.outcome.state, "unknown")

    async def test_earlier_wall_expiry_bounds_a_later_monotonic_deadline(self) -> None:
        self.mode = "drip"
        lease = AttemptLease(
            "attempt-1",
            asyncio.get_running_loop().time() + 1,
            int((time.time() + 0.05) * 1000),
        )
        started = time.monotonic()
        result = await complete_research(self.base_url, "internal-key", self.body, lease)
        self.assertEqual(result.outcome.state, "unknown")
        self.assertLess(time.monotonic() - started, 0.15)

    async def test_not_sent_invalid_inputs_and_redirect_do_not_replay(self) -> None:
        self.mode = "not_sent"
        result = await complete_research(self.base_url, "internal-key", self.body, self.lease())
        self.assertEqual(result.outcome.state, "not_sent")

    async def test_recursive_json_parser_failure_is_safe(self) -> None:
        with patch.object(adapter.json, "loads", side_effect=RecursionError):
            result = await complete_research(self.base_url, "internal-key", self.body, self.lease())
        self.assertEqual(result.content, "")
        self.assertEqual(result.outcome.state, "known_failed")
        self.mode = "redirect"
        before = len(self.calls)
        result = await complete_research(self.base_url, "internal-key", self.body, self.lease())
        self.assertEqual(result.outcome.state, "known_failed")
        self.assertEqual(len(self.calls), before + 1)
        before = len(self.calls)
        for base_url in (
            "http://[",
            "http://127.0.0.1:99999/v1",
            self.base_url.replace("http://", "http://user@"),
            f"{self.base_url}/other",
        ):
            result = await complete_research(base_url, "internal-key", self.body, self.lease())
            self.assertEqual(result.outcome.state, "not_sent")
        self.assertEqual(len(self.calls), before)
        result = await complete_research(self.base_url, "internal-key", b"x" * 65_537, self.lease())
        self.assertEqual(result.outcome.state, "not_sent")

    async def test_cancellation_propagates(self) -> None:
        self.mode = "cancel"
        task = asyncio.create_task(
            complete_research(self.base_url, "internal-key", self.body, self.lease())
        )
        await self.started.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task


if __name__ == "__main__":
    unittest.main(verbosity=2)
