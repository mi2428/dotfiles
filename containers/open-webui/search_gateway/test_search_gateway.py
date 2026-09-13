from __future__ import annotations

import io
import json
import os
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch
from urllib.parse import parse_qs, urlencode, urlsplit

from search_gateway import (
    SearchGateway,
    Settings,
    make_server,
    parse_search_query,
)


def response(*urls: str, unresponsive: list[object] | None = None) -> bytes:
    return json.dumps(
        {
            "results": [
                {"url": url, "title": f"title {url}", "content": f"body {url}"}
                for url in urls
            ],
            "unresponsive_engines": unresponsive or [],
        }
    ).encode()


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


class FakeFetcher:
    def __init__(self, replies: dict[str, bytes | BaseException]) -> None:
        self.replies = replies
        self.calls: list[tuple[str, dict[str, list[str]], float]] = []

    def __call__(self, url: str, timeout: float) -> bytes:
        parameters = parse_qs(urlsplit(url).query, keep_blank_values=True)
        provider = parameters["engines"][0]
        self.calls.append((provider, parameters, timeout))
        reply = self.replies.get(provider, response())
        if isinstance(reply, BaseException):
            raise reply
        return reply


def settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "upstream_url": "http://searxng:8080/search",
        "provider_interval": 0,
        "long_cooldown": 100,
        "backoff_base": 1,
        "backoff_max": 4,
        "upstream_timeout": 2,
        "global_deadline": 10,
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


def gateway_with(
    replies: dict[str, bytes | BaseException], **setting_changes: object
) -> tuple[SearchGateway, FakeFetcher, FakeClock]:
    fetcher = FakeFetcher(replies)
    clock = FakeClock()
    gateway = SearchGateway(settings(**setting_changes), fetcher, clock, clock.sleep)
    return gateway, fetcher, clock


