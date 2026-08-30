from __future__ import annotations

import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from sakura_retry_proxy import Settings, make_server, retry_after_seconds


class UpstreamHandler(BaseHTTPRequestHandler):
    attempts = 0

    def do_POST(self) -> None:
        type(self).attempts += 1
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        if self.attempts < 3:
            self.send_response(429)
            self.send_header("Retry-After", "0")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class SakuraRetryProxyTest(unittest.TestCase):
    def setUp(self) -> None:
        UpstreamHandler.attempts = 0
        self.upstream = ThreadingHTTPServer(("127.0.0.1", 0), UpstreamHandler)
        upstream_port = self.upstream.server_address[1]
        self.proxy = make_server(
            Settings(
                upstream_url=f"http://127.0.0.1:{upstream_port}",
                listen_host="127.0.0.1",
                listen_port=0,
                max_retries=3,
                base_backoff=0.01,
                max_backoff=0.01,
                jitter=0,
            )
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

    def test_retries_429_then_streams_success(self) -> None:
        proxy_port = self.proxy.server_address[1]
        request = urllib.request.Request(
            f"http://127.0.0.1:{proxy_port}/v1/chat/completions",
            data=b"{}",
            headers={"Authorization": "Bearer test"},
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b'{"ok":true}')
        self.assertEqual(UpstreamHandler.attempts, 3)

    def test_retry_after_parser(self) -> None:
        self.assertEqual(retry_after_seconds("2"), 2)
        self.assertIsNone(retry_after_seconds("invalid"))


if __name__ == "__main__":
    unittest.main()
