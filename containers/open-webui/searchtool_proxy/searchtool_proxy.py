"""Search with DDGS first; use Sakura Search Tool only when DDGS fails."""

from __future__ import annotations

import hmac
import json
import logging
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import ClassVar, Final, TypedDict
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from ddgs import DDGS
from ddgs.exceptions import DDGSException, RatelimitException

SEARCHTOOL_URL: Final = "http://sakura-ai-engine-searchtool:8081/search"
MAX_REQUEST_BYTES: Final = 64 * 1024
MAX_QUERY_BYTES: Final = 2048
REQUEST_TIMEOUT: Final = 120
DDGS_COOLDOWN: Final = 300
ddgs_retry_after = 0.0

logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
logger = logging.getLogger(__name__)


class SearchResult(TypedDict):
    """Result shape expected by Open WebUI's External Search backend."""

    title: str
    link: str
    snippet: str


def decode_search_request(body: bytes) -> tuple[str, int]:
    """Validate and normalize the query/count JSON sent by Open WebUI."""
    payload = json.loads(body)
    if not isinstance(payload, dict) or payload.keys() - {"query", "count"}:
        raise ValueError("expected query and count fields")

    query = payload.get("query")
    count = payload.get("count")
    if (
        not isinstance(query, str)
        or not query.strip()
        or len(query.strip().encode()) > MAX_QUERY_BYTES
    ):
        raise ValueError("query must contain 1-2048 bytes")
    if type(count) is not int or not 0 <= count <= 20:
        raise ValueError("count must be an integer from 0 to 20")
    return query.strip(), count


def bearer_token_matches(header: str, token: str) -> bool:
    """Compare a Bearer header with the shared Search Tool client token."""
    scheme, separator, supplied = header.partition(" ")
    return (
        bool(separator)
        and scheme.casefold() == "bearer"
        and hmac.compare_digest(supplied, token)
    )


def search_tool(query: str, count: int, token: str) -> list[SearchResult]:
    """Query Search Tool and unwrap its results envelope for Open WebUI."""
    body = json.dumps({"query": query, "count": count}).encode()
    request = Request(
        SEARCHTOOL_URL,
        data=body,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        payload = json.loads(response.read())

    if not isinstance(payload, dict) or not isinstance(payload.get("results"), list):
        raise TypeError("Search Tool returned an invalid response")
    results: list[SearchResult] = []
    for result in payload["results"]:
        if not isinstance(result, dict):
            raise TypeError("Search Tool returned an invalid result")
        title, link, snippet = (
            result.get("title"),
            result.get("link"),
            result.get("snippet"),
        )
        if (
            not isinstance(title, str)
            or not isinstance(link, str)
            or not isinstance(snippet, str)
        ):
            raise TypeError("Search Tool returned an invalid result")
        results.append({"title": title, "link": link, "snippet": snippet})
    return results


def search(query: str, count: int, token: str) -> list[SearchResult]:
    """Save keyed search requests when DDGS returns usable results."""
    global ddgs_retry_after
    if count == 0:
        return []
    if time.monotonic() < ddgs_retry_after:
        return search_tool(query, count, token)
    try:
        results = DDGS(timeout=10).text(query, max_results=count, backend="auto")
        normalized: list[SearchResult] = []
        for row in results:
            title, link, snippet = row["title"], row["href"], row["body"]
            if not all(isinstance(value, str) for value in (title, link, snippet)):
                raise TypeError("DDGS returned an invalid result")
            parsed = urlsplit(link)
            if (
                not title.strip()
                or parsed.scheme not in ("http", "https")
                or not parsed.netloc
            ):
                raise ValueError("DDGS returned an invalid link")
            normalized.append({"title": title, "link": link, "snippet": snippet})
        if normalized:
            return normalized
    except (DDGSException, OSError, KeyError, TypeError, ValueError) as error:
        logger.warning("DDGS search failed (%s)", type(error).__name__)
        if isinstance(error, RatelimitException):
            ddgs_retry_after = time.monotonic() + DDGS_COOLDOWN
    return search_tool(query, count, token)


class ProxyHandler(BaseHTTPRequestHandler):
    """Serve authenticated Open WebUI external-search requests."""

    client_token: ClassVar[str] = ""

    def do_POST(self) -> None:
        """Forward a valid search request and return the adapted results list."""
        if self.path != "/search":
            self._send_json(404, {"error": "not_found"})
            return
        if not bearer_token_matches(
            self.headers.get("Authorization", ""), self.client_token
        ):
            self._send_json(401, {"error": "unauthorized"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self._send_json(400, {"error": "invalid_content_length"})
            return
        if content_length < 1:
            self._send_json(400, {"error": "empty_request"})
            return
        if content_length > MAX_REQUEST_BYTES:
            self._send_json(413, {"error": "request_too_large"})
            return

        try:
            query, count = decode_search_request(self.rfile.read(content_length))
        except ValueError:
            self._send_json(400, {"error": "invalid_request"})
            return

        try:
            results = search(query, count, self.client_token)
        except (OSError, TypeError, ValueError) as error:
            logger.warning("Search Tool request failed (%s)", type(error).__name__)
            self._send_json(502, {"error": "search_tool_unavailable"})
            return
        self._send_json(200, results)

    def _send_json(self, status: int, payload: object) -> None:
        """Write a JSON response with an explicit content length."""
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    """Validate the shared token and serve the local search adapter."""
    token = os.environ.get("SEARCHTOOL_CLIENT_TOKEN", "")
    if not 32 <= len(token.encode()) <= 4096 or any(
        character.isspace() for character in token
    ):
        raise SystemExit(
            "SEARCHTOOL_CLIENT_TOKEN must be 32-4096 bytes without whitespace"
        )
    ProxyHandler.client_token = token
    with ThreadingHTTPServer(("0.0.0.0", 8082), ProxyHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
