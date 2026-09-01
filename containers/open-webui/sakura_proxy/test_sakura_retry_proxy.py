from __future__ import annotations

import json
import threading
import unittest
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import ClassVar

from sakura_retry_proxy import Settings, make_server, retry_after_seconds


class UpstreamHandler(BaseHTTPRequestHandler):
    attempts = 0
    mode = "rate_limit"
    attempts_by_body: ClassVar[dict[bytes, int]] = {}
    request_bodies: ClassVar[list[bytes]] = []

    def do_POST(self) -> None:
        type(self).attempts += 1
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        type(self).request_bodies.append(body)
        type(self).attempts_by_body[body] = (
            type(self).attempts_by_body.get(body, 0) + 1
        )
        if (self.mode == "rate_limit" and self.attempts < 3) or (
            self.mode == "second_rate_limited"
            and body == b"second"
            and self.attempts_by_body[body] == 1
        ):
            self.send_response(429)
            self.send_header("Retry-After", "0")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.mode == "always_timeout" or (
            self.mode == "timeout_then_success" and self.attempts == 1
        ):
            body = b'data: {"error":{"code":"timeout"}}\n\n'
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class SakuraRetryProxyTest(unittest.TestCase):
    def setUp(self) -> None:
        UpstreamHandler.attempts = 0
        UpstreamHandler.mode = "rate_limit"
        UpstreamHandler.attempts_by_body = {}
        UpstreamHandler.request_bodies = []
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream_port = self.upstream.server_address[1]
        self.proxy = make_server(
            Settings(
                upstream_url=f"http://127.0.0.1:{upstream_port}",
                max_retries=3,
                base_backoff=0.01,
                max_backoff=0.01,
                jitter=0,
            ),
            ("127.0.0.1", 0),
        )
        self.threads = [
            threading.Thread(target=server.serve_forever, daemon=True)
            for server in (self.upstream, self.proxy)
        ]
        for thread in self.threads:
            thread.start()

    def tearDown(self) -> None:
        for server in (self.proxy, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=1)

    def test_retries_429_then_streams_success(self) -> None:
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=b"{}",
            headers={"Authorization": "Bearer test"},
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertEqual(UpstreamHandler.attempts, 3)

    def test_retries_timeout_once_with_low_reasoning(self) -> None:
        UpstreamHandler.mode = "timeout_then_success"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "max"}).encode(),
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertEqual(UpstreamHandler.attempts, 2)
        self.assertEqual(
            [
                json.loads(body)["reasoning_effort"]
                for body in UpstreamHandler.request_bodies
            ],
            ["max", "low"],
        )

    def test_retries_timeout_once_unchanged_without_reasoning_effort(self) -> None:
        UpstreamHandler.mode = "timeout_then_success"
        proxy_port = self.proxy.server_address[1]
        body = json.dumps({"model": "test"}).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=body,
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertEqual(UpstreamHandler.request_bodies, [body, body])

    def test_retries_timeout_only_once(self) -> None:
        UpstreamHandler.mode = "always_timeout"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "high"}).encode(),
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(
                response.read(), b'data: {"error":{"code":"timeout"}}\n\n'
            )
        self.assertEqual(UpstreamHandler.attempts, 2)

    def test_does_not_retry_none_as_low(self) -> None:
        UpstreamHandler.mode = "always_timeout"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "none"}).encode(),
        )
        with urllib.request.urlopen(request) as response:
            response.read()
        self.assertEqual(UpstreamHandler.attempts, 1)

    def test_retry_after_parser(self) -> None:
        self.assertEqual(retry_after_seconds("2"), 2)
        self.assertIsNone(retry_after_seconds("invalid"))

    def test_concurrent_429_retries_only_affected_request(self) -> None:
        UpstreamHandler.mode = "second_rate_limited"
        proxy_port = self.proxy.server_address[1]

        def request(body: bytes) -> bytes:
            with urllib.request.urlopen(
                urllib.request.Request(
                    f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
                    data=body,
                )
            ) as response:
                return response.read()

        with ThreadPoolExecutor(max_workers=2) as executor:
            responses = list(executor.map(request, (b"first", b"second")))

        self.assertEqual(responses, [b'{"ok":true}'] * 2)
        self.assertEqual(
            UpstreamHandler.attempts_by_body, {b"first": 1, b"second": 2}
        )

if __name__ == "__main__":
    unittest.main()
