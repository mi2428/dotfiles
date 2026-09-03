from __future__ import annotations

import http.client
import json
import os
import threading
import time
import unittest
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import ClassVar, cast
from unittest.mock import patch

from sakura_retry_proxy import (
    SakuraRetryProxyHandler,
    Settings,
    SharedTokenCooldown,
    TokenLease,
    make_server,
    retry_after_seconds,
    retry_delay_seconds,
    retryable_response_reason,
)


class UpstreamHandler(BaseHTTPRequestHandler):
    attempts = 0
    mode = "rate_limit"
    attempts_by_body: ClassVar[dict[bytes, int]] = {}
    request_bodies: ClassVar[list[bytes]] = []
    authorization_headers: ClassVar[list[str | None]] = []
    attempts_by_authorization: ClassVar[dict[str | None, int]] = {}
    active_requests = 0
    max_active_requests = 0
    active_by_authorization: ClassVar[dict[str | None, int]] = {}
    max_active_by_authorization: ClassVar[dict[str | None, int]] = {}
    state_lock = threading.Lock()
    hold_event = threading.Event()
    request_started_event = threading.Event()
    two_requests_started_event = threading.Event()

    def do_POST(self) -> None:
        type(self).attempts += 1
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        type(self).request_bodies.append(body)
        authorization = self.headers.get("Authorization")
        type(self).authorization_headers.append(authorization)
        type(self).attempts_by_authorization[authorization] = (
            type(self).attempts_by_authorization.get(authorization, 0) + 1
        )
        type(self).attempts_by_body[body] = type(self).attempts_by_body.get(body, 0) + 1
        with type(self).state_lock:
            type(self).active_requests += 1
            type(self).max_active_requests = max(
                type(self).max_active_requests, type(self).active_requests
            )
            type(self).active_by_authorization[authorization] = (
                type(self).active_by_authorization.get(authorization, 0) + 1
            )
            type(self).max_active_by_authorization[authorization] = max(
                type(self).max_active_by_authorization.get(authorization, 0),
                type(self).active_by_authorization[authorization],
            )
            type(self).request_started_event.set()
            if type(self).active_requests >= 2:
                type(self).two_requests_started_event.set()
        try:
            if self.mode in {"serialized_hold", "parallel_hold"}:
                type(self).hold_event.wait(timeout=1)
            if (
                self.mode in {"rate_limit", "rate_limit_slow"} and self.attempts < 3
            ) or (
                self.mode == "second_rate_limited"
                and body == b"second"
                and self.attempts_by_body[body] == 1
            ):
                self.send_response(429)
                self.send_header(
                    "Retry-After", "1000" if self.mode == "rate_limit_slow" else "0"
                )
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if (
                self.mode == "token_a_once_rate_limited"
                and authorization == "Bearer token-a"
                and self.attempts_by_authorization[authorization] == 1
            ):
                self.send_response(429)
                self.send_header("Retry-After", "0.2")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.mode == "always_timeout" or (
                self.mode in {"timeout_then_success", "timeout_then_stream"}
                and self.attempts == 1
            ):
                body = b'data: {"error":{"code":"timeout"}}\n\n'
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.mode == "server_error_then_success" and self.attempts == 1:
                body = b'{"error":{"code":"server_error"}}'
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.mode == "always_internal_error" or (
                self.mode == "internal_error_then_success" and self.attempts == 1
            ):
                body = b'data: {"error":{"code":"internal_server_error"}}\n\n'
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.mode == "timeout_then_stream":
                body = b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
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
        finally:
            with type(self).state_lock:
                type(self).active_requests -= 1
                type(self).active_by_authorization[authorization] = (
                    type(self).active_by_authorization.get(authorization, 1) - 1
                )

    def log_message(self, format: str, *args: object) -> None:
        pass


