from __future__ import annotations

import http.client
import json
import socket
import sqlite3
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar, cast
from unittest.mock import patch

from sakura_retry_proxy import (
    RESEARCH_MAX_DEADLINE_MS,
    RESEARCH_MAX_REQUEST_BYTES,
    RESEARCH_MAX_RESPONSE_BYTES,
    RESEARCH_PATH,
    SakuraRetryProxyHandler,
    Settings,
    SharedTokenCooldown,
    TokenLease,
    make_server,
)


class ResearchUpstreamHandler(BaseHTTPRequestHandler):
    attempts = 0
    mode = "success"
    bodies: ClassVar[list[bytes]] = []
    authorizations: ClassVar[list[str | None]] = []
    started = threading.Event()

    def do_POST(self) -> None:
        type(self).attempts += 1
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        type(self).bodies.append(body)
        type(self).authorizations.append(self.headers.get("Authorization"))
        type(self).started.set()
        if self.mode == "normal_retry" and self.attempts == 1:
            self._send(503, b"{}")
            return
        if self.mode == "failure":
            self._send(503, b"{}")
            return
        if self.mode == "rate_limit":
            self._send(429, b"", {"Retry-After": "1"})
            return
        if self.mode == "oversize":
            try:
                self._send(200, b"x", content_length=RESEARCH_MAX_RESPONSE_BYTES + 1)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if self.mode == "drip":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            try:
                for _ in range(100):
                    self.wfile.write(b"x")
                    self.wfile.flush()
                    time.sleep(0.01)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if self.mode == "incomplete":
            self._send(200, b'data: {"choices":[]}\n\n')
            return
        self._send(200, b'data: {"choices":[]}\n\ndata: [DONE]\n\n')

    def _send(
        self,
        status: int,
        body: bytes,
        headers: dict[str, str] | None = None,
        *,
        content_length: int | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header(
            "Content-Length",
            str(len(body) if content_length is None else content_length),
        )
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


def valid_body() -> bytes:
    return json.dumps(
        {
            "max_tokens": 16_384,
            "messages": [
                {"content": "system", "role": "system"},
                {"content": "user", "role": "user"},
            ],
            "model": "public-model",
            "stream": True,
            "stream_options": {"include_usage": True},
        },
        separators=(",", ":"),
        sort_keys=True,
    ).encode()


class ResearchProxyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = str(Path(self.tmpdir.name) / "shared.db")
        ResearchUpstreamHandler.attempts = 0
        ResearchUpstreamHandler.mode = "success"
        ResearchUpstreamHandler.bodies = []
        ResearchUpstreamHandler.authorizations = []
        ResearchUpstreamHandler.started = threading.Event()
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), ResearchUpstreamHandler)
        self.proxy = make_server(
            Settings(
                upstream_url=f"http://127.0.0.1:{self.upstream.server_address[1]}",
                base_backoff=0.01,
                max_backoff=1,
                jitter=0,
                account_tokens=("account-a",),
                account_ids=("account-public-a",),
                account_db_path=self.db_path,
                research_api_key="internal-key",
            ),
            ("127.0.0.1", 0),
        )
        self.handler = cast(
            type[SakuraRetryProxyHandler], self.proxy.RequestHandlerClass
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
            thread.join(timeout=2)
        self.tmpdir.cleanup()

    def research_headers(self, seconds: float = 2) -> dict[str, str]:
        return {
            "Authorization": "Bearer internal-key",
            "Content-Type": "application/json",
            "X-Sakura-Attempt-Id": "attempt-1",
            "X-Sakura-Deadline-Unix-Ms": str(int((time.time() + seconds) * 1000)),
        }

    def request(
        self,
        path: str = RESEARCH_PATH,
        *,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
        proxy: ThreadingHTTPServer | None = None,
    ) -> tuple[int, dict[str, str], bytes]:
        connection = http.client.HTTPConnection(
            "127.0.0.1", (proxy or self.proxy).server_address[1], timeout=3
        )
        self.addCleanup(connection.close)
        connection.request(
            "POST",
            path,
            valid_body() if body is None else body,
            self.research_headers() if headers is None else headers,
        )
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()

    def raw_request(
        self,
        headers: dict[str, str],
        *,
        body: bytes | None = None,
        suffix: bytes = b"",
    ) -> bytes:
        connection = socket.create_connection(
            ("127.0.0.1", self.proxy.server_address[1])
        )
        connection.settimeout(1)
        payload = valid_body() if body is None else body
        request = [f"POST {RESEARCH_PATH} HTTP/1.1", "Host: localhost"]
        request.extend(f"{name}: {value}" for name, value in headers.items())
        request.extend([f"Content-Length: {len(payload)}", "", ""])
        connection.sendall("\r\n".join(request).encode() + payload + suffix)
        chunks = bytearray()
        try:
            while chunk := connection.recv(64 * 1024):
                chunks.extend(chunk)
        except (TimeoutError, OSError):
            pass
        finally:
            connection.close()
        return bytes(chunks)

    def account_state(
        self, handler: type[SakuraRetryProxyHandler] | None = None
    ) -> str:
        state = (handler or self.handler).token_state
        deadline = time.monotonic() + 0.5
        while time.monotonic() < deadline:
            row = state.state("account-public-a")
            if row is not None and row["state"] not in {"leased", "send_intent"}:
                return str(row["state"])
            time.sleep(0.005)
        row = state.state("account-public-a")
        if row is None:
            raise AssertionError("account state disappeared")
        return str(row["state"])

    def test_invalid_auth_deadline_headers_and_body_never_send(self) -> None:
        self.assertEqual(RESEARCH_MAX_DEADLINE_MS, 360_000)
        cases = [
            {"headers": {}},
            {"headers": {**self.research_headers(), "Authorization": "Bearer wrong"}},
            {"headers": {**self.research_headers(), "Authorization": "Bearer é"}},
            {
                "headers": {
                    **self.research_headers(),
                    "X-Sakura-Deadline-Unix-Ms": "invalid",
                }
            },
            {
                "headers": {
                    **self.research_headers(),
                    "X-Sakura-Attempt-Id": "bad value",
                }
            },
            {"headers": self.research_headers(RESEARCH_MAX_DEADLINE_MS / 1000 + 1)},
            {"body": b"{}"},
            {"body": b"x" * (RESEARCH_MAX_REQUEST_BYTES + 1)},
        ]
        for case in cases:
            with self.subTest(case=case):
                status, _headers, _body = self.request(**case)
                self.assertIn(status, {400, 401})
        self.assertEqual(ResearchUpstreamHandler.attempts, 0)

        pipelined = self.raw_request(
            {**self.research_headers(), "Authorization": "Bearer wrong"},
            suffix=b"GET /must-not-be-parsed HTTP/1.1\r\nHost: localhost\r\n\r\n",
        )
        self.assertEqual(pipelined.count(b"HTTP/1.1"), 1)
        self.assertIn(b"Connection: close", pipelined)

    def test_research_failure_sends_once_while_normal_chat_still_retries(self) -> None:
        ResearchUpstreamHandler.mode = "failure"
        status, headers, _body = self.request()
        self.assertEqual(status, 503)
        self.assertEqual(headers["X-Sakura-Attempt-Id"], "attempt-1")
        self.assertEqual(headers["X-Sakura-Upstream-Send"], "sent")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)

        ResearchUpstreamHandler.mode = "normal_retry"
        ResearchUpstreamHandler.attempts = 0
        status, _headers, body = self.request(
            "/v1/chat/completions", body=b"{}", headers={}
        )
        self.assertEqual(
            (status, body), (200, b'data: {"choices":[]}\n\ndata: [DONE]\n\n')
        )
        self.assertEqual(ResearchUpstreamHandler.attempts, 2)

    def test_success_releases_and_uses_account_credential(self) -> None:
        status, _headers, _body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        self.assertEqual(ResearchUpstreamHandler.bodies, [valid_body()])
        self.assertEqual(ResearchUpstreamHandler.authorizations, ["Bearer account-a"])
        lease, _waited = self.handler.token_state.acquire(
            time.monotonic() + 0.1, lambda: False
        )
        self.assertIsNotNone(lease)
        self.handler.token_state.release(cast(TokenLease, lease))

    def test_rate_limit_has_no_retry_and_shares_cooldown(self) -> None:
        ResearchUpstreamHandler.mode = "rate_limit"
        status, _headers, _body = self.request()
        self.assertEqual(status, 429)
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        self.assertEqual(self.account_state(), "cooldown")
        lease, _waited = self.handler.token_state.acquire(
            time.monotonic() + 0.02, lambda: False
        )
        self.assertIsNone(lease)

    def test_oversize_response_is_unknown_and_quarantines_account(self) -> None:
        ResearchUpstreamHandler.mode = "oversize"
        status, headers, _body = self.request()
        self.assertEqual(status, 502)
        self.assertEqual(headers["X-Sakura-Upstream-Send"], "unknown")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        self.assertEqual(self.account_state(), "unknown")

    def test_connect_failure_is_not_sent_and_releases_account(self) -> None:
        unused = socket.socket()
        unused.bind(("127.0.0.1", 0))
        unused_port = unused.getsockname()[1]
        unused.close()
        proxy = make_server(
            Settings(
                upstream_url=f"http://127.0.0.1:{unused_port}",
                account_tokens=("account-a",),
                account_ids=("account-public-a",),
                account_db_path=str(Path(self.tmpdir.name) / "connect.db"),
                research_api_key="internal-key",
            ),
            ("127.0.0.1", 0),
        )
        handler = cast(type[SakuraRetryProxyHandler], proxy.RequestHandlerClass)
        thread = threading.Thread(target=proxy.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 2)
        self.addCleanup(proxy.server_close)
        self.addCleanup(proxy.shutdown)
        status, headers, _body = self.request(proxy=proxy)
        self.assertEqual(status, 502)
        self.assertEqual(headers["X-Sakura-Upstream-Send"], "not-sent")
        self.assertEqual(self.account_state(handler), "available")
        self.assertLessEqual(handler.token_state._cooldown_until[0], time.monotonic())

    def test_delayed_connect_cannot_send_or_reconnect_after_deadline(self) -> None:
        original_connect = http.client.HTTPConnection.connect

        def delayed_connect(connection: http.client.HTTPConnection) -> None:
            time.sleep(0.12)
            original_connect(connection)

        with patch.object(http.client.HTTPConnection, "connect", delayed_connect):
            self.raw_request(self.research_headers(0.05))
        time.sleep(0.2)
        self.assertEqual(ResearchUpstreamHandler.attempts, 0)
        self.assertEqual(self.handler.token_state._in_flight, [False])

    def test_absolute_deadline_stops_continuous_drip_and_quarantines(self) -> None:
        ResearchUpstreamHandler.mode = "drip"
        headers = self.research_headers(0.08)
        started = time.monotonic()
        response = self.raw_request(headers)
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(response.count(b"HTTP/1.1"), 1)
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        time.sleep(0.05)
        self.assertEqual(self.account_state(), "unknown")

    def test_clean_2xx_eof_without_done_quarantines_account(self) -> None:
        ResearchUpstreamHandler.mode = "incomplete"
        status, headers, _body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(headers["X-Sakura-Upstream-Send"], "sent")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        self.assertEqual(self.account_state(), "unknown")

    def test_shared_busy_lease_expires_queue_without_upstream_send(self) -> None:
        lease, _waited = self.handler.token_state.acquire(
            time.monotonic() + 1, lambda: False
        )
        self.assertIsNotNone(lease)
        headers = self.research_headers(0.08)
        try:
            self.request(headers=headers)
        except (http.client.HTTPException, OSError):
            pass
        self.assertEqual(ResearchUpstreamHandler.attempts, 0)
        self.assertEqual(self.handler.token_state._in_flight, [True])
        self.handler.token_state.release(cast(TokenLease, lease))

    def test_client_close_after_send_releases_into_quarantine(self) -> None:
        ResearchUpstreamHandler.mode = "drip"
        connection = socket.create_connection(
            ("127.0.0.1", self.proxy.server_address[1])
        )
        body = valid_body()
        headers = self.research_headers(0.2)
        request = [f"POST {RESEARCH_PATH} HTTP/1.1", "Host: localhost"]
        request.extend(f"{name}: {value}" for name, value in headers.items())
        request.extend([f"Content-Length: {len(body)}", "", ""])
        connection.sendall("\r\n".join(request).encode() + body)
        self.assertTrue(ResearchUpstreamHandler.started.wait(timeout=1))
        connection.close()
        time.sleep(0.1)
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        self.assertEqual(self.account_state(), "unknown")

    def test_same_research_attempt_is_sent_at_most_once_concurrently_and_after_completion(
        self,
    ) -> None:
        ResearchUpstreamHandler.mode = "drip"
        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(self.request)
            self.assertTrue(ResearchUpstreamHandler.started.wait(timeout=1))
            duplicate_status, duplicate_headers, _ = self.request()
            first.result(timeout=3)
        self.assertEqual(duplicate_status, 409)
        self.assertEqual(duplicate_headers["X-Sakura-Upstream-Send"], "not-sent")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)

    def test_successful_research_attempt_id_cannot_be_replayed(self) -> None:
        first_status, _first_headers, _ = self.request()
        replay_status, replay_headers, _ = self.request()
        self.assertEqual(first_status, 200)
        self.assertEqual(replay_status, 409)
        self.assertEqual(replay_headers["X-Sakura-Upstream-Send"], "not-sent")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)
        replay_status, replay_headers, _ = self.request()
        self.assertEqual(replay_status, 409)
        self.assertEqual(replay_headers["X-Sakura-Upstream-Send"], "not-sent")
        self.assertEqual(ResearchUpstreamHandler.attempts, 1)

    def test_failed_sql_admission_rolls_back_and_does_not_poison_normal_acquire(
        self,
    ) -> None:
        path = str(Path(self.tmpdir.name) / "sql-failure.db")
        state = SharedTokenCooldown(("secret",), ("stable",), path)
        self.addCleanup(state.close)
        state._db.execute(
            "CREATE TRIGGER reject_test_lease BEFORE UPDATE OF lease_id ON account_admissions "
            "WHEN NEW.lease_id = 'sql-fail' BEGIN SELECT RAISE(ABORT, 'test failure'); END"
        )
        state._db.commit()
        with self.assertRaises(sqlite3.IntegrityError):
            state.acquire(
                time.monotonic() + 0.1,
                lambda: False,
                lease_id="sql-fail",
                purpose="research",
            )
        state._db.execute("DROP TRIGGER reject_test_lease")
        state._db.commit()
        lease, _ = state.acquire(time.monotonic() + 0.1, lambda: False)
        self.assertIsNotNone(lease)
        state.release(cast(TokenLease, lease))

    def test_durable_unknown_survives_restart_and_token_reordering_without_secret_storage(
        self,
    ) -> None:
        path = str(Path(self.tmpdir.name) / "restart.db")
        first = SharedTokenCooldown(
            ("secret-token-a", "secret-token-b"),
            ("stable-a", "stable-b"),
            path,
        )
        lease, _ = first.acquire(
            time.monotonic() + 1,
            lambda: False,
            lease_id="research-attempt-a",
            purpose="research",
        )
        self.assertIsNotNone(lease)
        first.mark_send_intent(cast(TokenLease, lease))
        first.mark_unknown(cast(TokenLease, lease))
        first.close()

        reordered = SharedTokenCooldown(
            ("secret-token-b", "secret-token-a"),
            ("stable-b", "stable-a"),
            path,
        )
        self.addCleanup(reordered.close)
        held = reordered.state("stable-a")
        if held is None:
            raise AssertionError("durable account disappeared")
        self.assertEqual(
            (held["state"], held["lease_id"]), ("unknown", "research-attempt-a")
        )
        available, _ = reordered.acquire(time.monotonic() + 0.1, lambda: False)
        if available is None:
            raise AssertionError("available account was not acquired")
        self.assertEqual(
            (available.account_id, available.token), ("stable-b", "secret-token-b")
        )
        reordered.release(available)
        self.assertNotIn(b"secret-token-a", Path(path).read_bytes())
        with self.assertRaisesRegex(ValueError, "omit an unresolved"):
            SharedTokenCooldown(("secret-token-b",), ("stable-b",), path)

    def test_restart_converts_send_intent_to_unknown_and_never_expires_it(self) -> None:
        path = str(Path(self.tmpdir.name) / "send-intent.db")
        first = SharedTokenCooldown(("secret",), ("stable",), path)
        lease, _ = first.acquire(time.monotonic() + 1, lambda: False)
        self.assertIsNotNone(lease)
        first.mark_send_intent(cast(TokenLease, lease))
        first.close()
        restarted = SharedTokenCooldown(("secret",), ("stable",), path)
        self.addCleanup(restarted.close)
        restarted_row = restarted.state("stable")
        if restarted_row is None:
            raise AssertionError("durable account disappeared")
        self.assertEqual(restarted_row["state"], "unknown")
        unavailable, _ = restarted.acquire(time.monotonic() + 0.02, lambda: False)
        self.assertIsNone(unavailable)


if __name__ == "__main__":
    unittest.main(verbosity=2)
