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
    """Minimal successful upstream response."""

    status_code: int = 200
    content: bytes = b'<a class="result__a">result</a>'
    headers: dict[str, str] = field(
        default_factory=lambda: {"content-type": "text/html"}
    )


class FakeClient:
    """Record forwarded forms without network access."""

    def __init__(self) -> None:
        """Initialize the last submitted form."""
        self.data: dict[str, str] = {}

    def post(self, url: str, *, data: dict[str, str]) -> FakeResponse:
        """Record a form and return a successful HTML response."""
        self.data = data
        return FakeResponse()


class DdgProxyTest(unittest.TestCase):
    """Exercise the proxy through its HTTP boundary."""

    def setUp(self) -> None:
        """Start a proxy backed by the fake client."""
        self.client = FakeClient()
        self.original_client = ddg_proxy.CLIENT
        ddg_proxy.CLIENT = self.client
        self.server = ddg_proxy.make_server(("127.0.0.1", 0))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        """Restore the client and stop the proxy."""
        ddg_proxy.CLIENT = self.original_client
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)

    def test_forwards_valid_form(self) -> None:
        """Forward a valid SearXNG form to the client."""
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/html/",
            data=b"q=Python+3.14&b=&kl=wt-wt",
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertIn(b"result__a", response.read())
        self.assertEqual(self.client.data["q"], "Python 3.14")

    def test_rejects_other_paths(self) -> None:
        """Reject paths outside the fixed DDG endpoint."""
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}/other",
            data=b"q=test",
        )
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        self.assertEqual(error.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