class SakuraRetryProxyTest(unittest.TestCase):
    def unsafe_settings(self, **changes: object) -> Settings:
        base = cast(
            type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass
        ).settings
        settings = object.__new__(Settings)
        for field in Settings.__dataclass_fields__:
            object.__setattr__(settings, field, getattr(base, field))
        for field, value in changes.items():
            object.__setattr__(settings, field, value)
        return settings

    def setUp(self) -> None:
        UpstreamHandler.attempts = 0
        UpstreamHandler.mode = "rate_limit"
        UpstreamHandler.attempts_by_body = {}
        UpstreamHandler.request_bodies = []
        UpstreamHandler.authorization_headers = []
        UpstreamHandler.attempts_by_authorization = {}
        UpstreamHandler.active_requests = 0
        UpstreamHandler.max_active_requests = 0
        UpstreamHandler.active_by_authorization = {}
        UpstreamHandler.max_active_by_authorization = {}
        UpstreamHandler.state_lock = threading.Lock()
        UpstreamHandler.hold_event = threading.Event()
        UpstreamHandler.request_started_event = threading.Event()
        UpstreamHandler.two_requests_started_event = threading.Event()
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream_port = self.upstream.server_address[1]
        self.proxy = make_server(
            Settings(
                upstream_url=f"http://127.0.0.1:{upstream_port}",
                max_retries=3,
                base_backoff=0.01,
                max_backoff=0.01,
                jitter=0,
                upstream_timeout=1,
                account_tokens=("token-a", "token-b"),
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

    def test_round_robins_tokens_across_429_retries(self) -> None:
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=b"{}",
            headers={"Authorization": "Bearer test"},
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b'{"ok":true}')
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertEqual(UpstreamHandler.attempts, 4)
        self.assertEqual(
            UpstreamHandler.authorization_headers,
            ["Bearer token-a", "Bearer token-b", "Bearer token-a", "Bearer token-b"],
        )

    def test_rate_limit_retry_waits_before_reusing_limited_token(self) -> None:
        UpstreamHandler.mode = "token_a_once_rate_limited"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=b"{}",
        )

        started = time.monotonic()
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertGreaterEqual(time.monotonic() - started, 0.008)
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')

        self.assertEqual(
            UpstreamHandler.authorization_headers,
            ["Bearer token-a", "Bearer token-b", "Bearer token-a"],
        )

    def test_same_token_never_allows_two_in_flight_upstream_requests(self) -> None:
        single_token_proxy = make_server(
            replace(
                cast(
                    type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass
                ).settings,
                account_tokens=("token-a",),
            ),
            ("127.0.0.1", 0),
        )
        thread = threading.Thread(target=single_token_proxy.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 1)
        self.addCleanup(single_token_proxy.server_close)
        self.addCleanup(single_token_proxy.shutdown)
        UpstreamHandler.mode = "serialized_hold"
        proxy_port = single_token_proxy.server_address[1]

        def request() -> bytes:
            with urllib.request.urlopen(
                urllib.request.Request(
                    f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
                    data=b"{}",
                )
            ) as response:
                return response.read()

        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(request)
            self.assertTrue(UpstreamHandler.request_started_event.wait(timeout=1))
            second = executor.submit(request)
            time.sleep(0.05)
            self.assertFalse(UpstreamHandler.two_requests_started_event.is_set())
            UpstreamHandler.hold_event.set()
            self.assertEqual(first.result(timeout=1), b'{"ok":true}')
            self.assertEqual(second.result(timeout=1), b'{"ok":true}')

        self.assertEqual(
            UpstreamHandler.max_active_by_authorization["Bearer token-a"], 1
        )

    def test_different_tokens_can_run_upstream_in_parallel(self) -> None:
        UpstreamHandler.mode = "parallel_hold"
        proxy_port = self.proxy.server_address[1]

        def request() -> bytes:
            with urllib.request.urlopen(
                urllib.request.Request(
                    f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
                    data=b"{}",
                )
            ) as response:
                return response.read()

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(request) for _ in range(2)]
            self.assertTrue(UpstreamHandler.two_requests_started_event.wait(timeout=1))
            UpstreamHandler.hold_event.set()
            self.assertEqual(
                [future.result(timeout=1) for future in futures], [b'{"ok":true}'] * 2
            )

        self.assertGreaterEqual(UpstreamHandler.max_active_requests, 2)
        self.assertEqual(
            {header for header in UpstreamHandler.authorization_headers},
            {"Bearer token-a", "Bearer token-b"},
        )

    def test_deadline_without_lease_never_reaches_upstream(self) -> None:
        single_token_proxy = make_server(
            Settings(
                upstream_url=(f"http://127.0.0.1:{self.upstream.server_address[1]}"),
                max_retries=3,
                base_backoff=0.01,
                max_backoff=0.01,
                jitter=0,
                upstream_timeout=1,
                account_tokens=("token-a",),
            ),
            ("127.0.0.1", 0),
        )
        thread = threading.Thread(target=single_token_proxy.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 1)
        self.addCleanup(single_token_proxy.server_close)
        self.addCleanup(single_token_proxy.shutdown)
        handler = cast(
            type[SakuraRetryProxyHandler], single_token_proxy.RequestHandlerClass
        )
        handler.settings = self.unsafe_settings(
            upstream_url=f"http://127.0.0.1:{self.upstream.server_address[1]}",
            account_tokens=("token-a",),
            retry_budget=0.02,
            upstream_timeout=0.001,
        )
        handler.token_state = SharedTokenCooldown(handler.settings.account_tokens)
        lease, _ = handler.token_state.acquire(time.monotonic() + 1, lambda: False)
        self.assertIsNotNone(lease)
        self.addCleanup(handler.token_state.release, cast(TokenLease, lease))
        attempts_before = UpstreamHandler.attempts

        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(
                urllib.request.Request(
                    f"http://127.0.0.1:{single_token_proxy.server_address[1]}/v1/chat/completions",
                    data=b"{}",
                    headers={"Authorization": "Bearer caller-secret"},
                )
            )
        error.exception.close()

        self.assertEqual(error.exception.code, 504)
        self.assertEqual(UpstreamHandler.attempts, attempts_before)
        self.assertNotIn("Bearer caller-secret", UpstreamHandler.authorization_headers)

    def test_strips_caller_authorization_when_no_configured_token_exists(self) -> None:
        UpstreamHandler.mode = "success"
        UpstreamHandler.attempts = 0
        UpstreamHandler.attempts_by_body = {}
        UpstreamHandler.request_bodies = []
        UpstreamHandler.authorization_headers = []
        no_token_proxy = make_server(
            Settings(
                upstream_url=(f"http://127.0.0.1:{self.upstream.server_address[1]}"),
                max_retries=3,
                base_backoff=0.01,
                max_backoff=0.01,
                jitter=0,
                upstream_timeout=1,
            ),
            ("127.0.0.1", 0),
        )
        thread = threading.Thread(target=no_token_proxy.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 1)
        self.addCleanup(no_token_proxy.server_close)
        self.addCleanup(no_token_proxy.shutdown)

        with urllib.request.urlopen(
            urllib.request.Request(
                f"http://127.0.0.1:{no_token_proxy.server_address[1]}/v1/chat/completions",
                data=b"{}",
                headers={"Authorization": "Bearer caller-secret"},
            )
        ) as response:
            self.assertEqual(response.read(), b'{"ok":true}')

        self.assertEqual(UpstreamHandler.authorization_headers, [None])

    def test_retries_timeout_once_with_low_reasoning(self) -> None:
        UpstreamHandler.mode = "timeout_then_success"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "max"}).encode(),
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.read(), b'{"ok":true}')
            self.assertEqual(response.headers["X-Sakura-Retry-Count"], "1")
            self.assertEqual(response.headers["X-Sakura-Retry-Reason"], "timeout")
            self.assertEqual(
                response.headers["X-Sakura-Effective-Reasoning-Effort"], "low"
            )
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

    def test_openwebui_mode_injects_retry_status_only_when_enabled(self) -> None:
        UpstreamHandler.mode = "timeout_then_stream"
        proxy_port = self.proxy.server_address[1]

        def request(openwebui_mode: bool) -> tuple[bytes, str | None]:
            UpstreamHandler.attempts = 0
            headers = {"X-OpenWebUI-Mode": "true"} if openwebui_mode else {}
            with urllib.request.urlopen(
                urllib.request.Request(
                    f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
                    data=json.dumps({"reasoning_effort": "high"}).encode(),
                    headers=headers,
                )
            ) as response:
                return response.read(), response.headers.get("Content-Length")

        upstream_event = b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
        standard_body, standard_length = request(False)
        self.assertEqual(standard_body, upstream_event)
        self.assertEqual(standard_length, str(len(upstream_event)))

        openwebui_body, openwebui_length = request(True)
        status_line, streamed_body = openwebui_body.split(b"\n\n", 1)
        status = json.loads(status_line.removeprefix(b"data: "))
        self.assertEqual(
            status,
            {
                "event": {
                    "type": "status",
                    "data": {"description": "Lowで再試行しました", "done": True},
                }
            },
        )
        self.assertEqual(streamed_body, upstream_event)
        self.assertIsNone(openwebui_length)

    def test_retries_timeout_to_configured_limit(self) -> None:
        UpstreamHandler.mode = "always_timeout"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "high"}).encode(),
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        self.assertEqual(error.exception.code, 504)
        self.assertEqual(error.exception.headers["X-Sakura-Retry-Count"], "3")
        error.exception.close()
        self.assertEqual(UpstreamHandler.attempts, 4)

    def test_timeout_retries_none_effort_without_rewriting_it(self) -> None:
        UpstreamHandler.mode = "always_timeout"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=json.dumps({"reasoning_effort": "none"}).encode(),
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()
        self.assertEqual(UpstreamHandler.attempts, 4)
        self.assertEqual(
            [
                json.loads(body)["reasoning_effort"]
                for body in UpstreamHandler.request_bodies
            ],
            ["none"] * 4,
        )

    def test_retries_http_and_stream_provider_errors(self) -> None:
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions", data=b"{}"
        )
        for mode, reason in (
            ("server_error_then_success", "server_error"),
            ("internal_error_then_success", "server_error"),
        ):
            with self.subTest(mode=mode):
                UpstreamHandler.mode = mode
                UpstreamHandler.attempts = 0
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(response.read(), b'{"ok":true}')
                    self.assertEqual(response.headers["X-Sakura-Retry-Count"], "1")
                    self.assertEqual(response.headers["X-Sakura-Retry-Reason"], reason)
                self.assertEqual(UpstreamHandler.attempts, 2)

        UpstreamHandler.mode = "always_internal_error"
        UpstreamHandler.attempts = 0
        handler = cast(type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass)
        handler.settings = self.unsafe_settings(
            max_retries=5,
            base_backoff=0,
            max_backoff=0,
            upstream_timeout=1,
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        self.assertEqual(error.exception.code, 502)
        self.assertEqual(error.exception.headers["X-Sakura-Retry-Count"], "5")
        error.exception.close()
        self.assertEqual(UpstreamHandler.attempts, 6)

    def test_retries_upstream_transport_error(self) -> None:
        handler = cast(type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass)
        original = handler._request_upstream
        calls = 0

        def flaky_request(
            instance: SakuraRetryProxyHandler,
            body: bytes,
            timeout: float,
            deadline: float,
        ) -> tuple[
            http.client.HTTPConnection,
            http.client.HTTPResponse,
            TokenLease | None,
            float,
        ]:
            nonlocal calls
            calls += 1
            if calls == 1:
                raise OSError("temporary transport failure")
            return original(instance, body, timeout, deadline)

        UpstreamHandler.mode = "success"
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.proxy.server_address[1]}/v1/chat/completions",
            data=b"{}",
        )
        with (
            patch.object(handler, "_request_upstream", flaky_request),
            urllib.request.urlopen(request) as response,
        ):
            self.assertEqual(response.read(), b'{"ok":true}')
            self.assertEqual(response.headers["X-Sakura-Retry-Count"], "1")
            self.assertEqual(
                response.headers["X-Sakura-Retry-Reason"], "upstream_error"
            )
        self.assertEqual(calls, 2)

    def test_retry_after_parser(self) -> None:
        self.assertEqual(retry_after_seconds("2"), 2)
        self.assertIsNone(retry_after_seconds("invalid"))
        settings = Settings(jitter=0)
        self.assertEqual(retry_delay_seconds(settings, 0, 2), 10)
        self.assertEqual(retry_delay_seconds(settings, 1, None), 20)
        self.assertEqual(
            [retry_delay_seconds(settings, attempt, None) for attempt in range(5)],
            [10, 20, 40, 80, 120],
        )
        self.assertEqual(retryable_response_reason(409, b""), "server_error")
        self.assertEqual(
            retryable_response_reason(200, b"Internal server error."), "server_error"
        )
        self.assertEqual(
            retryable_response_reason(200, b'{"error":"Internal server error."}'),
            "server_error",
        )
        self.assertIsNone(retryable_response_reason(401, b""))

    def test_retry_budget_stops_before_an_unaffordable_backoff(self) -> None:
        UpstreamHandler.mode = "rate_limit_slow"
        handler = cast(type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass)
        handler.settings = self.unsafe_settings(
            max_backoff=1000,
            retry_budget=300.002,
            upstream_timeout=0.001,
        )
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.proxy.server_address[1]}/v1/chat/completions",
            data=b"{}",
        )

        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()

        self.assertEqual(error.exception.code, 429)
        self.assertEqual(UpstreamHandler.attempts, 1)

    def test_shared_cooldown_waits_until_a_token_is_available(self) -> None:
        state = SharedTokenCooldown(("token-a", "token-b"))
        state.schedule(0, 0.05)
        state.schedule(1, 0.05)

        start = time.monotonic()
        lease, waited = state.acquire(start + 1, lambda: False)
        elapsed = time.monotonic() - start

        self.assertIsNotNone(lease)
        self.assertGreaterEqual(waited, 0.03)
        self.assertGreaterEqual(elapsed, 0.03)

    def test_aggregate_logs_use_token_slots_without_leaking_secrets(self) -> None:
        UpstreamHandler.mode = "token_a_once_rate_limited"
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=b"{}",
        )

        with (
            self.assertLogs("sakura-retry-proxy", level="INFO") as captured,
            urllib.request.urlopen(request) as response,
        ):
            self.assertEqual(response.read(), b'{"ok":true}')

        aggregate_logs = [line for line in captured.output if "correlation=" in line]
        self.assertGreaterEqual(len(aggregate_logs), 2)
        self.assertTrue(
            any(
                all(
                    field in line
                    for field in (
                        "token_slot=",
                        "attempt=",
                        "reason=",
                        "scheduled=",
                        "shared_wait=",
                        "status=",
                    )
                )
                for line in aggregate_logs
            )
        )
        self.assertFalse(
            any("token-a" in line or "token-b" in line for line in captured.output)
        )

    def test_settings_parse_comma_separated_account_tokens(self) -> None:
        with patch.dict(
            os.environ,
            {"SAKURA_AI_ACCOUNT_TOKENS": " token-a,token-b ,, token-c "},
            clear=True,
        ):
            settings = Settings.from_environment()

        self.assertEqual(settings.account_tokens, ("token-a", "token-b", "token-c"))
        self.assertEqual(settings.upstream_url, "https://api.ai.sakura.ad.jp")
        self.assertEqual((settings.max_retries, settings.base_backoff), (5, 10))
        self.assertGreaterEqual(
            settings.retry_budget
            - (settings.max_retries + 1) * settings.upstream_timeout
            - sum(
                min(settings.max_backoff, settings.base_backoff * (2**attempt))
                + settings.jitter
                for attempt in range(settings.max_retries)
            ),
            300,
        )
        with self.assertRaisesRegex(ValueError, "lacks timeout safety margin"):
            replace(settings, retry_budget=1000)

        with (
            patch.dict(os.environ, {}, clear=True),
            self.assertRaisesRegex(ValueError, "must contain at least one token"),
        ):
            Settings.from_environment()

    def test_rejects_negative_content_length_without_reading_a_body(self) -> None:
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.proxy.server_address[1], timeout=1
        )
        self.addCleanup(connection.close)
        connection.putrequest("POST", "/v1/chat/completions")
        connection.putheader("Content-Length", "-1")
        connection.endheaders()

        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        self.assertEqual(
            json.loads(response.read()),
            {"error": {"message": "invalid content length"}},
        )

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
        self.assertEqual(UpstreamHandler.attempts_by_body, {b"first": 1, b"second": 2})


if __name__ == "__main__":
    unittest.main()
