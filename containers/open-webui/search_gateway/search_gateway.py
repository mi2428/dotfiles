"""Serial, dependency-free SearXNG search gateway for Open WebUI."""

from __future__ import annotations

import json
import logging
import math
import os
import threading
import time
import unicodedata
from collections import OrderedDict
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import ClassVar
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

LOG = logging.getLogger("search-gateway")
LISTEN_ADDRESS = ("0.0.0.0", 8082)
CACHE_TTL_SECONDS = 15 * 60
CACHE_MAX_ENTRIES = 512
MAX_RESULTS = 10
MAX_UPSTREAM_BYTES = 2 * 1024 * 1024
ALLOWED_PARAMETERS = {
    "q",
    "format",
    "language",
    "pageno",
    "safesearch",
    "time_range",
    "categories",
    "theme",
    "image_proxy",
}
OPTIONAL_PARAMETERS = (
    "language",
    "pageno",
    "safesearch",
    "time_range",
    "categories",
    "theme",
    "image_proxy",
)


@dataclass(frozen=True, slots=True)
class Settings:
    """Runtime settings with only the requested calibration knobs."""

    upstream_url: str = "http://searxng:8080/search"
    japanese_route: tuple[str, ...] = ("wikipedia", "bing", "duckduckgo")
    other_route: tuple[str, ...] = ("mwmbl", "bing", "duckduckgo")
    result_threshold: int = 5
    provider_interval: float = 2.0
    long_cooldown: float = 3600.0
    backoff_base: float = 30.0
    backoff_max: float = 300.0
    upstream_timeout: float = 10.0
    global_deadline: float = 25.0
    cache_ttl: float = CACHE_TTL_SECONDS
    cache_max_entries: int = CACHE_MAX_ENTRIES

    def __post_init__(self) -> None:
        parsed = urlsplit(self.upstream_url)
        routes = (self.japanese_route, self.other_route)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ValueError("SEARXNG_URL must be an absolute HTTP(S) URL")
        if any(
            not route or len(route) > 3 or len(route) != len(set(route))
            for route in routes
        ):
            raise ValueError("search routes must contain one to three unique providers")
        if any(not provider.strip() for route in routes for provider in route):
            raise ValueError("search routes must not contain empty providers")
        if not 1 <= self.result_threshold <= MAX_RESULTS:
            raise ValueError("result threshold must be between 1 and 10")
        timings = (
            self.provider_interval,
            self.long_cooldown,
            self.backoff_base,
            self.backoff_max,
            self.upstream_timeout,
            self.global_deadline,
            self.cache_ttl,
        )
        if (
            not all(math.isfinite(value) for value in timings)
            or self.provider_interval < 0
            or self.long_cooldown <= 0
            or self.backoff_base < 0
            or self.backoff_max < self.backoff_base
            or self.upstream_timeout <= 0
            or self.global_deadline <= 0
            or self.cache_ttl <= 0
            or self.cache_max_entries <= 0
        ):
            raise ValueError("search timing and cache settings are invalid")

    @classmethod
    def from_environment(cls) -> Settings:
        defaults = cls()

        def route(name: str, default: tuple[str, ...]) -> tuple[str, ...]:
            raw = os.getenv(name)
            if raw is None:
                return default
            return tuple(provider.strip() for provider in raw.split(","))

        return cls(
            upstream_url=os.getenv("SEARXNG_URL", defaults.upstream_url),
            japanese_route=route("SEARCH_GATEWAY_JA_ROUTE", defaults.japanese_route),
            other_route=route("SEARCH_GATEWAY_OTHER_ROUTE", defaults.other_route),
            result_threshold=int(
                os.getenv("SEARCH_GATEWAY_RESULT_THRESHOLD", defaults.result_threshold)
            ),
            provider_interval=float(
                os.getenv(
                    "SEARCH_GATEWAY_PROVIDER_INTERVAL_SECONDS",
                    defaults.provider_interval,
                )
            ),
            long_cooldown=float(
                os.getenv(
                    "SEARCH_GATEWAY_LONG_COOLDOWN_SECONDS", defaults.long_cooldown
                )
            ),
            backoff_base=float(
                os.getenv("SEARCH_GATEWAY_BACKOFF_BASE_SECONDS", defaults.backoff_base)
            ),
            backoff_max=float(
                os.getenv("SEARCH_GATEWAY_BACKOFF_MAX_SECONDS", defaults.backoff_max)
            ),
            upstream_timeout=float(
                os.getenv(
                    "SEARCH_GATEWAY_UPSTREAM_TIMEOUT_SECONDS",
                    defaults.upstream_timeout,
                )
            ),
            global_deadline=float(
                os.getenv("SEARCH_GATEWAY_DEADLINE_SECONDS", defaults.global_deadline)
            ),
            cache_ttl=float(
                os.getenv("SEARCH_GATEWAY_CACHE_TTL_SECONDS", defaults.cache_ttl)
            ),
            cache_max_entries=int(
                os.getenv(
                    "SEARCH_GATEWAY_CACHE_MAX_ENTRIES", defaults.cache_max_entries
                )
            ),
        )


