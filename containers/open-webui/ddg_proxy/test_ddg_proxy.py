"""Tests for the internal DuckDuckGo transport proxy."""

from __future__ import annotations

import threading
import unittest
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from email.message import Message
from unittest.mock import patch

import ddg_proxy


@dataclass
class FakeResponse:
    status_code: int = 200
    content: bytes = b'<a class="result__a">result</a>'
    headers: dict[str, str] = field(
        default_factory=lambda: {"content-type": "text/html"}
    )


class FakeClient:
    """Record forwarded forms without network access."""

    def __init__(self) -> None:
        self.data: dict[str, str] = {}
        self.calls = 0
        self.response = FakeResponse()
        self.error: Exception | None = None

    def post(self, url: str, *, data: dict[str, str]) -> FakeResponse:
        self.calls += 1
        self.data = data
        if self.error is not None:
            raise self.error
        return self.response


class FakeClock:
    """Advance monotonic time only when a test asks or the proxy sleeps."""

    def __init__(self) -> None:
        self.now = 100.0
        self.sleeps: list[float] = []

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds


class DdgProxyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = FakeClient()
        self.clock = FakeClock()
        self.original_client = ddg_proxy.CLIENT
        self.original_last_request_at = ddg_proxy.LAST_REQUEST_AT
        self.original_cooldown_until = ddg_proxy.COOLDOWN_UNTIL
        ddg_proxy.CLIENT = self.client
        ddg_proxy.LAST_REQUEST_AT = None
        ddg_proxy.COOLDOWN_UNTIL = 0
        self.patches = [
            patch.object(ddg_proxy, "MIN_INTERVAL_SECONDS", 10),
            patch.object(ddg_proxy, "CAPTCHA_COOLDOWN_SECONDS", 60),
            patch.object(ddg_proxy, "RATE_LIMIT_COOLDOWN_SECONDS", 30),
            patch.object(ddg_proxy, "MONOTONIC", self.clock.monotonic),
            patch.object(ddg_proxy, "WALL_TIME", self.clock.monotonic),
            patch.object(ddg_proxy, "SLEEP", self.clock.sleep),
        ]
        for active_patch in self.patches:
            active_patch.start()
        self.server = ddg_proxy.make_server(("127.0.0.1", 0))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)
        for active_patch in reversed(self.patches):
            active_patch.stop()
        ddg_proxy.CLIENT = self.original_client
        ddg_proxy.LAST_REQUEST_AT = self.original_last_request_at
        ddg_proxy.COOLDOWN_UNTIL = self.original_cooldown_until

    def post(self, data: bytes = b"q=test") -> tuple[int, Message, bytes]:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/", data=data
        )
        try:
            response = urllib.request.urlopen(request)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.headers, error.read()
        with response:
            return response.status, response.headers, response.read()

    def test_forwards_valid_form(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/",
            data=b"q=Python+3.14&b=&kl=wt-wt",
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertIn(b"result__a", response.read())
        self.assertEqual(self.client.data["q"], "Python 3.14")

    def test_rejects_other_paths(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/other",
            data=b"q=test",
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()
        self.assertEqual(error.exception.code, 404)

    def test_rejects_empty_queries_before_upstream(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/",
            data=b"q=",
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()
        self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.client.data, {})

    def test_captcha_becomes_generic_429_without_logging_secrets(self) -> None:
        self.client.response = FakeResponse(
            status_code=202,
            content=b'<form id="challenge-form">captcha-body-secret</form>',
        )

        with self.assertLogs("ddg-proxy", level="INFO") as logs:
            status, headers, body = self.post(b"q=query-secret")

        self.assertEqual(status, 429)
        self.assertEqual(headers["Retry-After"], "60")
        self.assertEqual(body, b'{"error":"temporarily unavailable"}')
        self.assertNotIn("query-secret", "\n".join(logs.output))
        self.assertNotIn("captcha-body-secret", "\n".join(logs.output))

    def test_cooldown_skips_upstream(self) -> None:
        self.client.response = FakeResponse(content=b"challenge-form")
        self.assertEqual(self.post()[0], 429)
        self.client.response = FakeResponse()

        status, headers, _ = self.post()

        self.assertEqual(status, 429)
        self.assertEqual(headers["Retry-After"], "60")
        self.assertEqual(self.client.calls, 1)
        self.assertEqual(self.clock.sleeps, [])

    def test_waits_for_minimum_interval(self) -> None:
        self.assertEqual(self.post()[0], 200)
        self.assertEqual(self.post()[0], 200)

        self.assertEqual(self.client.calls, 2)
        self.assertEqual(self.clock.sleeps, [10])

    def test_upstream_429_uses_bounded_retry_after(self) -> None:
        self.client.response = FakeResponse(
            status_code=429,
            content=b"provider details",
            headers={"Retry-After": "9999", "Content-Type": "text/plain"},
        )

        status, headers, body = self.post()

        self.assertEqual(status, 429)
        self.assertEqual(headers["Retry-After"], "30")
        self.assertEqual(body, b'{"error":"temporarily unavailable"}')
        self.assertEqual(self.client.calls, 1)

    def test_transport_failure_is_generic_and_not_retried(self) -> None:
        self.client.error = RuntimeError("query-secret")

        with self.assertLogs("ddg-proxy", level="ERROR") as logs:
            status, _, body = self.post(b"q=query-secret")

        self.assertEqual(status, 502)
        self.assertEqual(body, b'{"error":"upstream unavailable"}')
        self.assertEqual(self.client.calls, 1)
        self.assertNotIn("query-secret", "\n".join(logs.output))


if __name__ == "__main__":
    unittest.main()
