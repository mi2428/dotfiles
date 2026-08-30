"""Stream Sakura AI Engine responses and retry recoverable failures."""

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


def low_reasoning_body(body: bytes) -> bytes | None:
    """Return a copy downgraded to low reasoning when retrying is safe."""
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if (
        not isinstance(payload, dict)
        or payload.get("reasoning_effort") not in TIMEOUT_RETRY_EFFORTS
    ):
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
    chat_request_stagger: float = 0.0

    @classmethod
    def from_environment(cls) -> Settings:
        """Load overrides from the container environment."""
        return cls(
            upstream_url=os.getenv("SAKURA_UPSTREAM_URL", cls.upstream_url),
            max_retries=int(os.getenv("SAKURA_RETRY_MAX", cls.max_retries)),
            base_backoff=float(
                os.getenv("SAKURA_RETRY_BASE_SECONDS", cls.base_backoff)
            ),
            max_backoff=float(os.getenv("SAKURA_RETRY_MAX_SECONDS", cls.max_backoff)),
            jitter=float(os.getenv("SAKURA_RETRY_JITTER_SECONDS", cls.jitter)),
            chat_request_stagger=float(
                os.getenv(
                    "SAKURA_CHAT_REQUEST_STAGGER_SECONDS", cls.chat_request_stagger
                )
            ),
        )


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    """Forward OpenAI-compatible requests and retry recoverable failures."""

    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)
    _chat_slot_lock = threading.Lock()
    _next_chat_request_at = 0.0

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
        while True:
            try:
                self._wait_for_chat_slot()
                connection, response = self._request_upstream(request_body)
            except TimeoutError as error:
                fallback = None if timeout_retried else low_reasoning_body(request_body)
                if fallback is not None:
                    LOG.warning(
                        "Upstream request timed out; retrying once with "
                        "reasoning_effort=low"
                    )
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                LOG.warning("Upstream request timed out: %s", error)
                self._send_json(
                    504, {"error": {"code": "timeout", "message": "upstream timeout"}}
                )
                return
            except (OSError, http.client.HTTPException) as error:
                LOG.warning("Upstream request failed: %s", error)
                self._send_json(502, {"error": {"message": "upstream unavailable"}})
                return
            if response.status == 429 and rate_limit_attempt < self.settings.max_retries:
                retry_after = retry_after_seconds(response.getheader("Retry-After"))
                response.read()
                connection.close()
                delay = (
                    retry_after
                    if retry_after is not None
                    else min(
                        self.settings.max_backoff,
                        self.settings.base_backoff * (2**rate_limit_attempt),
                    )
                )
                delay += random.uniform(0.0, self.settings.jitter)
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
                fallback = None if timeout_retried else low_reasoning_body(request_body)
                if fallback is not None:
                    LOG.warning(
                        "Upstream response timed out; retrying once with "
                        "reasoning_effort=low"
                    )
                    request_body = fallback
                    timeout_retried = True
                    rate_limit_attempt = 0
                    continue
                LOG.warning("Upstream response timed out: %s", error)
                self._send_json(
                    504, {"error": {"code": "timeout", "message": "upstream timeout"}}
                )
                return

            fallback = None
            if is_timeout_response(response.status, prefix) and not timeout_retried:
                fallback = low_reasoning_body(request_body)
            if fallback is not None:
                response.close()
                connection.close()
                LOG.warning(
                    "Upstream returned a timeout; retrying once with "
                    "reasoning_effort=low"
                )
                request_body = fallback
                timeout_retried = True
                rate_limit_attempt = 0
                continue

            self._stream(connection, response, prefix)
            return

    def _wait_for_chat_slot(self) -> None:
        interval = self.settings.chat_request_stagger
        if interval <= 0 or urlsplit(self.path).path != "/v1/chat/completions":
            return
        handler = type(self)
        # Reserve slots globally so concurrent handlers reach Sakura at fixed intervals.
        with handler._chat_slot_lock:
            now = time.monotonic()
            scheduled = max(now, handler._next_chat_request_at)
            handler._next_chat_request_at = scheduled + interval
        delay = scheduled - time.monotonic()
        if delay > 0:
            LOG.info("Delaying chat completion by %.1fs to pace upstream requests", delay)
            time.sleep(delay)

    def _read_body(self) -> bytes | None:
        if self.headers.get("Transfer-Encoding"):
            self._send_json(501, {"error": {"message": "chunked request unsupported"}})
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
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
            and name.lower() not in {"host", "content-length"}
        }
        headers["Host"] = self.upstream.netloc
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

    def _stream(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
        prefix: bytes = b"",
    ) -> None:
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            if name.lower() not in HOP_BY_HOP_HEADERS:
                self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
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

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
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
    if settings.chat_request_stagger < 0:
        raise ValueError("SAKURA_CHAT_REQUEST_STAGGER_SECONDS must not be negative")
    handler = type(
        "ConfiguredSakuraRetryProxyHandler",
        (SakuraRetryProxyHandler,),
        {
            "settings": settings,
            "upstream": upstream,
            "_chat_slot_lock": threading.Lock(),
            "_next_chat_request_at": 0.0,
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
