"""Forward SearXNG's fixed DuckDuckGo HTML endpoint through a browser profile.

Only internal form searches are accepted, request bodies are bounded, and query-bearing
access logs are suppressed. A lock serializes the shared primp client used by SearXNG.
"""

from __future__ import annotations

import logging
import math
import os
import threading
import time
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Protocol, cast
from urllib.parse import parse_qsl, urlsplit

LOG = logging.getLogger("ddg-proxy")
LISTEN_ADDRESS = ("0.0.0.0", 8081)
MAX_REQUEST_BYTES = 64 * 1024
UPSTREAM_URL = "https://html.duckduckgo.com/html/"


def env_seconds(name: str, default: float) -> float:
    """Read a finite, non-negative duration or fail fast at startup."""
    value = float(os.getenv(name, str(default)))
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{name} must be a finite, non-negative number")
    return value


MIN_INTERVAL_SECONDS = env_seconds("DDG_MIN_INTERVAL", 10)
CAPTCHA_COOLDOWN_SECONDS = env_seconds("DDG_CAPTCHA_COOLDOWN", 3600)
RATE_LIMIT_COOLDOWN_SECONDS = env_seconds("DDG_429_COOLDOWN", 1800)
MONOTONIC = time.monotonic
WALL_TIME = time.time
SLEEP = time.sleep


class Response(Protocol):
    """Subset of a primp response consumed by the proxy."""

    status_code: int
    content: bytes
    headers: dict[str, str]


class Client(Protocol):
    """Subset of the primp client used for dependency-free tests."""

    def post(self, url: str, *, data: dict[str, str]) -> Response:
        """Submit a form and return its response."""
        ...


def make_client() -> Client:
    """Create the image-only primp client without coupling unit tests to primp."""
    import primp  # pyright: ignore[reportMissingImports]

    return cast(
        Client,
        primp.Client(
            impersonate=os.getenv("DDG_IMPERSONATE", "chrome_151"),
            impersonate_os=os.getenv("DDG_IMPERSONATE_OS", "macos"),
            timeout=30,
            follow_redirects=True,
        ),
    )


CLIENT: Client | None = None
CLIENT_LOCK = threading.Lock()
LAST_REQUEST_AT: float | None = None
COOLDOWN_UNTIL = 0.0


def response_header(response: Response, name: str, default: str = "") -> str:
    """Read a response header without relying on mapping case behavior."""
    return next(
        (value for key, value in response.headers.items() if key.lower() == name.lower()),
        default,
    )


def retry_after_seconds(value: str) -> float:
    """Interpret Retry-After and cap it at the configured 429 cooldown."""
    try:
        delay = float(value)
    except ValueError:
        try:
            delay = parsedate_to_datetime(value).timestamp() - WALL_TIME()
        except (TypeError, ValueError, OverflowError):
            return RATE_LIMIT_COOLDOWN_SECONDS
    if not math.isfinite(delay) or delay <= 0:
        return RATE_LIMIT_COOLDOWN_SECONDS
    return min(delay, RATE_LIMIT_COOLDOWN_SECONDS)


def request_upstream(form: dict[str, str]) -> tuple[Response | None, float]:
    """Serialize DDG access and atomically enforce interval and cooldown state."""
    global COOLDOWN_UNTIL, LAST_REQUEST_AT

    assert CLIENT is not None
    with CLIENT_LOCK:
        now = MONOTONIC()
        remaining = COOLDOWN_UNTIL - now
        if remaining > 0:
            return None, remaining

        if LAST_REQUEST_AT is not None:
            wait = MIN_INTERVAL_SECONDS - (now - LAST_REQUEST_AT)
            if wait > 0:
                SLEEP(wait)
        LAST_REQUEST_AT = MONOTONIC()
        response = CLIENT.post(UPSTREAM_URL, data=form)
        lower = response.content.lower()
        captcha = b"challenge-form" in lower
        LOG.info(
            "Upstream status=%d captcha=%s results=%s",
            response.status_code,
            captcha,
            b"result__a" in lower,
        )

        if captcha:
            cooldown = CAPTCHA_COOLDOWN_SECONDS
        elif response.status_code == 429:
            cooldown = retry_after_seconds(response_header(response, "retry-after"))
        else:
            return response, 0
        COOLDOWN_UNTIL = MONOTONIC() + cooldown
        return None, cooldown


class Handler(BaseHTTPRequestHandler):
    """Validate internal requests and proxy only the fixed DDG HTML endpoint."""

    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        """Serve the container health check."""
        if urlsplit(self.path).path == "/health":
            self._send(200, b'{"status":true}', "application/json")
        else:
            self._send(404, b'{"error":"not found"}', "application/json")

    def do_POST(self) -> None:
        """Forward a validated SearXNG form search to DuckDuckGo."""
        if urlsplit(self.path).path != "/html/":
            self._send(404, b'{"error":"not found"}', "application/json")
            return
        form = self._read_form()
        if form is None:
            return

        try:
            response, retry_after = request_upstream(form)
        except Exception as error:  # noqa: BLE001 - isolate all provider failures
            LOG.error("DuckDuckGo request failed (%s)", type(error).__name__)
            self._send(502, b'{"error":"upstream unavailable"}', "application/json")
            return

        if response is None:
            self._send(
                429,
                b'{"error":"temporarily unavailable"}',
                "application/json",
                retry_after=math.ceil(retry_after),
            )
            return
        self._send(
            response.status_code,
            response.content,
            response_header(response, "content-type", "text/html; charset=UTF-8"),
        )

    def _read_form(self) -> dict[str, str] | None:
        if self.headers.get("Transfer-Encoding"):
            self._send(
                501, b'{"error":"chunked request unsupported"}', "application/json"
            )
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send(400, b'{"error":"invalid content length"}', "application/json")
            return None
        if length < 0 or length > MAX_REQUEST_BYTES:
            self._send(413, b'{"error":"request body too large"}', "application/json")
            return None
        try:
            body = self.rfile.read(length).decode()
        except UnicodeDecodeError:
            self._send(400, b'{"error":"invalid form encoding"}', "application/json")
            return None
        form = dict(parse_qsl(body, keep_blank_values=True))
        if not form.get("q"):
            self._send(400, b'{"error":"query required"}', "application/json")
            return None
        return form

    def _send(
        self,
        status: int,
        body: bytes,
        content_type: str,
        *,
        retry_after: int | None = None,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if retry_after is not None:
            self.send_header("Retry-After", str(retry_after))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def log_message(self, format: str, *args: object) -> None:
        """Suppress the base server's access log to avoid recording queries."""


def make_server(
    address: tuple[str, int] = LISTEN_ADDRESS,
) -> ThreadingHTTPServer:
    """Build the server after initializing its shared production client."""
    global CLIENT
    if CLIENT is None:
        CLIENT = make_client()
    return ThreadingHTTPServer(address, Handler)


def main() -> None:
    """Run the proxy until the container stops."""
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    server = make_server()
    LOG.info("Listening on %s:%d", *server.server_address)
    server.serve_forever()


if __name__ == "__main__":
    main()
