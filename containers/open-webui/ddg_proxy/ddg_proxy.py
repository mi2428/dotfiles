"""Forward SearXNG's DuckDuckGo requests with a browser transport profile."""

from __future__ import annotations

import logging
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Protocol, cast
from urllib.parse import parse_qsl, urlsplit

import primp

LOG = logging.getLogger("ddg-proxy")
LISTEN_ADDRESS = ("0.0.0.0", 8081)
MAX_REQUEST_BYTES = 64 * 1024
UPSTREAM_URL = "https://html.duckduckgo.com/html/"


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


CLIENT = cast(
    Client,
    primp.Client(
        impersonate=os.getenv("DDG_IMPERSONATE", "chrome_151"),
        impersonate_os=os.getenv("DDG_IMPERSONATE_OS", "macos"),
        timeout=30,
        follow_redirects=True,
    ),
)
CLIENT_LOCK = threading.Lock()


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
            with CLIENT_LOCK:
                response = CLIENT.post(UPSTREAM_URL, data=form)
        except Exception:
            LOG.exception("DuckDuckGo request failed")
            self._send(502, b'{"error":"upstream unavailable"}', "application/json")
            return

        lower = response.content.lower()
        LOG.info(
            "Upstream status=%d captcha=%s results=%s",
            response.status_code,
            b"challenge-form" in lower,
            b"result__a" in lower,
        )
        self._send(
            response.status_code,
            response.content,
            response.headers.get("content-type", "text/html; charset=UTF-8"),
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

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def log_message(self, format: str, *args: object) -> None:
        """Suppress the base server's access log to avoid recording queries."""


def make_server(
    address: tuple[str, int] = LISTEN_ADDRESS,
) -> ThreadingHTTPServer:
    """Build the threaded internal proxy server."""
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
