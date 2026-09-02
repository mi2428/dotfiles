"""Serve the internal OpenAI-compatible gateway for Sakura AI Engine.

The proxy replaces caller credentials with round-robin account tokens, preserves streaming,
retries bounded 429 responses, and retries one timeout at low reasoning when the request
explicitly permits that fallback. Open WebUI-only status events require its private header.
"""

from __future__ import annotations

import http.client
import json
import logging
import os
import random
import ssl
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import SplitResult, urlsplit
from uuid import uuid4

LOG = logging.getLogger("sakura-retry-proxy")
SSL_CONTEXT = ssl.create_default_context()
LISTEN_ADDRESS = ("0.0.0.0", 8080)
TIMEOUT_SAFETY_MARGIN_SECONDS = 300.0
MAX_REQUEST_BYTES = 64 * 1024 * 1024
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}
TIMEOUT_STATUSES = {408, 504}
TIMEOUT_RETRY_EFFORTS = {"medium", "high", "max"}
OPENWEBUI_MODE_HEADER = "X-OpenWebUI-Mode"
RETRY_HEADER_NAMES = {
    "x-sakura-retry-count",
    "x-sakura-retry-reason",
    "x-sakura-effective-reasoning-effort",
}
OPENWEBUI_LOW_RETRY_EVENT = (
    "data: "
    + json.dumps(
        {
            "event": {
                "type": "status",
                "data": {"description": "Lowで再試行しました", "done": True},
            }
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    + "\n\n"
).encode()


def retry_after_seconds(value: str | None) -> float | None:
    """Return the delay encoded by a Retry-After value, if valid."""
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except ValueError:
        try:
            return max(0.0, parsedate_to_datetime(value).timestamp() - time.time())
        except (TypeError, ValueError, OverflowError):
            return None


def timeout_retry_body(body: bytes) -> bytes | None:
    """Return one safe timeout retry, unchanged when effort is unspecified."""
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if "reasoning_effort" not in payload:
        return body
    if payload.get("reasoning_effort") not in TIMEOUT_RETRY_EFFORTS:
        return None
    payload["reasoning_effort"] = "low"
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()


def is_timeout_response(status: int, prefix: bytes) -> bool:
    """Recognize HTTP and OpenAI-compatible timeout responses."""
    if status in TIMEOUT_STATUSES:
        return True
    payload = prefix.strip()
    if payload.startswith(b"data:"):
        payload = payload.removeprefix(b"data:").strip()
    try:
        error = json.loads(payload).get("error", {})
    except (AttributeError, json.JSONDecodeError, UnicodeDecodeError):
        return False
    return isinstance(error, dict) and error.get("code") == "timeout"


@dataclass(frozen=True, slots=True)
class Settings:
    """Runtime settings for the internal Sakura gateway."""

    upstream_url: str = "https://api.ai.sakura.ad.jp"
    max_retries: int = 10
    base_backoff: float = 2.0
    max_backoff: float = 120.0
    jitter: float = 1.0
    retry_budget: float = 1200.0
    upstream_timeout: float = 420.0
    account_tokens: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if self.upstream_timeout <= 0 or self.retry_budget <= 0:
            raise ValueError("Sakura timeout settings must be positive")
        if (
            self.retry_budget - 2 * self.upstream_timeout
            < TIMEOUT_SAFETY_MARGIN_SECONDS
        ):
            raise ValueError("Sakura retry budget lacks timeout safety margin")

    @classmethod
    def from_environment(cls) -> Settings:
        """Load overrides from the container environment."""
        defaults = cls()
        account_tokens = tuple(
            token.strip()
            for token in os.getenv("SAKURA_AI_ACCOUNT_TOKENS", "").split(",")
            if token.strip()
        )
        if not account_tokens:
            raise ValueError("SAKURA_AI_ACCOUNT_TOKENS must contain at least one token")
        return cls(
            upstream_url=os.getenv("SAKURA_UPSTREAM_URL", defaults.upstream_url),
            max_retries=int(os.getenv("SAKURA_RETRY_MAX", defaults.max_retries)),
            base_backoff=float(
                os.getenv("SAKURA_RETRY_BASE_SECONDS", defaults.base_backoff)
            ),
            max_backoff=float(
                os.getenv("SAKURA_RETRY_MAX_SECONDS", defaults.max_backoff)
            ),
            jitter=float(os.getenv("SAKURA_RETRY_JITTER_SECONDS", defaults.jitter)),
            retry_budget=float(
                os.getenv("SAKURA_RETRY_BUDGET_SECONDS", defaults.retry_budget)
            ),
            upstream_timeout=float(
                os.getenv("SAKURA_UPSTREAM_TIMEOUT_SECONDS", defaults.upstream_timeout)
            ),
            account_tokens=account_tokens,
        )


def retry_delay_seconds(
    settings: Settings, attempt: int, retry_after: float | None
) -> float:
    """Return capped exponential or provider-directed backoff with jitter."""

    delay = (
        retry_after if retry_after is not None else settings.base_backoff * (2**attempt)
    )
    return min(settings.max_backoff, delay) + random.uniform(0.0, settings.jitter)


@dataclass(frozen=True, slots=True)
class TokenLease:
    slot: int
    token: str


class SharedTokenCooldown:
    """Thread-safe token rotation with shared 429 cooldowns."""

    def __init__(self, tokens: tuple[str, ...]) -> None:
        self._tokens = tokens
        self._next_index = 0
        self._cooldown_until = [0.0] * len(tokens)
        self._in_flight = [False] * len(tokens)
        self._condition = threading.Condition()

    def acquire(
        self, deadline: float, is_cancelled: Callable[[], bool]
    ) -> tuple[TokenLease | None, float]:
        if not self._tokens:
            return None, 0.0
        waited = 0.0
        with self._condition:
            while True:
                if is_cancelled():
                    return None, waited
                now = time.monotonic()
                for offset in range(len(self._tokens)):
                    slot = (self._next_index + offset) % len(self._tokens)
                    if not self._in_flight[slot] and self._cooldown_until[slot] <= now:
                        self._in_flight[slot] = True
                        self._next_index = (slot + 1) % len(self._tokens)
                        return TokenLease(slot, self._tokens[slot]), waited
                remaining = deadline - now
                if remaining <= 0:
                    return None, waited
                available_slots = [
                    slot for slot, busy in enumerate(self._in_flight) if not busy
                ]
                shared_wait = (
                    min(self._cooldown_until[slot] for slot in available_slots) - now
                    if available_slots
                    else remaining
                )
                pause = min(max(0.0, shared_wait), remaining, 0.1)
                if pause <= 0:
                    continue
                start = time.monotonic()
                self._condition.wait(timeout=pause)
                waited += time.monotonic() - start

    def release(self, lease: TokenLease) -> None:
        with self._condition:
            if self._in_flight[lease.slot]:
                self._in_flight[lease.slot] = False
                self._condition.notify_all()

    def schedule(self, slot: int, delay: float) -> float:
        with self._condition:
            scheduled = self._schedule_unlocked(slot, delay)
            self._condition.notify_all()
            return scheduled

    def schedule_and_release(self, lease: TokenLease, delay: float) -> float:
        with self._condition:
            scheduled = self._schedule_unlocked(lease.slot, delay)
            self._in_flight[lease.slot] = False
            self._condition.notify_all()
            return scheduled

    def _schedule_unlocked(self, slot: int, delay: float) -> float:
        self._cooldown_until[slot] = max(
            self._cooldown_until[slot], time.monotonic() + max(0.0, delay)
        )
        return max(0.0, self._cooldown_until[slot] - time.monotonic())


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    """Forward OpenAI-compatible requests and retry recoverable failures."""

    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)
    token_state = SharedTokenCooldown(settings.account_tokens)

    def do_GET(self) -> None:
        """Handle health checks and upstream GET requests."""
        self._proxy()

    do_POST = do_GET

    def log_message(self, format: str, *args: object) -> None:
        """Log requests without flooding logs with health checks."""
        if self.path != "/health":
            LOG.info("%s - %s", self.client_address[0], format % args)

    def _proxy(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        body = self._read_body()
        if body is None:
            return

        request_body = body
        rate_limit_attempt = 0
        upstream_attempt = 0
        timeout_retried = False
        effective_reasoning_effort = None
        retry_deadline = time.monotonic() + self.settings.retry_budget
        openwebui_mode = (
            self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true"
        )
        correlation_id = uuid4().hex[:12]
        while True:
            lease: TokenLease | None = None
            remaining = retry_deadline - time.monotonic()
            if remaining <= 0:
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None,
                    attempt=upstream_attempt,
                    reason="budget",
                    scheduled=0.0,
                    shared_wait=0.0,
                    status=504,
                )
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return
            try:
                upstream_attempt += 1
                connection, response, lease, shared_wait = self._request_upstream(
                    request_body,
                    min(self.settings.upstream_timeout, remaining),
                    retry_deadline,
                )
            except TimeoutError:
                fallback = None if timeout_retried else timeout_retry_body(request_body)
                if fallback is not None and time.monotonic() < retry_deadline:
                    self._log_event(
                        correlation_id=correlation_id,
                        token_slot=None if lease is None else lease.slot,
                        attempt=upstream_attempt,
                        reason="timeout",
                        scheduled=0.0,
                        shared_wait=0.0,
                        status="retry",
                    )
                    if fallback != request_body:
                        effective_reasoning_effort = "low"
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None if lease is None else lease.slot,
                    attempt=upstream_attempt,
                    reason="timeout",
                    scheduled=0.0,
                    shared_wait=0.0,
                    status=504,
                )
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return
            except BrokenPipeError:
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None if lease is None else lease.slot,
                    attempt=upstream_attempt,
                    reason="client_disconnect",
                    scheduled=0.0,
                    shared_wait=0.0,
                    status="cancelled",
                )
                self.close_connection = True
                return
            except (OSError, http.client.HTTPException):
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None if lease is None else lease.slot,
                    attempt=upstream_attempt,
                    reason="upstream_error",
                    scheduled=0.0,
                    shared_wait=0.0,
                    status=502,
                )
                self._send_json(
                    502,
                    {"error": {"message": "upstream unavailable"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return
            rate_limited = False
            token_slot = None if lease is None else lease.slot
            if (
                response.status == 429
                and rate_limit_attempt < self.settings.max_retries
            ):
                rate_limited = True
                retry_after = retry_after_seconds(response.getheader("Retry-After"))
                delay = retry_delay_seconds(
                    self.settings, rate_limit_attempt, retry_after
                )
                scheduled = (
                    type(self).token_state.schedule_and_release(lease, delay)
                    if lease is not None
                    else delay
                )
                lease = None
                if delay < retry_deadline - time.monotonic():
                    response.read()
                    connection.close()
                    rate_limit_attempt += 1
                    self._log_event(
                        correlation_id=correlation_id,
                        token_slot=token_slot,
                        attempt=upstream_attempt,
                        reason="rate_limit",
                        scheduled=scheduled,
                        shared_wait=shared_wait,
                        status=429,
                    )
                    continue
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=token_slot,
                    attempt=upstream_attempt,
                    reason="rate_limit",
                    scheduled=scheduled,
                    shared_wait=shared_wait,
                    status=429,
                )

            try:
                remaining = retry_deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("retry budget exhausted")
                if connection.sock is not None:
                    connection.sock.settimeout(
                        min(self.settings.upstream_timeout, remaining)
                    )
                prefix = response.readline(64 * 1024)
            except TimeoutError:
                response.close()
                connection.close()
                if lease is not None:
                    type(self).token_state.release(lease)
                    lease = None
                fallback = None if timeout_retried else timeout_retry_body(request_body)
                if fallback is not None and time.monotonic() < retry_deadline:
                    self._log_event(
                        correlation_id=correlation_id,
                        token_slot=token_slot,
                        attempt=upstream_attempt,
                        reason="timeout",
                        scheduled=0.0,
                        shared_wait=shared_wait,
                        status="retry",
                    )
                    if fallback != request_body:
                        effective_reasoning_effort = "low"
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=token_slot,
                    attempt=upstream_attempt,
                    reason="timeout",
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status=504,
                )
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return

            fallback = None
            if is_timeout_response(response.status, prefix) and not timeout_retried:
                fallback = timeout_retry_body(request_body)
            if fallback is not None and time.monotonic() < retry_deadline:
                response.close()
                connection.close()
                if lease is not None:
                    type(self).token_state.release(lease)
                    lease = None
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=token_slot,
                    attempt=upstream_attempt,
                    reason="timeout",
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status="retry",
                )
                if fallback != request_body:
                    effective_reasoning_effort = "low"
                request_body = fallback
                timeout_retried = True
                rate_limit_attempt = 0
                continue

            self._log_event(
                correlation_id=correlation_id,
                token_slot=token_slot,
                attempt=upstream_attempt,
                reason="rate_limit" if rate_limited else "response",
                scheduled=0.0,
                shared_wait=shared_wait,
                status=response.status,
            )

            self._stream(
                connection,
                response,
                prefix,
                lease,
                self._retry_headers(timeout_retried, effective_reasoning_effort),
                openwebui_mode and effective_reasoning_effort == "low",
            )
            return

    def _read_body(self) -> bytes | None:
        if self.headers.get("Transfer-Encoding"):
            self._send_json(501, {"error": {"message": "chunked request unsupported"}})
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": {"message": "invalid content length"}})
            return None
        if length < 0:
            self._send_json(400, {"error": {"message": "invalid content length"}})
            return None
        if length > MAX_REQUEST_BYTES:
            self._send_json(413, {"error": {"message": "request body too large"}})
            return None
        return self.rfile.read(length) if length else b""

    def _request_upstream(
        self, body: bytes, timeout: float, deadline: float
    ) -> tuple[
        http.client.HTTPConnection,
        http.client.HTTPResponse,
        TokenLease | None,
        float,
    ]:
        host = self.upstream.hostname
        if host is None:
            raise ValueError("upstream host is required")
        if self.upstream.scheme == "https":
            connection: http.client.HTTPConnection = http.client.HTTPSConnection(
                host,
                self.upstream.port,
                timeout=timeout,
                context=SSL_CONTEXT,
            )
        else:
            connection = http.client.HTTPConnection(
                host, self.upstream.port, timeout=timeout
            )
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
            and name.lower()
            not in {
                "authorization",
                "host",
                "content-length",
                OPENWEBUI_MODE_HEADER.casefold(),
            }
        }
        headers["Host"] = self.upstream.netloc
        if self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true":
            headers["Accept-Encoding"] = "identity"
        lease, shared_wait = type(self).token_state.acquire(
            deadline, self._client_disconnected
        )
        if self._client_disconnected():
            if lease is not None:
                type(self).token_state.release(lease)
            connection.close()
            raise BrokenPipeError("client disconnected")
        if lease is None and self.settings.account_tokens:
            connection.close()
            raise TimeoutError("token lease unavailable")
        if lease is not None:
            headers["Authorization"] = f"Bearer {lease.token}"
        if body:
            headers["Content-Length"] = str(len(body))
        try:
            connection.request(
                self.command,
                f"{self.upstream.path.rstrip('/')}{self.path}",
                body,
                headers,
            )
            return connection, connection.getresponse(), lease, shared_wait
        except Exception:
            if lease is not None:
                type(self).token_state.release(lease)
            connection.close()
            raise

    def _client_disconnected(self) -> bool:
        try:
            if getattr(self.wfile, "closed", False):
                return True
            return self.connection is not None and self.connection.fileno() < 0
        except OSError:
            return True

    def _log_event(
        self,
        *,
        correlation_id: str,
        token_slot: int | None,
        attempt: int,
        reason: str,
        scheduled: float,
        shared_wait: float,
        status: int | str,
    ) -> None:
        LOG.info(
            "correlation=%s token_slot=%s attempt=%d reason=%s scheduled=%.3f shared_wait=%.3f status=%s",
            correlation_id,
            "-" if token_slot is None else token_slot,
            attempt,
            reason,
            scheduled,
            shared_wait,
            status,
        )

    @staticmethod
    def _retry_headers(retried: bool, effective_effort: str | None) -> dict[str, str]:
        if not retried:
            return {}
        headers = {
            "X-Sakura-Retry-Count": "1",
            "X-Sakura-Retry-Reason": "timeout",
        }
        if effective_effort:
            headers["X-Sakura-Effective-Reasoning-Effort"] = effective_effort
        return headers

    def _stream(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
        prefix: bytes = b"",
        lease: TokenLease | None = None,
        extra_headers: dict[str, str] | None = None,
        openwebui_retry_status: bool = False,
    ) -> None:
        extra_headers = extra_headers or {}
        status_event = (
            OPENWEBUI_LOW_RETRY_EVENT
            if openwebui_retry_status
            and response.getheader("Content-Type", "")
            .casefold()
            .startswith("text/event-stream")
            else b""
        )
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            lower_name = name.lower()
            if (
                lower_name not in HOP_BY_HOP_HEADERS
                and lower_name not in RETRY_HEADER_NAMES
                and not (status_event and lower_name == "content-length")
            ):
                self.send_header(name, value)
        for name, value in extra_headers.items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            if status_event:
                self.wfile.write(status_event)
                self.wfile.flush()
            if prefix:
                self.wfile.write(prefix)
                self.wfile.flush()
            while chunk := response.read(64 * 1024):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            if lease is not None:
                type(self).token_state.release(lease)
            response.close()
            connection.close()
            self.close_connection = True

    def _send_json(
        self,
        status: int,
        payload: dict[str, object],
        headers: dict[str, str] | None = None,
    ) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True


def make_server(
    settings: Settings, address: tuple[str, int] = LISTEN_ADDRESS
) -> ThreadingHTTPServer:
    """Build a threaded gateway bound according to settings."""
    upstream = urlsplit(settings.upstream_url)
    if upstream.scheme not in {"http", "https"} or not upstream.hostname:
        raise ValueError("SAKURA_UPSTREAM_URL must be an absolute HTTP(S) URL")
    handler = type(
        "ConfiguredSakuraRetryProxyHandler",
        (SakuraRetryProxyHandler,),
        {
            "settings": settings,
            "upstream": upstream,
            "token_state": SharedTokenCooldown(settings.account_tokens),
        },
    )
    return ThreadingHTTPServer(address, handler)


def main() -> None:
    """Run the gateway until the container stops."""
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = Settings.from_environment()
    server = make_server(settings)
    LOG.info("Listening on %s:%d", *server.server_address)
    server.serve_forever()


if __name__ == "__main__":
    main()
