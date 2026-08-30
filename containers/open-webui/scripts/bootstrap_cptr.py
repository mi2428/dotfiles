"""Provision Open WebUI access to the local Computer gateway."""

from __future__ import annotations

import http.cookiejar
import json
import os
import time
import urllib.error
import urllib.request
from collections.abc import Mapping
from typing import Final, TypeAlias, cast
from urllib.parse import quote

Json: TypeAlias = dict[str, "Json"] | list["Json"] | str | int | float | bool | None
BASE_URL: Final = "http://127.0.0.1:8000"


class Client:
    """Cookie-preserving JSON client for the Computer API."""

    def __init__(self) -> None:
        cookies = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(cookies)
        )

    def request(
        self,
        path: str,
        payload: object | None = None,
        *,
        method: str | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Json:
        """Send one authenticated-session request and decode its JSON response."""
        request_headers = {"Content-Type": "application/json", **(headers or {})}
        request = urllib.request.Request(
            f"{BASE_URL}{path}",
            data=json.dumps(payload).encode() if payload is not None else None,
            method=method,
            headers=request_headers,
        )
        with self._opener.open(request, timeout=5) as response:
            return cast(Json, json.load(response))


def as_object(value: Json, endpoint: str) -> dict[str, Json]:
    """Require an object response from an endpoint."""
    if not isinstance(value, dict):
        raise TypeError(f"{endpoint} returned {type(value).__name__}, expected object")
    return value


def wait_for_config(client: Client) -> dict[str, Json]:
    """Wait until Computer exposes its setup state."""
    for _ in range(60):
        try:
            return as_object(client.request("/api/config"), "/api/config")
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            time.sleep(1)
    raise TimeoutError("Computer did not become ready")


def main() -> None:
    """Set up Computer and print a replacement gateway key only when required."""
    client = Client()
    username = os.environ["WEBUI_ADMIN_USERNAME"]
    password = os.environ["WEBUI_ADMIN_PASSWORD"]

    if wait_for_config(client).get("needs_setup") is True:
        token = os.environ["CPTR_STARTUP_TOKEN"]
        if not token:
            raise RuntimeError("Computer startup token was not found")
        client.request(
            "/api/auth/setup",
            {"username": username, "password": password, "token": token},
        )

    client.request("/api/auth/login", {"username": username, "password": password})
    gateway_key = os.environ.get("CPTR_GATEWAY_API_KEY", "")
    try:
        client.request("/v1/models", headers={"Authorization": f"Bearer {gateway_key}"})
        return
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise

    keys = client.request("/v1/keys")
    if not isinstance(keys, list):
        raise TypeError("/v1/keys did not return a list")
    for key in keys:
        if isinstance(key, dict) and key.get("name") == "Open WebUI":
            client.request(
                f"/v1/keys/{quote(str(key['id']), safe='')}", method="DELETE"
            )

    created = as_object(client.request("/v1/keys", {"name": "Open WebUI"}), "/v1/keys")
    key = created.get("key")
    if not isinstance(key, str):
        raise TypeError("/v1/keys response omitted the key")
    print(key)


if __name__ == "__main__":
    main()