@dataclass(slots=True)
class ProviderState:
    last_request: float | None = None
    failure_count: int = 0
    open_until: float = 0.0
    reason: str | None = None


def normalized_query(query: str) -> str:
    """Normalize equivalent queries without changing their search terms."""
    return " ".join(unicodedata.normalize("NFKC", query).split())


def is_japanese(query: str) -> bool:
    """Route text containing kanji, hiragana, or katakana as Japanese."""
    return any(
        "\u3400" <= character <= "\u4dbf"
        or "\u4e00" <= character <= "\u9fff"
        or "\uf900" <= character <= "\ufaff"
        or "\u3040" <= character <= "\u30ff"
        or "\u31f0" <= character <= "\u31ff"
        or "\uff66" <= character <= "\uff9f"
        or "\U0001b000" <= character <= "\U0001b16f"
        or "\U00020000" <= character <= "\U000323af"
        for character in query
    )


def validate_parameters(parameters: Mapping[str, str]) -> dict[str, str]:
    """Validate and reduce caller input to SearXNG-compatible parameters."""
    query = parameters.get("q")
    if query is None or not 1 <= len(query) <= 1000 or not query.strip():
        raise ValueError("query must contain between 1 and 1000 characters")
    if parameters.get("format", "json").casefold() != "json":
        raise ValueError("format must be json")
    clean = {
        name: value
        for name, value in parameters.items()
        if name in ALLOWED_PARAMETERS and isinstance(value, str)
    }
    clean["q"] = normalized_query(query)
    clean["format"] = "json"
    return clean


def parse_search_query(raw_query: str) -> dict[str, str]:
    """Strictly decode a bounded set of UTF-8 query-string fields."""
    try:
        values = parse_qs(
            raw_query,
            keep_blank_values=True,
            encoding="utf-8",
            errors="strict",
            max_num_fields=20,
        )
    except (UnicodeDecodeError, ValueError) as error:
        raise ValueError("invalid query string") from error
    if len(values.get("q", [])) != 1 or len(values.get("format", [])) > 1:
        raise ValueError("query must occur exactly once")
    return validate_parameters(
        {name: entries[-1] for name, entries in values.items() if entries}
    )


def fetch_url(url: str, timeout: float) -> bytes:
    """Fetch one bounded JSON response from the internal SearXNG service."""
    request = Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "search-gateway/1"},
    )
    with urlopen(request, timeout=timeout) as response:
        body = response.read(MAX_UPSTREAM_BYTES + 1)
    if len(body) > MAX_UPSTREAM_BYTES:
        raise ValueError("upstream response too large")
    return body


