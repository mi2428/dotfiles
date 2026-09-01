"""Tests for the internal DuckDuckGo transport proxy."""

from __future__ import annotations

import threading
import unittest
import urllib.error
import urllib.request
from dataclasses import dataclass, field

import ddg_proxy


@dataclass
class FakeResponse:
    status_code: int = 200
    content: bytes = b'<a class="result__a">result</a>'
    headers: dict[str, str] = field(
        default_factory=lambda: {"content-type": "text/html"}
    )


class FakeClient:
    """Record forwarded forms without network access."""

    def __init__(self) -> None:
        self.data: dict[str, str] = {}

    def post(self, url: str, *, data: dict[str, str]) -> FakeResponse:
        self.data = data
        return FakeResponse()


class DdgProxyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = FakeClient()
        self.original_client = ddg_proxy.CLIENT
        ddg_proxy.CLIENT = self.client
        self.server = ddg_proxy.make_server(("127.0.0.1", 0))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        ddg_proxy.CLIENT = self.original_client
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)

    def test_forwards_valid_form(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/",
            data=b"q=Python+3.14&b=&kl=wt-wt",
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertIn(b"result__a", response.read())
        self.assertEqual(self.client.data["q"], "Python 3.14")

    def test_rejects_other_paths(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/other",
            data=b"q=test",
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()
        self.assertEqual(error.exception.code, 404)

    def test_rejects_empty_queries_before_upstream(self) -> None:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/",
            data=b"q=",
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        error.exception.close()
        self.assertEqual(error.exception.code, 400)
        self.assertEqual(self.client.data, {})


if __name__ == "__main__":
    unittest.main()
