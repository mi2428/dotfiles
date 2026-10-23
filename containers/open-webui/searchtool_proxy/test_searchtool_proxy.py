"""Tests for the Open WebUI to Sakura Search Tool adapter."""

import json
import unittest
from unittest.mock import MagicMock, patch

from ddgs.exceptions import RatelimitException
from searchtool_proxy import (
    bearer_token_matches,
    decode_search_request,
    search,
    search_tool,
)


class SearchToolProxyTests(unittest.TestCase):
    """Verify input validation, authentication, and result translation."""

    def setUp(self) -> None:
        self.cooldown = patch("searchtool_proxy.ddgs_retry_after", 0)
        self.cooldown.start()
        self.addCleanup(self.cooldown.stop)

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

    def test_ddgs_success_does_not_consume_search_tool_api(self) -> None:
        with (
            patch("searchtool_proxy.DDGS") as ddgs,
            patch("searchtool_proxy.search_tool") as paid,
        ):
            ddgs.return_value.text.return_value = [
                {"title": "Sakura", "href": "https://example.test", "body": "result"}
            ]
            self.assertEqual(
                search("Sakura", 5, "x" * 32),
                [
                    {
                        "title": "Sakura",
                        "link": "https://example.test",
                        "snippet": "result",
                    }
                ],
            )
            ddgs.return_value.text.assert_called_once_with(
                "Sakura", max_results=5, backend="auto"
            )
            paid.assert_not_called()

    def test_ddgs_failure_or_empty_results_uses_search_tool(self) -> None:
        with (
            patch("searchtool_proxy.DDGS") as ddgs,
            patch("searchtool_proxy.search_tool", return_value=[]) as paid,
        ):
            for result in ([], RatelimitException("rate limited")):
                ddgs.return_value.text.side_effect = (
                    result if isinstance(result, Exception) else None
                )
                ddgs.return_value.text.return_value = (
                    result if isinstance(result, list) else None
                )
                search("Sakura", 5, "x" * 32)
            self.assertEqual(paid.call_count, 2)

    def test_invalid_ddgs_link_does_not_become_a_search_result(self) -> None:
        with (
            patch("searchtool_proxy.DDGS") as ddgs,
            patch("searchtool_proxy.search_tool", return_value=[]) as paid,
        ):
            ddgs.return_value.text.return_value = [
                {"title": "invalid", "href": "javascript:alert(1)", "body": "text"}
            ]
            self.assertEqual(search("Sakura", 5, "x" * 32), [])
            paid.assert_called_once()

    def test_zero_count_skips_both_backends(self) -> None:
        with (
            patch("searchtool_proxy.DDGS") as ddgs,
            patch("searchtool_proxy.search_tool") as paid,
        ):
            self.assertEqual(search("Sakura", 0, "x" * 32), [])
            ddgs.assert_not_called()
            paid.assert_not_called()

    def test_rate_limit_cools_down_ddgs(self) -> None:
        with (
            patch("searchtool_proxy.ddgs_retry_after", 0),
            patch("searchtool_proxy.time.monotonic", return_value=100),
            patch("searchtool_proxy.DDGS") as ddgs,
            patch("searchtool_proxy.search_tool", return_value=[]) as paid,
        ):
            ddgs.return_value.text.side_effect = RatelimitException("rate limited")
            search("Sakura", 5, "x" * 32)
            search("Sakura", 5, "x" * 32)
            self.assertEqual(ddgs.return_value.text.call_count, 1)
            self.assertEqual(paid.call_count, 2)


if __name__ == "__main__":
    unittest.main()
