"""Tests for the Open WebUI to Sakura Search Tool adapter."""

import json
import unittest
from unittest.mock import MagicMock, patch

from searchtool_proxy import bearer_token_matches, decode_search_request, search_tool


class SearchToolProxyTests(unittest.TestCase):
    """Verify input validation, authentication, and result translation."""

    def test_decodes_open_webui_search_request(self) -> None:
        self.assertEqual(
            decode_search_request(b'{"query":"  Sakura  ","count":10}'), ("Sakura", 10)
        )

    def test_rejects_invalid_request(self) -> None:
        for body in (
            b"{}",
            b'{"query":"x","count":21}',
            b'{"query":"x","count":1,"extra":true}',
        ):
            with self.subTest(body=body), self.assertRaises(ValueError):
                decode_search_request(body)

    def test_checks_bearer_token(self) -> None:
        self.assertTrue(bearer_token_matches("Bearer " + "x" * 32, "x" * 32))
        self.assertFalse(bearer_token_matches("Bearer wrong", "x" * 32))

    def test_forwards_and_adapts_search_results(self) -> None:
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = json.dumps(
            {
                "results": [
                    {
                        "title": "Sakura",
                        "link": "https://example.test",
                        "snippet": "result",
                    }
                ]
            }
        ).encode()
        token = "x" * 32

        with patch("searchtool_proxy.urlopen", return_value=response) as urlopen:
            results = search_tool("Sakura", 5, token)

        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer " + token)
        self.assertEqual(json.loads(request.data), {"query": "Sakura", "count": 5})
        self.assertEqual(
            results,
            [{"title": "Sakura", "link": "https://example.test", "snippet": "result"}],
        )

    def test_rejects_malformed_search_results(self) -> None:
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = (
            b'{"results":[{"title":null,"link":"url","snippet":"text"}]}'
        )

        with (
            patch("searchtool_proxy.urlopen", return_value=response),
            self.assertRaises(TypeError),
        ):
            search_tool("Sakura", 5, "x" * 32)


if __name__ == "__main__":
    unittest.main()