class SearchGatewayTest(unittest.TestCase):
    def test_routes_japanese_and_non_japanese_queries(self) -> None:
        cases = (
            ("猫について", "yahoo japan"),
            ("𠮷野家", "yahoo japan"),
            ("python docs", "mwmbl"),
        )
        for query, expected_provider in cases:
            with self.subTest(query=query):
                gateway, fetcher, _ = gateway_with(
                    {expected_provider: response("1", "2", "3", "4", "5")}
                )
                status, payload = gateway.search(
                    {
                        "q": query,
                        "format": "json",
                        "language": "ja-JP",
                        "pageno": "2",
                        "safesearch": "1",
                        "time_range": "month",
                        "categories": "general",
                        "theme": "simple",
                        "image_proxy": "0",
                    }
                )
                self.assertEqual((status, len(payload["results"])), (200, 5))  # type: ignore[arg-type]
                provider, forwarded, _ = fetcher.calls[0]
                self.assertEqual(provider, expected_provider)
                self.assertEqual(
                    {name: forwarded[name][0] for name in forwarded},
                    {
                        "q": query,
                        "format": "json",
                        "language": "ja-JP",
                        "pageno": "2",
                        "safesearch": "1",
                        "time_range": "month",
                        "categories": "general",
                        "theme": "simple",
                        "image_proxy": "0",
                        "engines": expected_provider,
                    },
                )

    def test_first_provider_reaching_threshold_short_circuits(self) -> None:
        gateway, fetcher, _ = gateway_with(
            {"mwmbl": response("1", "2", "3", "4", "5", "6")}
        )

        status, payload = gateway.search({"q": "python"})

        self.assertEqual(status, 200)
        self.assertEqual(len(payload["results"]), 6)  # type: ignore[arg-type]
        self.assertEqual([call[0] for call in fetcher.calls], ["mwmbl"])

    def test_partial_results_merge_in_order_and_dedupe_urls(self) -> None:
        gateway, fetcher, _ = gateway_with(
            {
                "mwmbl": response("a", "b"),
                "bing": response("b", "c", "d", "e"),
                "duckduckgo": response("unused"),
            }
        )

        status, payload = gateway.search({"q": "partial"})

        self.assertEqual(status, 200)
        self.assertEqual(
            [result["url"] for result in payload["results"]],  # type: ignore[index]
            ["a", "b", "c", "d", "e"],
        )
        self.assertEqual([call[0] for call in fetcher.calls], ["mwmbl", "bing"])

    def test_result_count_is_capped_at_ten(self) -> None:
        gateway, _, _ = gateway_with(
            {"mwmbl": response(*(str(number) for number in range(12)))}
        )
        status, payload = gateway.search({"q": "many"})
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["results"]), 10)  # type: ignore[arg-type]

    def test_normalized_query_and_language_hit_cache_without_fetching(self) -> None:
        gateway, fetcher, _ = gateway_with({"mwmbl": response("1", "2", "3", "4", "5")})

        first = gateway.search({"q": "  Python  ", "language": " EN "})
        second = gateway.search({"q": "ＰＹＴＨＯＮ", "language": "en"})

        self.assertEqual(first, second)
        self.assertEqual(len(fetcher.calls), 1)

    def test_cache_separates_forwarded_parameter_variants(self) -> None:
        cases = (
            ("pageno", "1", "2"),
            ("safesearch", "0", "1"),
            ("time_range", "day", "month"),
            ("categories", "general", "images"),
            ("theme", "simple", "dark"),
            ("image_proxy", "0", "1"),
        )
        for name, first, second in cases:
            with self.subTest(parameter=name):
                gateway, fetcher, _ = gateway_with(
                    {"mwmbl": response("1", "2", "3", "4", "5")}
                )

                gateway.search({"q": "cache variant", name: first})
                gateway.search({"q": "cache variant", name: second})

                self.assertEqual(len(fetcher.calls), 2)

    def test_cache_is_ttl_lru_bounded(self) -> None:
        gateway, fetcher, clock = gateway_with(
            {"mwmbl": response("1", "2", "3", "4", "5")},
            cache_ttl=5,
            cache_max_entries=2,
        )
        for query in ("a", "b", "a", "c", "b"):
            gateway.search({"q": query})
        self.assertEqual(len(fetcher.calls), 4)

        clock.now += 5
        gateway.search({"q": "a"})
        self.assertEqual(len(fetcher.calls), 5)

    def test_429_and_captcha_open_long_cooldowns(self) -> None:
        rate_limit = urllib.error.HTTPError(
            "http://internal", 429, "rate limited", {}, io.BytesIO(b"")
        )
        cases = (
            ("mwmbl", rate_limit, "rate_limit"),
            (
                "yahoo japan",
                response(unresponsive=[["yahoo japan", "CAPTCHA challenge"]]),
                "captcha",
            ),
        )
        for provider, reply, reason in cases:
            with self.subTest(reason=reason):
                query = "猫" if provider == "yahoo japan" else "python"
                gateway, _, clock = gateway_with(
                    {
                        provider: reply,
                        "bing": response("1", "2", "3", "4", "5"),
                    }
                )
                status, _ = gateway.search({"q": query})
                state = gateway.providers[provider]
                self.assertEqual(status, 200)
                self.assertEqual(state.reason, reason)
                self.assertEqual(state.failure_count, 1)
                self.assertEqual(state.open_until, clock.now + 100)

    def test_provider_on_cooldown_is_skipped(self) -> None:
        gateway, fetcher, clock = gateway_with(
            {"bing": response("1", "2", "3", "4", "5")}
        )
        gateway.providers["mwmbl"].open_until = clock.now + 30
        gateway.providers["mwmbl"].reason = "rate_limit"

        status, _ = gateway.search({"q": "skip"})

        self.assertEqual(status, 200)
        self.assertEqual([call[0] for call in fetcher.calls], ["bing"])

        for provider in ("mwmbl", "bing", "duckduckgo"):
            gateway.providers[provider].open_until = clock.now + 30
        unavailable_status, _ = gateway.search({"q": "all skipped"})
        self.assertEqual(unavailable_status, 503)
        self.assertEqual([call[0] for call in fetcher.calls], ["bing"])

    def test_provider_pacing_and_bounded_5xx_backoff(self) -> None:
        clock = FakeClock()

        def failing_first_provider(url: str, timeout: float) -> bytes:
            provider = parse_qs(urlsplit(url).query)["engines"][0]
            if provider == "mwmbl":
                raise urllib.error.HTTPError(
                    url, 503, "unavailable", {}, io.BytesIO(b"")
                )
            return response("1", "2", "3", "4", "5")

        gateway = SearchGateway(settings(), failing_first_provider, clock, clock.sleep)
        for attempt, expected_backoff in enumerate((1, 2, 4, 4)):
            status, _ = gateway.search({"q": f"failure {attempt}"})
            self.assertEqual(status, 200)
            state = gateway.providers["mwmbl"]
            self.assertEqual(state.reason, "server_error")
            self.assertEqual(state.open_until - clock.now, expected_backoff)
            clock.now = state.open_until

        pacing_gateway, _, pacing_clock = gateway_with(
            {"mwmbl": response("1", "2", "3", "4", "5")},
            provider_interval=3,
        )
        pacing_gateway.search({"q": "first"})
        pacing_gateway.search({"q": "second"})
        self.assertEqual(pacing_clock.now, 3)

    def test_all_healthy_zero_results_is_200_and_cached(self) -> None:
        gateway, fetcher, _ = gateway_with({})

        first = gateway.search({"q": "nothing"})
        second = gateway.search({"q": "nothing"})

        self.assertEqual(first, (200, {"results": []}))
        self.assertEqual(second, first)
        self.assertEqual(len(fetcher.calls), 3)

    def test_all_degraded_is_503_without_retry(self) -> None:
        gateway, fetcher, _ = gateway_with(
            {
                "mwmbl": TimeoutError(),
                "bing": TimeoutError(),
                "duckduckgo": TimeoutError(),
            }
        )

        status, payload = gateway.search({"q": "down"})

        self.assertEqual(
            (status, payload), (503, {"error": "all search providers unavailable"})
        )
        self.assertEqual(len(fetcher.calls), 3)
        self.assertTrue(
            all(
                gateway.providers[provider].reason == "timeout"
                for provider in ("mwmbl", "bing", "duckduckgo")
            )
        )

    def test_global_deadline_returns_504_even_after_provider_timeout(self) -> None:
        clock = FakeClock()
        calls = 0

        def timeout_fetcher(url: str, timeout: float) -> bytes:
            nonlocal calls
            calls += 1
            clock.now += timeout
            raise TimeoutError

        gateway = SearchGateway(
            settings(global_deadline=2, upstream_timeout=5),
            timeout_fetcher,
            clock,
            clock.sleep,
        )

        status, payload = gateway.search({"q": "deadline"})

        self.assertEqual(
            (status, payload), (504, {"error": "search deadline exceeded"})
        )
        self.assertEqual(calls, 1)

    def test_provider_requests_are_globally_serialized(self) -> None:
        entered = threading.Event()
        release = threading.Event()
        state_lock = threading.Lock()
        active = 0
        maximum_active = 0

        def blocking_fetcher(url: str, timeout: float) -> bytes:
            nonlocal active, maximum_active
            with state_lock:
                active += 1
                maximum_active = max(maximum_active, active)
                entered.set()
            release.wait(timeout=1)
            with state_lock:
                active -= 1
            return response("1", "2", "3", "4", "5")

        gateway = SearchGateway(settings(), blocking_fetcher)
        outputs: list[tuple[int, dict[str, object]]] = []
        threads = [
            threading.Thread(
                target=lambda q=q: outputs.append(gateway.search({"q": q}))
            )
            for q in ("first", "second")
        ]
        threads[0].start()
        self.assertTrue(entered.wait(timeout=1))
        threads[1].start()
        time.sleep(0.05)
        self.assertEqual(maximum_active, 1)
        release.set()
        for thread in threads:
            thread.join(timeout=1)

        self.assertEqual(maximum_active, 1)
        self.assertEqual([output[0] for output in outputs], [200, 200])

    def test_query_validation_rejects_invalid_values(self) -> None:
        invalid = ("", "q=", f"q={'x' * 1001}", "q=%FF", "q=ok&format=html", "q=a&q=b")
        for raw_query in invalid:
            with self.subTest(raw_query=raw_query[:30]), self.assertRaises(ValueError):
                parse_search_query(raw_query)
        self.assertEqual(len(parse_search_query(f"q={'x' * 1000}")["q"]), 1000)

    def test_settings_load_requested_calibration_environment(self) -> None:
        environment = {
            "SEARXNG_URL": "http://internal:8080/search",
            "SEARCH_GATEWAY_JA_ROUTE": "ja-one,ja-two",
            "SEARCH_GATEWAY_OTHER_ROUTE": "other-one",
            "SEARCH_GATEWAY_RESULT_THRESHOLD": "3",
            "SEARCH_GATEWAY_PROVIDER_INTERVAL_SECONDS": "4",
            "SEARCH_GATEWAY_LONG_COOLDOWN_SECONDS": "500",
            "SEARCH_GATEWAY_BACKOFF_BASE_SECONDS": "6",
            "SEARCH_GATEWAY_BACKOFF_MAX_SECONDS": "60",
            "SEARCH_GATEWAY_UPSTREAM_TIMEOUT_SECONDS": "7",
            "SEARCH_GATEWAY_DEADLINE_SECONDS": "8",
            "SEARCH_GATEWAY_CACHE_TTL_SECONDS": "9",
            "SEARCH_GATEWAY_CACHE_MAX_ENTRIES": "12",
        }
        with patch.dict(os.environ, environment, clear=True):
            configured = Settings.from_environment()

        self.assertEqual(configured.upstream_url, environment["SEARXNG_URL"])
        self.assertEqual(configured.japanese_route, ("ja-one", "ja-two"))
        self.assertEqual(configured.other_route, ("other-one",))
        self.assertEqual(
            (
                configured.result_threshold,
                configured.provider_interval,
                configured.long_cooldown,
                configured.backoff_base,
                configured.backoff_max,
                configured.upstream_timeout,
                configured.global_deadline,
                configured.cache_ttl,
                configured.cache_max_entries,
            ),
            (3, 4, 500, 6, 60, 7, 8, 9, 12),
        )

    def test_cache_environment_rejects_non_finite_or_non_positive_values(self) -> None:
        invalid_environments = (
            {"SEARCH_GATEWAY_CACHE_TTL_SECONDS": "nan"},
            {"SEARCH_GATEWAY_CACHE_TTL_SECONDS": "0"},
            {"SEARCH_GATEWAY_CACHE_MAX_ENTRIES": "0"},
            {"SEARCH_GATEWAY_CACHE_MAX_ENTRIES": "not-an-integer"},
        )
        for environment in invalid_environments:
            with (
                self.subTest(environment=environment),
                patch.dict(os.environ, environment, clear=True),
                self.assertRaises(ValueError),
            ):
                Settings.from_environment()


class SearchGatewayHTTPTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fetcher = FakeFetcher(
            {
                "mwmbl": TimeoutError(),
                "bing": TimeoutError(),
                "duckduckgo": TimeoutError(),
            }
        )
        gateway = SearchGateway(
            settings(upstream_url="http://searxng:8080/search?token=upstream-secret"),
            self.fetcher,
        )
        self.server = make_server(address=("127.0.0.1", 0), gateway=gateway)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)

    def request(
        self, path: str, method: str = "GET"
    ) -> tuple[int, bytes, dict[str, str]]:
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_address[1]}{path}",
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=2) as response_object:
                return (
                    response_object.status,
                    response_object.read(),
                    dict(response_object.headers),
                )
        except urllib.error.HTTPError as error:
            body = error.read()
            headers = dict(error.headers)
            status = error.code
            error.close()
            return status, body, headers

    def test_health_status_and_get_only_contract(self) -> None:
        health_status, health_body, _ = self.request("/health")
        status_status, status_body, _ = self.request("/status")
        method_status, _, method_headers = self.request("/search?q=ok", "POST")

        self.assertEqual(
            (health_status, json.loads(health_body)), (200, {"status": True})
        )
        status_payload = json.loads(status_body)
        self.assertEqual(status_status, 200)
        self.assertEqual(status_payload["status"], True)
        self.assertEqual(
            set(status_payload["providers"]["mwmbl"]),
            {"last_request", "failure_count", "open_until", "reason"},
        )
        self.assertEqual(method_status, 405)
        self.assertEqual(method_headers["Allow"], "GET")

    def test_http_query_validation(self) -> None:
        paths = (
            "/search",
            "/search?q=",
            f"/search?{urlencode({'q': 'x' * 1001})}",
            "/search?q=%FF",
            "/search?q=ok&format=html",
        )
        for path in paths:
            with self.subTest(path=path[:40]):
                status, body, _ = self.request(path)
                self.assertEqual(status, 400)
                self.assertNotIn(b"x" * 50, body)

    def test_http_json_round_trips_lone_surrogate_and_japanese(self) -> None:
        payload: dict[str, object] = {
            "results": [
                {
                    "url": "https://example.invalid",
                    "title": "日本語",
                    "content": "lone surrogate: \ud800",
                }
            ]
        }
        with patch.object(
            self.server.RequestHandlerClass.gateway,
            "search",
            return_value=(200, payload),
        ):
            status, body, headers = self.request("/search?q=unicode")

        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body.decode("utf-8")), payload)
        self.assertEqual(int(headers["Content-Length"]), len(body))

    def test_query_and_upstream_secret_never_appear_in_logs_status_or_errors(
        self,
    ) -> None:
        secret_query = "private-query-9f9d"
        with self.assertLogs("search-gateway", level="INFO") as captured:
            search_status, error_body, _ = self.request(
                f"/search?{urlencode({'q': secret_query, 'format': 'json'})}"
            )
        _, status_body, _ = self.request("/status")

        combined_logs = "\n".join(captured.output)
        self.assertEqual(search_status, 503)
        for output in (combined_logs.encode(), error_body, status_body):
            self.assertNotIn(secret_query.encode(), output)
            self.assertNotIn(b"upstream-secret", output)


if __name__ == "__main__":
    unittest.main()
