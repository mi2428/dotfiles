"""Serve the internal OpenAI-compatible gateway for Sakura AI Engine.

The proxy replaces caller credentials with round-robin account tokens, preserves streaming,
and retries transient provider failures with one bounded policy. Open WebUI-only status
events require its private header.
"""

from __future__ import annotations

import hmac
import http.client
import json
import logging
import os
import random
import re
import socket
import sqlite3
import ssl
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import SplitResult, urlsplit
from uuid import uuid4

LOG = logging.getLogger("sakura-retry-proxy")
SSL_CONTEXT = ssl.create_default_context()
LISTEN_ADDRESS = ("0.0.0.0", 8080)
TIMEOUT_SAFETY_MARGIN_SECONDS = 300.0
MAX_REQUEST_BYTES = 64 * 1024 * 1024
RESEARCH_PATH = "/research/v1/chat/completions"
RESEARCH_MAX_REQUEST_BYTES = 64 * 1024
RESEARCH_MAX_RESPONSE_BYTES = 4 * 1024 * 1024
RESEARCH_MAX_DEADLINE_MS = 240_000
RESEARCH_ATTEMPT_HEADER = "X-Sakura-Attempt-Id"
RESEARCH_DEADLINE_HEADER = "X-Sakura-Deadline-Unix-Ms"
RESEARCH_SEND_HEADER = "X-Sakura-Upstream-Send"
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
}
TIMEOUT_STATUSES = {408, 504}
RETRYABLE_STATUSES = {408, 409, 429}
RETRYABLE_ERROR_CODES = {
    "internal_error",
    "internal_server_error",
    "overloaded_error",
    "rate_limit_exceeded",
    "server_error",
    "timeout",
}
RETRYABLE_ERROR_MESSAGES = {
    "internal server error",
    "request timed out",
    "server error",
    "upstream timeout",
}
TIMEOUT_RETRY_EFFORTS = {"medium", "high", "max"}
OPENWEBUI_MODE_HEADER = "X-OpenWebUI-Mode"
RETRY_HEADER_NAMES = {
    "x-sakura-retry-count",
    "x-sakura-retry-reason",
    "x-sakura-effective-reasoning-effort",
}
OPENWEBUI_LOW_RETRY_EVENT = (
    "data: "
    + json.dumps(
        {
            "event": {
                "type": "status",
                "data": {"description": "Lowで再試行しました", "done": True},
            }
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    + "\n\n"
).encode()


def retry_after_seconds(value: str | None) -> float | None:
    """Return the delay encoded by a Retry-After value, if valid."""
    if not value:
        return None
    try:
        return max(0.0, float(value))
    except ValueError:
        try:
            return max(0.0, parsedate_to_datetime(value).timestamp() - time.time())
        except (TypeError, ValueError, OverflowError):
            return None


def timeout_retry_body(body: bytes) -> bytes | None:
    """Lower explicit expensive reasoning for retries, preserving unspecified effort."""
    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if "reasoning_effort" not in payload:
        return body
    if payload.get("reasoning_effort") not in TIMEOUT_RETRY_EFFORTS:
        return None
    payload["reasoning_effort"] = "low"
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()


def retryable_response_reason(status: int, prefix: bytes) -> str | None:
    """Classify retryable HTTP and OpenAI-compatible provider responses."""

    if status == 429:
        return "rate_limit"
    if status in TIMEOUT_STATUSES:
        return "timeout"
    if status in RETRYABLE_STATUSES or 500 <= status < 600:
        return "server_error"
    payload = prefix.strip()
    if payload.startswith(b"data:"):
        payload = payload.removeprefix(b"data:").strip()
    try:
        decoded = json.loads(payload)
    except (json.JSONDecodeError, UnicodeDecodeError):
        message = payload.decode(errors="ignore").strip().rstrip(".").casefold()
        return "server_error" if message in RETRYABLE_ERROR_MESSAGES else None
    error = decoded.get("error", {}) if isinstance(decoded, dict) else {}
    if isinstance(error, dict):
        code = str(error.get("code") or error.get("type") or "").casefold()
        message = str(error.get("message") or "").strip().rstrip(".").casefold()
    else:
        code = ""
        message = str(error).strip().rstrip(".").casefold()
    if code == "timeout" or message in {"request timed out", "upstream timeout"}:
        return "timeout"
    if code == "rate_limit_exceeded":
        return "rate_limit"
    if code in RETRYABLE_ERROR_CODES or message in RETRYABLE_ERROR_MESSAGES:
        return "server_error"
    return None


@dataclass(frozen=True, slots=True)
class Settings:
    """Runtime settings for the internal Sakura gateway."""

    upstream_url: str = "https://api.ai.sakura.ad.jp"
    max_retries: int = 5
    base_backoff: float = 10.0
    max_backoff: float = 120.0
    jitter: float = 1.0
    retry_budget: float = 3200.0
    upstream_timeout: float = 420.0
    account_tokens: tuple[str, ...] = ()
    account_ids: tuple[str, ...] = ()
    account_db_path: str = ":memory:"
    research_api_key: str = ""

    def __post_init__(self) -> None:
        if (
            self.max_retries < 0
            or self.base_backoff < 0
            or self.max_backoff < self.base_backoff
            or self.jitter < 0
            or self.upstream_timeout <= 0
            or self.retry_budget <= 0
        ):
            raise ValueError("Sakura timeout settings must be positive")
        if self.account_tokens and (
            len(self.account_ids) != len(self.account_tokens)
            or len(set(self.account_ids)) != len(self.account_ids)
            or any(
                not re.fullmatch(r"[A-Za-z0-9._:@-]{1,200}", value)
                for value in self.account_ids
            )
            or not self.account_db_path
        ):
            raise ValueError(
                "stable account IDs and a shared database are required for every token"
            )
        retry_waits = sum(
            min(self.max_backoff, self.base_backoff * (2**attempt)) + self.jitter
            for attempt in range(self.max_retries)
        )
        if (
            self.retry_budget
            - (self.max_retries + 1) * self.upstream_timeout
            - retry_waits
            < TIMEOUT_SAFETY_MARGIN_SECONDS
        ):
            raise ValueError("Sakura retry budget lacks timeout safety margin")

    @classmethod
    def from_environment(cls) -> Settings:
        """Load overrides from the container environment."""
        defaults = cls()
        account_tokens = tuple(
            token.strip()
            for token in os.getenv("SAKURA_AI_ACCOUNT_TOKENS", "").split(",")
            if token.strip()
        )
        if not account_tokens:
            raise ValueError("SAKURA_AI_ACCOUNT_TOKENS must contain at least one token")
        account_ids = tuple(
            account_id.strip()
            for account_id in os.getenv("SAKURA_AI_ACCOUNT_IDS", "").split(",")
            if account_id.strip()
        )
        account_db_path = os.getenv("DEEP_RESEARCH_DB_PATH", "").strip()
        return cls(
            upstream_url=os.getenv("SAKURA_UPSTREAM_URL", defaults.upstream_url),
            max_retries=int(os.getenv("SAKURA_RETRY_MAX", defaults.max_retries)),
            base_backoff=float(
                os.getenv("SAKURA_RETRY_BASE_SECONDS", defaults.base_backoff)
            ),
            max_backoff=float(
                os.getenv("SAKURA_RETRY_MAX_SECONDS", defaults.max_backoff)
            ),
            jitter=float(os.getenv("SAKURA_RETRY_JITTER_SECONDS", defaults.jitter)),
            retry_budget=float(
                os.getenv("SAKURA_RETRY_BUDGET_SECONDS", defaults.retry_budget)
            ),
            upstream_timeout=float(
                os.getenv("SAKURA_UPSTREAM_TIMEOUT_SECONDS", defaults.upstream_timeout)
            ),
            account_tokens=account_tokens,
            account_ids=account_ids,
            account_db_path=account_db_path,
            research_api_key=os.getenv("SAKURA_RESEARCH_API_KEY", "").strip(),
        )


def retry_delay_seconds(
    settings: Settings, attempt: int, retry_after: float | None
) -> float:
    """Return capped exponential or provider-directed backoff with jitter."""

    exponential = min(settings.max_backoff, settings.base_backoff * (2**attempt))
    directed = min(settings.max_backoff, retry_after or 0.0)
    return max(exponential, directed) + random.uniform(0.0, settings.jitter)


@dataclass(frozen=True, slots=True)
class TokenLease:
    slot: int
    token: str
    account_id: str
    lease_id: str


class DuplicateLeaseError(RuntimeError):
    """A durable research attempt was already admitted or sent."""


class SharedTokenCooldown:
    """SQLite-backed account leases shared by normal and research requests."""

    def __init__(
        self,
        tokens: tuple[str, ...],
        account_ids: tuple[str, ...] = (),
        db_path: str = ":memory:",
    ) -> None:
        if len(tokens) != len(account_ids):
            raise ValueError("stable account IDs must map one-to-one to account tokens")
        self._tokens = tokens
        self._account_ids = account_ids
        self._next_index = 0
        self._condition = threading.Condition()
        if db_path != ":memory:":
            Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(db_path, check_same_thread=False, timeout=5)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA busy_timeout=5000")
        self._db.executescript(
            """
            CREATE TABLE IF NOT EXISTS account_admissions (
                account_id TEXT PRIMARY KEY,
                state TEXT NOT NULL CHECK(state IN ('available', 'cooldown', 'leased', 'send_intent', 'unknown')),
                lease_id TEXT UNIQUE,
                purpose TEXT,
                cooldown_until_ms INTEGER NOT NULL DEFAULT 0,
                updated_at_ms INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS account_admission_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL,
                lease_id TEXT,
                event TEXT NOT NULL,
                actor TEXT NOT NULL,
                action_id TEXT,
                risk_ack TEXT,
                recorded_at_ms INTEGER NOT NULL
            );
            """
        )
        audit_columns = {
            str(row["name"])
            for row in self._db.execute("PRAGMA table_info(account_admission_audit)")
        }
        if "risk_ack" not in audit_columns:
            self._db.execute(
                "ALTER TABLE account_admission_audit ADD COLUMN risk_ack TEXT"
            )
        self._db.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS account_admission_operator_action "
            "ON account_admission_audit(action_id) WHERE action_id IS NOT NULL"
        )
        now = self._unix_ms()
        self._db.execute("BEGIN IMMEDIATE")
        try:
            unresolved = self._db.execute(
                "SELECT account_id FROM account_admissions "
                "WHERE state = 'unknown' AND account_id NOT IN "
                f"({','.join('?' for _ in account_ids) or "''"})",
                account_ids,
            ).fetchone()
            if unresolved is not None:
                raise ValueError(
                    "configured account IDs omit an unresolved durable account"
                )
            for account_id in account_ids:
                self._db.execute(
                    "INSERT OR IGNORE INTO account_admissions "
                    "(account_id, state, cooldown_until_ms, updated_at_ms) "
                    "VALUES (?, 'available', 0, ?)",
                    (account_id, now),
                )
            interrupted = self._db.execute(
                "SELECT account_id, lease_id FROM account_admissions "
                "WHERE account_id IN "
                f"({','.join('?' for _ in account_ids) or "''"}) "
                "AND state IN ('leased', 'send_intent')",
                account_ids,
            ).fetchall()
            self._db.execute(
                "UPDATE account_admissions SET state = 'unknown', updated_at_ms = ? "
                "WHERE account_id IN "
                f"({','.join('?' for _ in account_ids) or "''"}) "
                "AND state IN ('leased', 'send_intent')",
                (now, *account_ids),
            )
            for row in interrupted:
                self._audit(
                    str(row["account_id"]),
                    None if row["lease_id"] is None else str(row["lease_id"]),
                    "restart_unknown",
                    now,
                )
            self._db.commit()
        except BaseException:
            self._db.rollback()
            self._db.close()
            raise

    @staticmethod
    def _unix_ms() -> int:
        return time.time_ns() // 1_000_000

    def _audit(
        self, account_id: str, lease_id: str | None, event: str, now: int
    ) -> None:
        self._db.execute(
            "INSERT INTO account_admission_audit "
            "(account_id, lease_id, event, actor, recorded_at_ms) VALUES (?, ?, ?, 'proxy', ?)",
            (account_id, lease_id, event, now),
        )

    @property
    def _in_flight(self) -> list[bool]:
        rows = {
            str(row["account_id"]): str(row["state"])
            for row in self._db.execute(
                "SELECT account_id, state FROM account_admissions"
            )
        }
        return [
            rows.get(account_id) in {"leased", "send_intent"}
            for account_id in self._account_ids
        ]

    @property
    def _cooldown_until(self) -> list[float]:
        rows = {
            str(row["account_id"]): int(row["cooldown_until_ms"])
            for row in self._db.execute(
                "SELECT account_id, cooldown_until_ms FROM account_admissions"
            )
        }
        now_ms = self._unix_ms()
        now_monotonic = time.monotonic()
        return [
            now_monotonic + max(0, rows.get(account_id, 0) - now_ms) / 1000
            for account_id in self._account_ids
        ]

    def acquire(
        self,
        deadline: float,
        is_cancelled: Callable[[], bool],
        *,
        lease_id: str | None = None,
        purpose: str = "normal",
    ) -> tuple[TokenLease | None, float]:
        if not self._tokens:
            return None, 0.0
        waited = 0.0
        with self._condition:
            while True:
                if is_cancelled():
                    return None, waited
                now = time.monotonic()
                now_ms = self._unix_ms()
                try:
                    self._db.execute("BEGIN IMMEDIATE")
                    if purpose == "research" and lease_id is not None:
                        duplicate = self._db.execute(
                            "SELECT 1 FROM account_admissions WHERE lease_id = ? "
                            "UNION ALL SELECT 1 FROM account_admission_audit "
                            "WHERE lease_id = ? AND event = 'send_intent' LIMIT 1",
                            (lease_id, lease_id),
                        ).fetchone()
                        if duplicate is not None:
                            raise DuplicateLeaseError(
                                "research attempt was already admitted"
                            )
                    acquired: TokenLease | None = None
                    for offset in range(len(self._tokens)):
                        slot = (self._next_index + offset) % len(self._tokens)
                        account_id = self._account_ids[slot]
                        row = self._db.execute(
                            "SELECT state, cooldown_until_ms FROM account_admissions "
                            "WHERE account_id = ?",
                            (account_id,),
                        ).fetchone()
                        available = row is not None and (
                            row["state"] == "available"
                            or (
                                row["state"] == "cooldown"
                                and int(row["cooldown_until_ms"]) <= now_ms
                            )
                        )
                        current_lease_id = lease_id or uuid4().hex
                        changed = (
                            self._db.execute(
                                "UPDATE account_admissions SET state = 'leased', lease_id = ?, "
                                "purpose = ?, cooldown_until_ms = 0, updated_at_ms = ? "
                                "WHERE account_id = ? AND (state = 'available' OR "
                                "(state = 'cooldown' AND cooldown_until_ms <= ?))",
                                (current_lease_id, purpose, now_ms, account_id, now_ms),
                            ).rowcount
                            if available
                            else 0
                        )
                        if changed == 1:
                            acquired = TokenLease(
                                slot,
                                self._tokens[slot],
                                account_id,
                                current_lease_id,
                            )
                            break
                    self._db.commit()
                except BaseException:
                    if self._db.in_transaction:
                        self._db.rollback()
                    raise
                if acquired is not None:
                    self._next_index = (acquired.slot + 1) % len(self._tokens)
                    return acquired, waited
                remaining = deadline - now
                if remaining <= 0:
                    return None, waited
                pause = min(remaining, 0.1)
                start = time.monotonic()
                self._condition.wait(timeout=pause)
                waited += time.monotonic() - start

    def release(self, lease: TokenLease) -> None:
        with self._condition:
            now = self._unix_ms()
            row = self._db.execute(
                "SELECT cooldown_until_ms FROM account_admissions "
                "WHERE account_id = ? AND lease_id = ? AND state IN ('leased', 'send_intent')",
                (lease.account_id, lease.lease_id),
            ).fetchone()
            if row is not None:
                cooldown_until = int(row["cooldown_until_ms"])
                self._db.execute(
                    "UPDATE account_admissions SET state = ?, lease_id = NULL, purpose = NULL, "
                    "updated_at_ms = ? WHERE account_id = ? AND lease_id = ?",
                    (
                        "cooldown" if cooldown_until > now else "available",
                        now,
                        lease.account_id,
                        lease.lease_id,
                    ),
                )
                self._db.commit()
                self._condition.notify_all()

    def schedule(self, slot: int, delay: float) -> float:
        with self._condition:
            scheduled = self._schedule_unlocked(self._account_ids[slot], delay)
            self._condition.notify_all()
            return scheduled

    def schedule_and_release(self, lease: TokenLease, delay: float) -> float:
        with self._condition:
            scheduled = self._schedule_unlocked(lease.account_id, delay)
            self.release(lease)
            self._condition.notify_all()
            return scheduled

    def _schedule_unlocked(self, account_id: str, delay: float) -> float:
        now = self._unix_ms()
        until = now + int(max(0.0, delay) * 1000)
        self._db.execute(
            "UPDATE account_admissions SET state = CASE WHEN state = 'available' "
            "THEN 'cooldown' ELSE state END, "
            "cooldown_until_ms = MAX(cooldown_until_ms, ?), "
            "updated_at_ms = ? WHERE account_id = ?",
            (until, now, account_id),
        )
        self._db.commit()
        row = self._db.execute(
            "SELECT cooldown_until_ms FROM account_admissions WHERE account_id = ?",
            (account_id,),
        ).fetchone()
        return max(0.0, (int(row["cooldown_until_ms"]) - self._unix_ms()) / 1000)

    def mark_send_intent(self, lease: TokenLease) -> None:
        with self._condition:
            now = self._unix_ms()
            changed = self._db.execute(
                "UPDATE account_admissions SET state = 'send_intent', updated_at_ms = ? "
                "WHERE account_id = ? AND lease_id = ? AND state = 'leased'",
                (now, lease.account_id, lease.lease_id),
            ).rowcount
            if changed != 1:
                self._db.rollback()
                raise RuntimeError("durable account lease changed before send")
            self._audit(lease.account_id, lease.lease_id, "send_intent", now)
            self._db.commit()

    def mark_unknown(self, lease: TokenLease) -> None:
        with self._condition:
            now = self._unix_ms()
            changed = self._db.execute(
                "UPDATE account_admissions SET state = 'unknown', updated_at_ms = ? "
                "WHERE account_id = ? AND lease_id = ? AND state IN ('leased', 'send_intent')",
                (now, lease.account_id, lease.lease_id),
            ).rowcount
            if changed == 1:
                self._audit(lease.account_id, lease.lease_id, "unknown", now)
                self._db.commit()
            self._condition.notify_all()

    def state(self, account_id: str) -> sqlite3.Row | None:
        with self._condition:
            return self._db.execute(
                "SELECT * FROM account_admissions WHERE account_id = ?", (account_id,)
            ).fetchone()

    def close(self) -> None:
        with self._condition:
            self._db.close()


class SakuraProxyServer(ThreadingHTTPServer):
    def server_close(self) -> None:
        token_state = getattr(self.RequestHandlerClass, "token_state", None)
        if isinstance(token_state, SharedTokenCooldown):
            token_state.close()
        super().server_close()


class SakuraRetryProxyHandler(BaseHTTPRequestHandler):
    """Forward OpenAI-compatible requests and retry recoverable failures."""

    protocol_version = "HTTP/1.1"
    settings = Settings()
    upstream: SplitResult = urlsplit(settings.upstream_url)
    token_state = SharedTokenCooldown(settings.account_tokens)

    def do_GET(self) -> None:
        """Handle health checks and upstream GET requests."""
        if self.path == RESEARCH_PATH:
            self._research_error(405, self._research_attempt_id(), "not-sent")
            return
        self._proxy()

    def do_POST(self) -> None:
        if self.path == RESEARCH_PATH:
            self._research_proxy()
            return
        self._proxy()

    def log_message(self, format: str, *args: object) -> None:
        """Log requests without flooding logs with health checks."""
        if self.path != "/health":
            LOG.info("%s - %s", self.client_address[0], format % args)

    def _research_attempt_id(self) -> str | None:
        values = self.headers.get_all(RESEARCH_ATTEMPT_HEADER, [])
        if len(values) != 1:
            return None
        value = values[0]
        if not 1 <= len(value) <= 128 or not all(
            character.isascii() and (character.isalnum() or character in "-_.")
            for character in value
        ):
            return None
        return value

    def _research_headers(self, attempt_id: str | None, state: str) -> dict[str, str]:
        headers = {RESEARCH_SEND_HEADER: state}
        if attempt_id is not None:
            headers[RESEARCH_ATTEMPT_HEADER] = attempt_id
        return headers

    def _research_error(self, status: int, attempt_id: str | None, state: str) -> None:
        self.close_connection = True
        try:
            self._send_json(
                status,
                {"error": {"code": "research_transport", "message": "request failed"}},
                self._research_headers(attempt_id, state),
            )
        except (BrokenPipeError, ConnectionResetError, OSError):
            self.close_connection = True

    @staticmethod
    def _valid_research_body(body: bytes) -> bool:
        try:
            payload = json.loads(body)
        except (ValueError, UnicodeDecodeError, RecursionError):
            return False
        if type(payload) is not dict or set(payload) != {
            "max_tokens",
            "messages",
            "model",
            "stream",
            "stream_options",
        }:
            return False
        max_tokens = payload["max_tokens"]
        messages = payload["messages"]
        return (
            type(max_tokens) is int
            and 1 <= max_tokens <= 16_384
            and type(payload["model"]) is str
            and bool(payload["model"])
            and payload["stream"] is True
            and payload["stream_options"] == {"include_usage": True}
            and type(messages) is list
            and len(messages) == 2
            and all(
                type(message) is dict
                and set(message) == {"content", "role"}
                and type(message["content"]) is str
                and message["role"] == role
                for message, role in zip(messages, ("system", "user"), strict=True)
            )
        )

    def _read_research_body(self) -> bytes | None:
        if self.headers.get("Transfer-Encoding"):
            return None
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) != 1:
            return None
        try:
            length = int(lengths[0])
        except ValueError:
            return None
        if not 0 < length <= RESEARCH_MAX_REQUEST_BYTES:
            return None
        body = self.rfile.read(length)
        return body if len(body) == length else None

    @staticmethod
    def _close_connection(connection: http.client.HTTPConnection | None) -> None:
        if connection is None:
            return
        try:
            if connection.sock is not None:
                connection.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()

    def _research_proxy(self) -> None:
        attempt_id = self._research_attempt_id()
        expected = self.settings.research_api_key
        authorizations = self.headers.get_all("Authorization", [])
        if (
            not expected
            or len(authorizations) != 1
            or not hmac.compare_digest(
                authorizations[0].encode(), f"Bearer {expected}".encode()
            )
        ):
            self._research_error(401, attempt_id, "not-sent")
            return
        deadlines = self.headers.get_all(RESEARCH_DEADLINE_HEADER, [])
        if attempt_id is None or len(deadlines) != 1 or not deadlines[0].isascii():
            self._research_error(400, attempt_id, "not-sent")
            return
        try:
            remaining_ms = int(deadlines[0]) - time.time_ns() // 1_000_000
        except ValueError:
            remaining_ms = 0
        if not 0 < remaining_ms <= RESEARCH_MAX_DEADLINE_MS:
            self._research_error(400, attempt_id, "not-sent")
            return
        deadline = time.monotonic() + remaining_ms / 1000
        upstream_connection: http.client.HTTPConnection | None = None

        def expire() -> None:
            self._close_connection(upstream_connection)
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        watchdog = threading.Timer(remaining_ms / 1000, expire)
        watchdog.daemon = True
        watchdog.start()
        lease: TokenLease | None = None
        response: http.client.HTTPResponse | None = None
        sent = False
        unknown = False
        downstream_started = False
        try:
            body = self._read_research_body()
            if body is None or not self._valid_research_body(body):
                self._research_error(400, attempt_id, "not-sent")
                return
            try:
                lease, _shared_wait = type(self).token_state.acquire(
                    deadline,
                    self._client_disconnected,
                    lease_id=attempt_id,
                    purpose="research",
                )
            except DuplicateLeaseError:
                self._research_error(409, attempt_id, "not-sent")
                return
            if lease is None:
                self._research_error(504, attempt_id, "not-sent")
                return
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self._research_error(504, attempt_id, "not-sent")
                return
            host = self.upstream.hostname
            if host is None:
                self._research_error(502, attempt_id, "not-sent")
                return
            if self.upstream.scheme == "https":
                upstream_connection = http.client.HTTPSConnection(
                    host,
                    self.upstream.port,
                    timeout=remaining,
                    context=SSL_CONTEXT,
                )
            else:
                upstream_connection = http.client.HTTPConnection(
                    host, self.upstream.port, timeout=remaining
                )
            headers = {
                "Accept": "text/event-stream",
                "Accept-Encoding": "identity",
                "Authorization": f"Bearer {lease.token}",
                "Content-Length": str(len(body)),
                "Content-Type": "application/json",
                "Host": self.upstream.netloc,
            }
            upstream_connection.connect()
            upstream_connection.auto_open = 0
            remaining = deadline - time.monotonic()
            if (
                remaining <= 0
                or self._client_disconnected()
                or upstream_connection.sock is None
            ):
                raise TimeoutError("research connect deadline")
            upstream_connection.sock.settimeout(remaining)
            type(self).token_state.mark_send_intent(lease)
            sent = True
            upstream_connection.request(
                "POST",
                f"{self.upstream.path.rstrip('/')}/v1/chat/completions",
                body,
                headers,
            )
            response = upstream_connection.getresponse()
            if response.status == 429:
                delay = retry_delay_seconds(
                    self.settings,
                    0,
                    retry_after_seconds(response.getheader("Retry-After")),
                )
                type(self).token_state.schedule(lease.slot, delay)
            declared_length = response.getheader("Content-Length")
            if declared_length is not None:
                try:
                    if int(declared_length) > RESEARCH_MAX_RESPONSE_BYTES:
                        unknown = True
                        self._research_error(502, attempt_id, "unknown")
                        return
                except ValueError:
                    unknown = True
                    self._research_error(502, attempt_id, "unknown")
                    return
            downstream_started = True
            saw_done = self._stream_research(
                upstream_connection, response, attempt_id, deadline
            )
            unknown = 200 <= response.status < 300 and not saw_done
        except (TimeoutError, OSError, http.client.HTTPException):
            unknown = sent
            if downstream_started:
                self.close_connection = True
            else:
                self._research_error(
                    504 if time.monotonic() >= deadline else 502,
                    attempt_id,
                    "unknown" if sent else "not-sent",
                )
        finally:
            watchdog.cancel()
            if lease is not None:
                if unknown:
                    type(self).token_state.mark_unknown(lease)
                else:
                    type(self).token_state.release(lease)
            if response is not None:
                response.close()
            self._close_connection(upstream_connection)
            self.close_connection = True

    def _stream_research(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
        attempt_id: str,
        deadline: float,
    ) -> bool:
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            if name.casefold() not in HOP_BY_HOP_HEADERS | {
                RESEARCH_ATTEMPT_HEADER.casefold(),
                RESEARCH_SEND_HEADER.casefold(),
            }:
                self.send_header(name, value)
        self.send_header(RESEARCH_ATTEMPT_HEADER, attempt_id)
        self.send_header(RESEARCH_SEND_HEADER, "sent")
        self.send_header("Connection", "close")
        self.end_headers()
        received = 0
        line_buffer = b""
        saw_done = False
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("research deadline")
            if connection.sock is not None:
                connection.sock.settimeout(remaining)
            chunk = response.read1(
                min(64 * 1024, RESEARCH_MAX_RESPONSE_BYTES + 1 - received)
            )
            if not chunk:
                return saw_done
            received += len(chunk)
            if received > RESEARCH_MAX_RESPONSE_BYTES:
                raise OSError("research response limit")
            lines = (line_buffer + chunk).split(b"\n")
            line_buffer = lines.pop()
            saw_done = saw_done or any(
                line.strip() in {b"data: [DONE]", b"data:[DONE]"} for line in lines
            )
            if len(line_buffer) > len(b"data: [DONE]"):
                line_buffer = b"!"
            self.wfile.write(chunk)
            self.wfile.flush()

    def _proxy(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
            return
        body = self._read_body()
        if body is None:
            return

        request_body = body
        retry_count = 0
        upstream_attempt = 0
        last_retry_reason: str | None = None
        effective_reasoning_effort = None
        retry_deadline = time.monotonic() + self.settings.retry_budget
        openwebui_mode = (
            self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true"
        )
        correlation_id = uuid4().hex[:12]
        while True:
            connection: http.client.HTTPConnection | None = None
            response: http.client.HTTPResponse | None = None
            lease: TokenLease | None = None
            shared_wait = 0.0
            remaining = retry_deadline - time.monotonic()
            if remaining <= 0:
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None,
                    attempt=upstream_attempt,
                    reason="budget",
                    scheduled=0.0,
                    shared_wait=0.0,
                    status=504,
                )
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(
                        retry_count, last_retry_reason, effective_reasoning_effort
                    ),
                )
                return
            try:
                upstream_attempt += 1
                connection, response, lease, shared_wait = self._request_upstream(
                    request_body,
                    min(self.settings.upstream_timeout, remaining),
                    retry_deadline,
                )
                remaining = retry_deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("retry budget exhausted")
                if connection.sock is not None:
                    connection.sock.settimeout(
                        min(self.settings.upstream_timeout, remaining)
                    )
                prefix = response.readline(64 * 1024)
            except TimeoutError:
                if response is not None:
                    response.close()
                if connection is not None:
                    connection.close()
                if lease is not None:
                    type(self).token_state.release(lease)
                    lease = None
                reason = "timeout"
                delay = retry_delay_seconds(self.settings, retry_count, None)
                if self._can_retry(retry_count, delay, retry_deadline):
                    fallback = timeout_retry_body(request_body)
                    if fallback is not None:
                        if fallback != request_body:
                            effective_reasoning_effort = "low"
                        request_body = fallback
                    retry_count += 1
                    last_retry_reason = reason
                    self._log_event(
                        correlation_id=correlation_id,
                        token_slot=None,
                        attempt=upstream_attempt,
                        reason=reason,
                        scheduled=delay,
                        shared_wait=shared_wait,
                        status="retry",
                    )
                    if not self._wait_for_retry(delay, retry_deadline):
                        self.close_connection = True
                        return
                    continue
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None,
                    attempt=upstream_attempt,
                    reason=reason,
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status=504,
                )
                self._send_json(
                    504,
                    {"error": {"code": "timeout", "message": "upstream timeout"}},
                    self._retry_headers(
                        retry_count, last_retry_reason, effective_reasoning_effort
                    ),
                )
                return
            except BrokenPipeError:
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None if lease is None else lease.slot,
                    attempt=upstream_attempt,
                    reason="client_disconnect",
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status="cancelled",
                )
                self.close_connection = True
                return
            except (OSError, http.client.HTTPException):
                if response is not None:
                    response.close()
                if connection is not None:
                    connection.close()
                if lease is not None:
                    type(self).token_state.release(lease)
                    lease = None
                reason = "upstream_error"
                delay = retry_delay_seconds(self.settings, retry_count, None)
                if self._can_retry(retry_count, delay, retry_deadline):
                    retry_count += 1
                    last_retry_reason = reason
                    self._log_event(
                        correlation_id=correlation_id,
                        token_slot=None,
                        attempt=upstream_attempt,
                        reason=reason,
                        scheduled=delay,
                        shared_wait=shared_wait,
                        status="retry",
                    )
                    if not self._wait_for_retry(delay, retry_deadline):
                        self.close_connection = True
                        return
                    continue
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=None,
                    attempt=upstream_attempt,
                    reason=reason,
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status=502,
                )
                self._send_json(
                    502,
                    {
                        "error": {
                            "code": "server_error",
                            "message": "upstream unavailable",
                        }
                    },
                    self._retry_headers(
                        retry_count, last_retry_reason, effective_reasoning_effort
                    ),
                )
                return

            token_slot = None if lease is None else lease.slot
            reason = retryable_response_reason(response.status, prefix)
            if reason is not None:
                retry_after = (
                    retry_after_seconds(response.getheader("Retry-After"))
                    if reason == "rate_limit"
                    else None
                )
                delay = retry_delay_seconds(self.settings, retry_count, retry_after)
            else:
                delay = 0.0
            if reason is not None and self._can_retry(
                retry_count, delay, retry_deadline
            ):
                if reason == "timeout":
                    fallback = timeout_retry_body(request_body)
                    if fallback is not None:
                        if fallback != request_body:
                            effective_reasoning_effort = "low"
                        request_body = fallback
                response.close()
                connection.close()
                if lease is not None:
                    if reason == "rate_limit":
                        type(self).token_state.schedule_and_release(lease, delay)
                    else:
                        type(self).token_state.release(lease)
                    lease = None
                retry_count += 1
                last_retry_reason = reason
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=token_slot,
                    attempt=upstream_attempt,
                    reason=reason,
                    scheduled=delay,
                    shared_wait=shared_wait,
                    status="retry",
                )
                if not self._wait_for_retry(delay, retry_deadline):
                    self.close_connection = True
                    return
                continue

            if reason is not None and response.status < 400:
                response.close()
                connection.close()
                if lease is not None:
                    type(self).token_state.release(lease)
                status = 504 if reason == "timeout" else 502
                self._log_event(
                    correlation_id=correlation_id,
                    token_slot=token_slot,
                    attempt=upstream_attempt,
                    reason=reason,
                    scheduled=0.0,
                    shared_wait=shared_wait,
                    status=status,
                )
                self._send_json(
                    status,
                    {"error": {"code": reason, "message": "provider retry exhausted"}},
                    self._retry_headers(
                        retry_count, last_retry_reason, effective_reasoning_effort
                    ),
                )
                return

            self._log_event(
                correlation_id=correlation_id,
                token_slot=token_slot,
                attempt=upstream_attempt,
                reason=reason or "response",
                scheduled=0.0,
                shared_wait=shared_wait,
                status=response.status,
            )

            self._stream(
                connection,
                response,
                prefix,
                lease,
                self._retry_headers(
                    retry_count, last_retry_reason, effective_reasoning_effort
                ),
                openwebui_mode and effective_reasoning_effort == "low",
            )
            return

    def _can_retry(self, retry_count: int, delay: float, deadline: float) -> bool:
        return (
            retry_count < self.settings.max_retries
            and delay + self.settings.upstream_timeout <= deadline - time.monotonic()
        )

    def _wait_for_retry(self, delay: float, deadline: float) -> bool:
        target = time.monotonic() + delay
        while time.monotonic() < target:
            if self._client_disconnected() or time.monotonic() >= deadline:
                return False
            time.sleep(min(0.1, target - time.monotonic()))
        return True

    def _read_body(self) -> bytes | None:
        if self.headers.get("Transfer-Encoding"):
            self._send_json(501, {"error": {"message": "chunked request unsupported"}})
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": {"message": "invalid content length"}})
            return None
        if length < 0:
            self._send_json(400, {"error": {"message": "invalid content length"}})
            return None
        if length > MAX_REQUEST_BYTES:
            self._send_json(413, {"error": {"message": "request body too large"}})
            return None
        return self.rfile.read(length) if length else b""

    def _request_upstream(
        self, body: bytes, timeout: float, deadline: float
    ) -> tuple[
        http.client.HTTPConnection,
        http.client.HTTPResponse,
        TokenLease | None,
        float,
    ]:
        host = self.upstream.hostname
        if host is None:
            raise ValueError("upstream host is required")
        if self.upstream.scheme == "https":
            connection: http.client.HTTPConnection = http.client.HTTPSConnection(
                host,
                self.upstream.port,
                timeout=timeout,
                context=SSL_CONTEXT,
            )
        else:
            connection = http.client.HTTPConnection(
                host, self.upstream.port, timeout=timeout
            )
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
            and name.lower()
            not in {
                "authorization",
                "host",
                "content-length",
                OPENWEBUI_MODE_HEADER.casefold(),
            }
        }
        headers["Host"] = self.upstream.netloc
        if self.headers.get(OPENWEBUI_MODE_HEADER, "").casefold() == "true":
            headers["Accept-Encoding"] = "identity"
        lease, shared_wait = type(self).token_state.acquire(
            deadline, self._client_disconnected, purpose="normal"
        )
        if self._client_disconnected():
            if lease is not None:
                type(self).token_state.release(lease)
            connection.close()
            raise BrokenPipeError("client disconnected")
        if lease is None and self.settings.account_tokens:
            connection.close()
            raise TimeoutError("token lease unavailable")
        if lease is not None:
            headers["Authorization"] = f"Bearer {lease.token}"
        if body:
            headers["Content-Length"] = str(len(body))
        send_intent = False
        try:
            if lease is not None:
                type(self).token_state.mark_send_intent(lease)
                send_intent = True
            connection.request(
                self.command,
                f"{self.upstream.path.rstrip('/')}{self.path}",
                body,
                headers,
            )
            return connection, connection.getresponse(), lease, shared_wait
        except Exception:
            if lease is not None:
                if send_intent:
                    type(self).token_state.mark_unknown(lease)
                else:
                    type(self).token_state.release(lease)
            connection.close()
            raise

    def _client_disconnected(self) -> bool:
        try:
            if getattr(self.wfile, "closed", False):
                return True
            return self.connection is not None and self.connection.fileno() < 0
        except OSError:
            return True

    def _log_event(
        self,
        *,
        correlation_id: str,
        token_slot: int | None,
        attempt: int,
        reason: str,
        scheduled: float,
        shared_wait: float,
        status: int | str,
    ) -> None:
        LOG.info(
            "correlation=%s token_slot=%s attempt=%d reason=%s scheduled=%.3f shared_wait=%.3f status=%s",
            correlation_id,
            "-" if token_slot is None else token_slot,
            attempt,
            reason,
            scheduled,
            shared_wait,
            status,
        )

    @staticmethod
    def _retry_headers(
        retry_count: int,
        retry_reason: str | None,
        effective_effort: str | None,
    ) -> dict[str, str]:
        if retry_count <= 0:
            return {}
        headers = {
            "X-Sakura-Retry-Count": str(retry_count),
            "X-Sakura-Retry-Reason": retry_reason or "provider_error",
        }
        if effective_effort:
            headers["X-Sakura-Effective-Reasoning-Effort"] = effective_effort
        return headers

    def _stream(
        self,
        connection: http.client.HTTPConnection,
        response: http.client.HTTPResponse,
        prefix: bytes = b"",
        lease: TokenLease | None = None,
        extra_headers: dict[str, str] | None = None,
        openwebui_retry_status: bool = False,
    ) -> None:
        extra_headers = extra_headers or {}
        status_event = (
            OPENWEBUI_LOW_RETRY_EVENT
            if openwebui_retry_status
            and response.getheader("Content-Type", "")
            .casefold()
            .startswith("text/event-stream")
            else b""
        )
        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            lower_name = name.lower()
            if (
                lower_name not in HOP_BY_HOP_HEADERS
                and lower_name not in RETRY_HEADER_NAMES
                and not (status_event and lower_name == "content-length")
            ):
                self.send_header(name, value)
        for name, value in extra_headers.items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            if status_event:
                self.wfile.write(status_event)
                self.wfile.flush()
            if prefix:
                self.wfile.write(prefix)
                self.wfile.flush()
            while chunk := response.read(64 * 1024):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            if lease is not None:
                type(self).token_state.release(lease)
            response.close()
            connection.close()
            self.close_connection = True

    def _send_json(
        self,
        status: int,
        payload: dict[str, object],
        headers: dict[str, str] | None = None,
    ) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True


def make_server(
    settings: Settings, address: tuple[str, int] = LISTEN_ADDRESS
) -> ThreadingHTTPServer:
    """Build a threaded gateway bound according to settings."""
    upstream = urlsplit(settings.upstream_url)
    if upstream.scheme not in {"http", "https"} or not upstream.hostname:
        raise ValueError("SAKURA_UPSTREAM_URL must be an absolute HTTP(S) URL")
    handler = type(
        "ConfiguredSakuraRetryProxyHandler",
        (SakuraRetryProxyHandler,),
        {
            "settings": settings,
            "upstream": upstream,
            "token_state": SharedTokenCooldown(
                settings.account_tokens, settings.account_ids, settings.account_db_path
            ),
        },
    )
    return SakuraProxyServer(address, handler)


def main() -> None:
    """Run the gateway until the container stops."""
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = Settings.from_environment()
    server = make_server(settings)
    LOG.info("Listening on %s:%d", *server.server_address)
    server.serve_forever()


if __name__ == "__main__":
    main()
