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
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except ValueError:
        try:
            return max(0.0, parsedate_to_datetime(value).timestamp() - time.time())
        except (TypeError, ValueError, OverflowError):
            return None


@dataclass(frozen=True)
class Settings:
    upstream_url: str = "https://api.ai.sakura.ad.jp"
    listen_host: str = "0.0.0.0"
    listen_port: int = 8080
    max_retries: int = 10
    base_backoff: float = 2.0
    max_backoff: float = 120.0
    jitter: float = 1.0
    timeout: float = 7200.0
    max_request_bytes: int = 64 * 1024 * 1024

    @classmethod
    def from_environment(cls) -> Settings:
        return cls(
            upstream_url=os.getenv("SAKURA_UPSTREAM_URL", cls.upstream_url),
            listen_host=os.getenv("SAKURA_PROXY_HOST", cls.listen_host),
            listen_port=int(os.getenv("SAKURA_PROXY_PORT", cls.listen_port)),
            max_retries=int(os.getenv("SAKURA_RETRY_MAX", cls.max_retries)),
            base_backoff=float(
                os.getenv("SAKURA_RETRY_BASE_SECONDS", cls.base_backoff)
            ),
            max_backoff=float(os.getenv("SAKURA_RETRY_MAX_SECONDS", cls.max_backoff)),
            jitter=float(os.getenv("SAKURA_RETRY_JITTER_SECONDS", cls.jitter)),
            timeout=float(os.getenv("SAKURA_UPSTREAM_TIMEOUT_SECONDS", cls.timeout)),
            max_request_bytes=int(
                os.getenv("SAKURA_MAX_REQUEST_BYTES", cls.max_request_bytes)
            ),
        )


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)

    def do_GET(self) -> None:
        self._proxy()

    def do_POST(self) -> None:
        self._proxy()

    def do_DELETE(self) -> None:
        self._proxy()

    def do_PATCH(self) -> None:
        self._proxy()

    def do_PUT(self) -> None:
        self._proxy()

    def log_message(self, format: str, *args: object) -> None:
        if self.path == "/health":
            return
        LOG.info("%s - %s", self.client_address[0], format % args)

    def _proxy(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return

        body = self._read_request_body()
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
                self._stream_response(connection, response)
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

    def _read_request_body(self) -> bytes | None:
        if self.headers.get("Transfer-Encoding"):
            self._send_json(501, {"error": {"message": "chunked request unsupported"}})
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": {"message": "invalid content length"}})
            return None
        if length > self.settings.max_request_bytes:
            self._send_json(413, {"error": {"message": "request body too large"}})
            return None
        return self.rfile.read(length) if length else b""

    def _request_upstream(
        self, body: bytes
    ) -> tuple[http.client.HTTPConnection, http.client.HTTPResponse]:
        upstream = self.upstream
        host = upstream.hostname
        if host is None:
            raise ValueError("upstream host is required")
        connection_type = (
            http.client.HTTPSConnection
            if upstream.scheme == "https"
            else http.client.HTTPConnection
        )
        if connection_type is http.client.HTTPSConnection:
            connection = connection_type(
                host,
                upstream.port,
                timeout=self.settings.timeout,
                context=ssl.create_default_context(),
            )
        else:
            connection = connection_type(
                host,
                upstream.port,
                timeout=self.settings.timeout,
            )
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
            and name.lower() not in {"host", "content-length"}
        }
        headers["Host"] = upstream.netloc
        if body:
            headers["Content-Length"] = str(len(body))
        path = f"{upstream.path.rstrip('/')}{self.path}"
        connection.request(self.command, path, body=body, headers=headers)
        return connection, connection.getresponse()

    def _stream_response(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
    ) -> None:
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            if name.lower() not in HOP_BY_HOP_HEADERS and name.lower() != "connection":
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


def make_server(settings: Settings) -> ThreadingHTTPServer:
    upstream = urlsplit(settings.upstream_url)
    if upstream.scheme not in {"http", "https"} or not upstream.hostname:
        raise ValueError("SAKURA_UPSTREAM_URL must be an absolute HTTP(S) URL")
    handler = type(
        "ConfiguredSakuraRetryProxyHandler",
        (SakuraRetryProxyHandler,),
        {"settings": settings, "upstream": upstream},
    )
    return ThreadingHTTPServer((settings.listen_host, settings.listen_port), handler)


def main() -> None:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = Settings.from_environment()
    server = make_server(settings)
    LOG.info("Listening on %s:%d", settings.listen_host, settings.listen_port)
    server.serve_forever()


if __name__ == "__main__":
    main()