def unresponsive_reason(payload: dict[str, object], provider: str) -> str | None:
    """Classify SearXNG's unresponsive_engines entry for one explicit engine."""
    entries = payload.get("unresponsive_engines", [])
    if not isinstance(entries, list):
        return "invalid_response"
    provider_name = provider.casefold()
    for entry in entries:
        name = ""
        details = ""
        if isinstance(entry, (list, tuple)) and entry:
            name = str(entry[0])
            details = " ".join(str(value) for value in entry[1:])
        elif isinstance(entry, dict):
            name = str(entry.get("engine") or entry.get("name") or "")
            details = str(entry.get("reason") or entry.get("error") or "")
        elif isinstance(entry, str) and provider_name in entry.casefold():
            name = provider
            details = entry
        if name.casefold() != provider_name:
            continue
        folded = details.casefold()
        if "captcha" in folded:
            return "captcha"
        if "429" in folded or "rate limit" in folded or "too many request" in folded:
            return "rate_limit"
        if "timeout" in folded:
            return "timeout"
        return "unresponsive"
    return None


class SearchGateway:
    """Own all process-local search, cache, pacing, and breaker state."""

    def __init__(
        self,
        settings: Settings,
        fetcher: Callable[[str, float], bytes] = fetch_url,
        clock: Callable[[], float] = time.monotonic,
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        self.settings = settings
        self.fetcher = fetcher
        self.clock = clock
        self.sleeper = sleeper
        providers = dict.fromkeys(settings.japanese_route + settings.other_route)
        self.providers = {provider: ProviderState() for provider in providers}
        self.cache: OrderedDict[tuple[str, str], tuple[float, list[dict[str, str]]]] = (
            OrderedDict()
        )
        # ponytail: one process-wide lock and in-memory state are intentional;
        # use shared storage/coordination only when multiple replicas are required.
        self.search_lock = threading.Lock()

    def search(self, parameters: Mapping[str, str]) -> tuple[int, dict[str, object]]:
        """Run one globally serialized search within its end-to-end deadline."""
        clean = validate_parameters(parameters)
        deadline = self.clock() + self.settings.global_deadline
        remaining = deadline - self.clock()
        if remaining <= 0 or not self.search_lock.acquire(timeout=remaining):
            return self._error(504, "search deadline exceeded")
        try:
            if self.clock() >= deadline:
                return self._error(504, "search deadline exceeded")
            return self._search_locked(clean, deadline)
        finally:
            self.search_lock.release()

    def status(self) -> dict[str, object]:
        """Return aggregate state without URLs, secrets, or past queries."""
        with self.search_lock:
            now = self.clock()
            self._purge_cache(now)
            return {
                "status": True,
                "cache": {
                    "entries": len(self.cache),
                    "capacity": self.settings.cache_max_entries,
                    "ttl_seconds": self.settings.cache_ttl,
                },
                "providers": {
                    provider: {
                        "last_request": state.last_request,
                        "failure_count": state.failure_count,
                        "open_until": state.open_until,
                        "reason": state.reason,
                    }
                    for provider, state in self.providers.items()
                },
            }

    def _search_locked(
        self, parameters: dict[str, str], deadline: float
    ) -> tuple[int, dict[str, object]]:
        key = (
            parameters["q"].casefold(),
            normalized_query(parameters.get("language", "")).casefold(),
        )
        cached = self._cache_get(key, self.clock())
        if cached is not None:
            LOG.info("cache=hit results=%d", len(cached))
            return 200, {"results": cached}
        LOG.info("cache=miss")

        route = (
            self.settings.japanese_route
            if is_japanese(parameters["q"])
            else self.settings.other_route
        )
        results: list[dict[str, str]] = []
        seen_urls: set[str] = set()
        healthy_providers = 0
        for provider in route[:3]:
            now = self.clock()
            if now >= deadline:
                return self._error(504, "search deadline exceeded")
            state = self.providers[provider]
            if state.open_until > now:
                LOG.info("provider=%s outcome=cooldown", provider)
                continue
            if state.last_request is not None:
                wait = state.last_request + self.settings.provider_interval - now
                if wait > 0:
                    if now + wait >= deadline:
                        return self._error(504, "search deadline exceeded")
                    self.sleeper(wait)
                    if self.clock() >= deadline:
                        return self._error(504, "search deadline exceeded")

            state.last_request = self.clock()
            remaining = deadline - state.last_request
            if remaining <= 0:
                return self._error(504, "search deadline exceeded")
            healthy, provider_results = self._attempt_provider(
                provider,
                parameters,
                min(self.settings.upstream_timeout, remaining),
                deadline,
            )
            if self.clock() >= deadline:
                return self._error(504, "search deadline exceeded")
            if not healthy:
                continue
            healthy_providers += 1
            for result in provider_results:
                if result["url"] in seen_urls:
                    continue
                seen_urls.add(result["url"])
                results.append(result)
                if len(results) == MAX_RESULTS:
                    break
            if len(results) >= self.settings.result_threshold:
                break

        if results or healthy_providers:
            self._cache_put(key, results, self.clock())
            LOG.info(
                "search=complete results=%d healthy_providers=%d",
                len(results),
                healthy_providers,
            )
            return 200, {"results": [result.copy() for result in results]}
        return self._error(503, "all search providers unavailable")

    def _attempt_provider(
        self,
        provider: str,
        parameters: dict[str, str],
        timeout: float,
        deadline: float,
    ) -> tuple[bool, list[dict[str, str]]]:
        url = self._provider_url(provider, parameters)
        try:
            body = self.fetcher(url, timeout)
        except HTTPError as error:
            try:
                error_body = error.read(MAX_UPSTREAM_BYTES + 1)
            except OSError:
                error_body = b""
            finally:
                error.close()
            folded = error_body.lower()
            if error.code == 429:
                reason = "rate_limit"
            elif b"captcha" in folded:
                reason = "captcha"
            elif error.code in {408, 504}:
                reason = "timeout"
            else:
                reason = "server_error" if error.code >= 500 else "http_error"
            self._fail(provider, reason)
            return False, []
        except TimeoutError:
            self._fail(provider, "timeout")
            return False, []
        except URLError as error:
            reason = (
                "timeout"
                if isinstance(error.reason, TimeoutError)
                else "transport_error"
            )
            self._fail(provider, reason)
            return False, []
        except OSError:
            self._fail(provider, "transport_error")
            return False, []
        except ValueError:
            self._fail(provider, "invalid_response")
            return False, []

        if self.clock() >= deadline:
            self._fail(provider, "timeout")
            return False, []
        try:
            payload = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._fail(provider, "invalid_response")
            return False, []
        if not isinstance(payload, dict):
            self._fail(provider, "invalid_response")
            return False, []
        reason = unresponsive_reason(payload, provider)
        if reason is not None:
            self._fail(provider, reason)
            return False, []
        raw_results = payload.get("results")
        if not isinstance(raw_results, list):
            self._fail(provider, "invalid_response")
            return False, []

        self._succeed(provider)
        results = []
        for item in raw_results:
            if not isinstance(item, dict):
                continue
            url_value = item.get("url")
            if not isinstance(url_value, str) or not (url_value := url_value.strip()):
                continue
            title = item.get("title")
            content = item.get("content")
            results.append(
                {
                    "url": url_value,
                    "title": title if isinstance(title, str) else "",
                    "content": content if isinstance(content, str) else "",
                }
            )
            if len(results) == MAX_RESULTS:
                break
        LOG.info("provider=%s outcome=healthy results=%d", provider, len(results))
        return True, results

    def _provider_url(self, provider: str, parameters: dict[str, str]) -> str:
        parsed = urlsplit(self.settings.upstream_url)
        controlled = ALLOWED_PARAMETERS | {"engines"}
        query = [
            (name, value)
            for name, value in parse_qsl(parsed.query, keep_blank_values=True)
            if name not in controlled
        ]
        query.extend((("q", parameters["q"]), ("format", "json")))
        query.extend(
            (name, parameters[name])
            for name in OPTIONAL_PARAMETERS
            if name in parameters
        )
        query.append(("engines", provider))
        return urlunsplit(parsed._replace(query=urlencode(query), fragment=""))

    def _fail(self, provider: str, reason: str) -> None:
        state = self.providers[provider]
        state.failure_count += 1
        if reason in {"captcha", "rate_limit"}:
            delay = self.settings.long_cooldown
        else:
            exponent = min(state.failure_count - 1, 30)
            delay = min(
                self.settings.backoff_max,
                self.settings.backoff_base * (2**exponent),
            )
        state.open_until = max(state.open_until, self.clock() + delay)
        state.reason = reason
        LOG.info(
            "provider=%s outcome=%s failures=%d cooldown_seconds=%.3f",
            provider,
            reason,
            state.failure_count,
            delay,
        )

    def _succeed(self, provider: str) -> None:
        state = self.providers[provider]
        state.failure_count = 0
        state.open_until = 0.0
        state.reason = None

    def _cache_get(
        self, key: tuple[str, str], now: float
    ) -> list[dict[str, str]] | None:
        entry = self.cache.get(key)
        if entry is None:
            return None
        created, results = entry
        if created + self.settings.cache_ttl <= now:
            del self.cache[key]
            return None
        self.cache.move_to_end(key)
        return [result.copy() for result in results]

    def _cache_put(
        self, key: tuple[str, str], results: list[dict[str, str]], now: float
    ) -> None:
        self._purge_cache(now)
        self.cache[key] = (now, [result.copy() for result in results])
        self.cache.move_to_end(key)
        while len(self.cache) > self.settings.cache_max_entries:
            self.cache.popitem(last=False)

    def _purge_cache(self, now: float) -> None:
        for key, (created, _) in tuple(self.cache.items()):
            if created + self.settings.cache_ttl <= now:
                del self.cache[key]

    @staticmethod
    def _error(status: int, message: str) -> tuple[int, dict[str, object]]:
        return status, {"error": message}


class SearchHandler(BaseHTTPRequestHandler):
    """Expose only query-safe GET endpoints."""

    protocol_version = "HTTP/1.1"
    gateway: ClassVar[SearchGateway]

    def do_GET(self) -> None:
        try:
            parsed = urlsplit(self.path)
        except ValueError:
            self._send_json(400, {"error": "invalid request target"})
            return
        if parsed.path == "/health":
            self._send_json(200, {"status": True})
            return
        if parsed.path == "/status":
            self._send_json(200, self.gateway.status())
            return
        if parsed.path != "/search":
            self._send_json(404, {"error": "not found"})
            return
        try:
            parameters = parse_search_query(parsed.query)
        except ValueError:
            self._send_json(400, {"error": "invalid search query"})
            return
        started = time.monotonic()
        status, payload = self.gateway.search(parameters)
        LOG.info(
            "request=search status=%d elapsed_seconds=%.3f",
            status,
            time.monotonic() - started,
        )
        self._send_json(status, payload)

    def _method_not_allowed(self) -> None:
        self._send_json(405, {"error": "method not allowed"}, {"Allow": "GET"})

    do_DELETE = _method_not_allowed
    do_HEAD = _method_not_allowed
    do_OPTIONS = _method_not_allowed
    do_PATCH = _method_not_allowed
    do_POST = _method_not_allowed
    do_PUT = _method_not_allowed

    def _send_json(
        self,
        status: int,
        payload: dict[str, object],
        headers: Mapping[str, str] | None = None,
    ) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def log_message(self, format: str, *args: object) -> None:
        """Suppress request-target logging because /search contains the query."""


def make_server(
    settings: Settings | None = None,
    address: tuple[str, int] = LISTEN_ADDRESS,
    gateway: SearchGateway | None = None,
) -> ThreadingHTTPServer:
    configured_gateway = gateway or SearchGateway(
        settings or Settings.from_environment()
    )
    handler = type(
        "ConfiguredSearchHandler",
        (SearchHandler,),
        {"gateway": configured_gateway},
    )
    return ThreadingHTTPServer(address, handler)


def main() -> None:
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    server = make_server()
    LOG.info("Listening on %s:%d", *server.server_address)
    server.serve_forever()


if __name__ == "__main__":
    main()
