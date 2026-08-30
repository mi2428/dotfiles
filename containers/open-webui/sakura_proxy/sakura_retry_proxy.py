"""Stream Sakura AI Engine responses and retry HTTP 429 failures."""

from __future__ import annotations

import http.client
import json
import logging
import os
import random
import ssl
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


@dataclass(frozen=True, slots=True)
class Settings:
    """Runtime settings for the internal Sakura gateway."""

    upstream_url: str = "https://api.ai.sakura.ad.jp"
    max_retries: int = 10
    base_backoff: float = 2.0
    max_backoff: float = 120.0
    jitter: float = 1.0

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
        )


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    """Forward OpenAI-compatible requests and retry rate limits."""

    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)

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

        for attempt in range(self.settings.max_retries + 1):
            try:
                connection, response = self._request_upstream(body)
            except (OSError, http.client.HTTPException) as error:
                LOG.warning("Upstream request failed: %s", error)
                self._send_json(502, {"error": {"message": "upstream unavailable"}})
                return
            if response.status != 429 or attempt == self.settings.max_retries:
                self._stream(connection, response)
                return

            retry_after = retry_after_seconds(response.getheader("Retry-After"))
            response.read()
            connection.close()
            delay = (
                retry_after
                if retry_after is not None
                else min(
                    self.settings.max_backoff,
                    self.settings.base_backoff * (2**attempt),
                )
            )
            delay += random.uniform(0.0, self.settings.jitter)
            LOG.warning(
                "Upstream returned 429; retrying in %.1fs (%d/%d)",
                delay,
                attempt + 1,
                self.settings.max_retries,
            )
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
        connection.request(
            self.command,
            f"{self.upstream.path.rstrip('/')}{self.path}",
            body,
            headers,
        )
        return connection, connection.getresponse()

    def _stream(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
    ) -> None:
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            if name.lower() not in HOP_BY_HOP_HEADERS:
                self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
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
    handler = type(
        "ConfiguredSakuraRetryProxyHandler",
        (SakuraRetryProxyHandler,),
        {"settings": settings, "upstream": upstream},
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
