from __future__ import annotations

import asyncio
import importlib
import json
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar

from sakura_kimi_model import (
    AttemptLease,
    ResearchCompletion,
    complete_research,
    prepare_research_request,
)

PROXY_DIR = Path(__file__).resolve().parent.parent / "sakura_proxy"
sys.path.insert(0, str(PROXY_DIR))
proxy_module = importlib.import_module("sakura_retry_proxy")


def sse_event(payload: object) -> bytes:
    return b"data: " + json.dumps(payload, separators=(",", ":")).encode() + b"\n\n"


class FakeUpstreamHandler(BaseHTTPRequestHandler):
    mode = "success"
    attempts = 0
    paths: ClassVar[list[str]] = []
    bodies: ClassVar[list[bytes]] = []

    def do_POST(self) -> None:
        type(self).attempts += 1
        type(self).paths.append(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        type(self).bodies.append(self.rfile.read(length))
        if self.mode == "failure":
            self._send(503, b"{}")
            return
        if self.mode == "incomplete":
            self._send(200, b'data: {"choices":[')
            return
        body = b"".join(
            (
                sse_event(
                    {
                        "choices": [
                            {
                                "delta": {"content": "visible"},
                                "finish_reason": None,
                                "index": 0,
                            }
                        ],
                        "usage": None,
                    }
                ),
                sse_event(
                    {
                        "choices": [{"delta": {}, "finish_reason": "stop", "index": 0}],
                        "usage": None,
                    }
                ),
                sse_event(
                    {
                        "choices": [],
                        "usage": {
                            "completion_tokens": 2,
                            "prompt_tokens": 1,
                            "total_tokens": 3,
                        },
                    }
                ),
                b"data: [DONE]\n\n",
            )
        )
        self._send(200, body)

    def _send(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class ResearchGatewayIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        FakeUpstreamHandler.mode = "success"
        FakeUpstreamHandler.attempts = 0
        FakeUpstreamHandler.paths = []
        FakeUpstreamHandler.bodies = []
        self.tmpdir = tempfile.TemporaryDirectory()
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstreamHandler)
        settings = proxy_module.Settings(
            upstream_url=f"http://127.0.0.1:{self.upstream.server_address[1]}",
            account_tokens=("account-token",),
            account_ids=("account-public",),
            account_db_path=str(Path(self.tmpdir.name) / "shared.db"),
            research_api_key="gateway-key",
        )
        self.proxy = proxy_module.make_server(settings, ("127.0.0.1", 0))
        self.threads = [
            threading.Thread(target=server.serve_forever, daemon=True)
            for server in (self.upstream, self.proxy)
        ]
        for thread in self.threads:
            thread.start()
        self.base_url = f"http://127.0.0.1:{self.proxy.server_address[1]}/v1"
        self.body = prepare_research_request("public-model", "system", "user")

    async def asyncTearDown(self) -> None:
        for server in (self.proxy, self.upstream):
            await asyncio.to_thread(server.shutdown)
            server.server_close()
        for thread in self.threads:
            await asyncio.to_thread(thread.join, 2)
            self.assertFalse(thread.is_alive())
        self.tmpdir.cleanup()

    def lease(self) -> AttemptLease:
        return AttemptLease(
            "integration-attempt",
            asyncio.get_running_loop().time() + 2,
            int((time.time() + 2) * 1000),
        )

    async def complete(self, api_key: str = "gateway-key") -> ResearchCompletion:
        return await complete_research(self.base_url, api_key, self.body, self.lease())

    async def test_success_preserves_exact_body_visible_content_and_final_usage(self) -> None:
        result = await self.complete()
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
        self.assertEqual(FakeUpstreamHandler.attempts, 1)
        self.assertEqual(FakeUpstreamHandler.paths, ["/v1/chat/completions"])
        self.assertEqual(FakeUpstreamHandler.bodies, [self.body])

    async def test_gateway_credential_rejection_is_not_sent(self) -> None:
        result = await self.complete("wrong-key")
        self.assertEqual(result.content, "")
        self.assertEqual(result.outcome.state, "not_sent")
        self.assertEqual(result.outcome.http_status, 401)
        self.assertEqual(FakeUpstreamHandler.attempts, 0)

    async def test_upstream_http_failure_is_known_failed_without_retry(self) -> None:
        FakeUpstreamHandler.mode = "failure"
        result = await self.complete()
        self.assertEqual(result.content, "")
        self.assertEqual(result.outcome.state, "known_failed")
        self.assertEqual(result.outcome.http_status, 503)
        self.assertEqual(FakeUpstreamHandler.attempts, 1)
        self.assertEqual(FakeUpstreamHandler.bodies, [self.body])

    async def test_incomplete_sse_is_unknown_without_partial_content(self) -> None:
        FakeUpstreamHandler.mode = "incomplete"
        result = await self.complete()
        self.assertEqual(result.content, "")
        self.assertEqual(result.outcome.state, "unknown")
        self.assertEqual(FakeUpstreamHandler.attempts, 1)
        self.assertEqual(FakeUpstreamHandler.bodies, [self.body])


if __name__ == "__main__":
    unittest.main(verbosity=2)
