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
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import SplitResult, urlsplit

LOG = logging.getLogger("sakura-retry-proxy")
SSL_CONTEXT = ssl.create_default_context()
LISTEN_ADDRESS = ("0.0.0.0", 8080)
UPSTREAM_TIMEOUT = 7200.0
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
    account_tokens: tuple[str, ...] = ()

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


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    """Forward OpenAI-compatible requests and retry recoverable failures."""

    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)
    token_index = 0
    token_lock = threading.Lock()

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
        timeout_retried = False
        effective_reasoning_effort = None
        openwebui_mode = (
            self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true"
        )
        while True:
            try:
                connection, response = self._request_upstream(request_body)
            except TimeoutError as error:
                fallback = None if timeout_retried else timeout_retry_body(request_body)
                if fallback is not None:
                    LOG.warning("Upstream request timed out; retrying once")
                    if fallback != request_body:
                        effective_reasoning_effort = "low"
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                LOG.warning("Upstream request timed out: %s", error)
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return
            except (OSError, http.client.HTTPException) as error:
                LOG.warning("Upstream request failed: %s", error)
                self._send_json(
                    502,
                    {"error": {"message": "upstream unavailable"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return
            if (
                response.status == 429
                and rate_limit_attempt < self.settings.max_retries
            ):
                retry_after = retry_after_seconds(response.getheader("Retry-After"))
                response.read()
                connection.close()
                delay = retry_delay_seconds(
                    self.settings, rate_limit_attempt, retry_after
                )
                rate_limit_attempt += 1
                LOG.warning(
                    "Upstream returned 429; retrying in %.1fs (%d/%d)",
                    delay,
                    rate_limit_attempt,
                    self.settings.max_retries,
                )
                time.sleep(delay)
                continue

            try:
                prefix = response.readline(64 * 1024)
            except TimeoutError as error:
                response.close()
                connection.close()
                fallback = None if timeout_retried else timeout_retry_body(request_body)
                if fallback is not None:
                    LOG.warning("Upstream response timed out; retrying once")
                    if fallback != request_body:
                        effective_reasoning_effort = "low"
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                LOG.warning("Upstream response timed out: %s", error)
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(timeout_retried, effective_reasoning_effort),
                )
                return

            fallback = None
            if is_timeout_response(response.status, prefix) and not timeout_retried:
                fallback = timeout_retry_body(request_body)
            if fallback is not None:
                response.close()
                connection.close()
                LOG.warning("Upstream returned a timeout; retrying once")
                if fallback != request_body:
                    effective_reasoning_effort = "low"
                request_body = fallback
                timeout_retried = True
                rate_limit_attempt = 0
                continue

            self._stream(
                connection,
                response,
                prefix,
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
        self, body: bytes
    ) -> tuple[http.client.HTTPConnection, http.client.HTTPResponse]:
        host = self.upstream.hostname
        if host is None:
            raise ValueError("upstream host is required")
        if self.upstream.scheme == "https":
            connection: http.client.HTTPConnection = http.client.HTTPSConnection(
                host,
                self.upstream.port,
                timeout=UPSTREAM_TIMEOUT,
                context=SSL_CONTEXT,
            )
        else:
            connection = http.client.HTTPConnection(
                host, self.upstream.port, timeout=UPSTREAM_TIMEOUT
            )
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
            and name.lower()
            not in {"host", "content-length", OPENWEBUI_MODE_HEADER.casefold()}
        }
        headers["Host"] = self.upstream.netloc
        if self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true":
            headers["Accept-Encoding"] = "identity"
        if token := self._next_account_token():
            headers["Authorization"] = f"Bearer {token}"
        if body:
            headers["Content-Length"] = str(len(body))
        try:
            connection.request(
                self.command,
                f"{self.upstream.path.rstrip('/')}{self.path}",
                body,
                headers,
            )
            return connection, connection.getresponse()
        except Exception:
            connection.close()
            raise

    def _next_account_token(self) -> str | None:
        tokens = self.settings.account_tokens
        if not tokens:
            return None
        handler = type(self)
        with handler.token_lock:
            token = tokens[handler.token_index]
            handler.token_index = (handler.token_index + 1) % len(tokens)
        return token

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
            "token_index": 0,
            "token_lock": threading.Lock(),
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
