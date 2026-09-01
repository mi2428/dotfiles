"""Behavioral tests for the Computer gateway bootstrap contract."""

from __future__ import annotations

import contextlib
import io
import os
import unittest
import urllib.error
from email.message import Message
from unittest.mock import patch

import bootstrap_cptr as subject


class FakeClient:
    def __init__(self, *, needs_setup: bool, gateway_valid: bool) -> None:
        self.needs_setup = needs_setup
        self.gateway_valid = gateway_valid
        self.calls: list[tuple[str, object | None, str | None]] = []

    def request(
        self,
        path: str,
        payload: object | None = None,
        *,
        method: str | None = None,
        headers: object | None = None,
    ) -> subject.Json:
        self.calls.append((path, payload, method))
        if path == "/api/config":
            return {"needs_setup": self.needs_setup}
        if path in {"/api/auth/setup", "/api/auth/login"}:
            return {}
        if path == "/v1/models":
            if self.gateway_valid:
                return {"data": []}
            raise urllib.error.HTTPError(path, 401, "unauthorized", Message(), None)
        if path == "/v1/keys" and payload is None:
            return [
                {"id": "owned/key", "name": "Open WebUI"},
                {"id": "other", "name": "Other"},
            ]
        if path == "/v1/keys" and payload is not None:
            return {"key": "new-key"}
        if method == "DELETE":
            return {}
        raise AssertionError(f"unexpected request: {path}")


class BootstrapComputerTests(unittest.TestCase):
    def run_main(self, client: FakeClient, **environment: str) -> str:
        output = io.StringIO()
        with (
            patch.object(subject, "Client", return_value=client),
            patch.dict(os.environ, environment, clear=True),
            contextlib.redirect_stdout(output),
        ):
            subject.main()
        return output.getvalue()

    def test_valid_gateway_key_is_reused_without_output(self) -> None:
        client = FakeClient(needs_setup=False, gateway_valid=True)

        output = self.run_main(
            client,
            WEBUI_ADMIN_USERNAME="admin",
            WEBUI_ADMIN_PASSWORD="password",
            CPTR_GATEWAY_API_KEY="current-key",
        )

        self.assertEqual(output, "")
        self.assertEqual(
            [path for path, _payload, _method in client.calls],
            ["/api/config", "/api/auth/login", "/v1/models"],
        )

    def test_setup_and_rejected_key_create_one_named_replacement(self) -> None:
        client = FakeClient(needs_setup=True, gateway_valid=False)

        output = self.run_main(
            client,
            WEBUI_ADMIN_USERNAME="admin",
            WEBUI_ADMIN_PASSWORD="password",
            CPTR_STARTUP_TOKEN="startup-token",
            CPTR_GATEWAY_API_KEY="stale-key",
        )

        self.assertEqual(output, "new-key\n")
        self.assertIn(
            (
                "/api/auth/setup",
                {
                    "username": "admin",
                    "password": "password",
                    "token": "startup-token",
                },
                None,
            ),
            client.calls,
        )
        self.assertIn(("/v1/keys/owned%2Fkey", None, "DELETE"), client.calls)
        self.assertNotIn(("/v1/keys/other", None, "DELETE"), client.calls)
        self.assertIn(("/v1/keys", {"name": "Open WebUI"}, None), client.calls)


if __name__ == "__main__":
    unittest.main()
