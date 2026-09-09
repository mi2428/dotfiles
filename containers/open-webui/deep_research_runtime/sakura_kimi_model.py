"""Adapter for Kimi K2.7 preserved thinking on top of Strands' OpenAIModel.

Kimi K2.7 Code keeps preserved thinking enabled for tool loops, so each assistant
tool-call message must carry its original ``reasoning_content`` back into the next
Chat Completions request. Strands 1.54 intentionally drops ``reasoningContent`` when
formatting follow-up requests for the stock Chat Completions API because most
OpenAI-compatible providers do not accept it. Sakura's OpenAI-compatible Kimi proxy
does require that replay, so this subclass restores only that one field while
leaving Strands' normal text, tool call, and tool result formatting unchanged.
"""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import AsyncGenerator, Iterator
from contextlib import aclosing, contextmanager
from dataclasses import dataclass
from typing import Any, Literal
from urllib.parse import urlsplit, urlunsplit

import aiohttp
from openai.types.completion_usage import CompletionTokensDetails, CompletionUsage
from strands.models.openai import OpenAIModel
from strands.types.content import Message, Messages
from strands.types.streaming import StreamEvent

RESEARCH_MAX_REQUEST_BYTES = 64 * 1024
RESEARCH_MAX_RESPONSE_BYTES = 4 * 1024 * 1024
RESEARCH_MAX_SECONDS = 240.0
RESEARCH_MAX_TOKENS = 16_384


@dataclass(frozen=True, slots=True)
class AttemptLease:
    attempt_id: str
    deadline_monotonic: float
    expires_at_unix_ms: int


@dataclass(frozen=True, slots=True)
class AttemptOutcome:
    state: Literal["not_sent", "succeeded", "known_failed", "unknown"]
    http_status: int | None
    finish_reason: str | None
    prompt_tokens: int | None
    completion_tokens: int | None
    total_tokens: int | None
    response_bytes: int


@dataclass(frozen=True, slots=True)
class ResearchCompletion:
    content: str
    outcome: AttemptOutcome


def prepare_research_request(model: str, system: str, user: str) -> bytes:
    """Return the exact bounded JSON body sent by ``complete_research``."""
    if not all(type(value) is str for value in (model, system, user)) or not model:
        raise ValueError("RESEARCH_REQUEST_INVALID")
    body = json.dumps(
        {
            "max_tokens": RESEARCH_MAX_TOKENS,
            "messages": [
                {"content": system, "role": "system"},
                {"content": user, "role": "user"},
            ],
            "model": model,
            "stream": True,
            "stream_options": {"include_usage": True},
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    if len(body) > RESEARCH_MAX_REQUEST_BYTES:
        raise ValueError("RESEARCH_REQUEST_TOO_LARGE")
    return body


def _attempt_outcome(
    state: Literal["not_sent", "succeeded", "known_failed", "unknown"],
    *,
    status: int | None = None,
    finish_reason: str | None = None,
    usage: tuple[int | None, int | None, int | None] = (None, None, None),
    response_bytes: int = 0,
) -> ResearchCompletion:
    return ResearchCompletion(
        "",
        AttemptOutcome(state, status, finish_reason, *usage, response_bytes),
    )


def _usage_integer(value: object) -> int | None:
    return value if type(value) is int and 0 <= value <= 1_000_000_000 else None


def _parse_research_stream(
    raw: bytes,
) -> tuple[
    Literal["complete", "incomplete", "invalid"],
    str,
    str | None,
    tuple[int | None, int | None, int | None],
]:
    content: list[str] = []
    finish_reason: str | None = None
    usage: tuple[int | None, int | None, int | None] = (None, None, None)
    done = False
    data_events: list[bytes] = []
    for event in raw.replace(b"\r\n", b"\n").split(b"\n\n"):
        data = b"\n".join(
            line.removeprefix(b"data:").lstrip()
            for line in event.splitlines()
            if line.startswith(b"data:")
        )
        if data:
            data_events.append(data)
    framed = b"[DONE]" in data_events
    invalid_state: Literal["incomplete", "invalid"] = "invalid" if framed else "incomplete"
    for data in data_events:
        if data == b"[DONE]":
            if done:
                return invalid_state, "", None, usage
            done = True
            continue
        if done:
            return invalid_state, "", None, usage
        try:
            payload = json.loads(data)
        except (ValueError, UnicodeDecodeError, RecursionError):
            return invalid_state, "", None, usage
        if type(payload) is not dict or "error" in payload:
            return invalid_state, "", None, usage
        choices = payload.get("choices", [])
        if type(choices) is not list or len(choices) > 1:
            return invalid_state, "", None, usage
        if choices:
            choice = choices[0]
            if type(choice) is not dict or choice.get("index", 0) != 0:
                return invalid_state, "", None, usage
            delta = choice.get("delta")
            if type(delta) is not dict or any(
                key in delta for key in ("tool_calls", "function_call")
            ):
                return invalid_state, "", None, usage
            text = delta.get("content")
            if text is not None:
                if type(text) is not str or finish_reason is not None:
                    return invalid_state, "", None, usage
                content.append(text)
            reason = choice.get("finish_reason")
            if reason is not None:
                if type(reason) is not str or finish_reason is not None:
                    return invalid_state, "", None, usage
                finish_reason = (
                    reason
                    if reason in {"stop", "length", "tool_calls", "content_filter", "function_call"}
                    else "unknown"
                )
        if "usage" in payload:
            value = payload["usage"]
            if value is None:
                continue
            if type(value) is not dict:
                return invalid_state, "", None, usage
            values = tuple(
                _usage_integer(value.get(name))
                for name in ("prompt_tokens", "completion_tokens", "total_tokens")
            )
            names = ("prompt_tokens", "completion_tokens", "total_tokens")
            if any(
                value.get(name) is not None and number is None
                for name, number in zip(names, values, strict=True)
            ):
                return invalid_state, "", None, usage
            usage = values[0], values[1], values[2]
    visible = "".join(content)
    if not done:
        return "incomplete", "", None, usage
    if finish_reason is None:
        return "invalid", "", None, usage
    return "complete", visible, finish_reason, usage


async def complete_research(
    base_url: str,
    api_key: str,
    body: bytes,
    lease: AttemptLease,
) -> ResearchCompletion:
    """Send one bounded request to the authenticated no-retry research gateway."""
    attempt_id = lease.attempt_id
    valid_attempt_id = (
        type(attempt_id) is str
        and 1 <= len(attempt_id) <= 128
        and all(
            character.isascii() and (character.isalnum() or character in "-_.")
            for character in attempt_id
        )
    )
    try:
        parts = urlsplit(base_url)
        host = parts.hostname
        _port = parts.port
    except (TypeError, ValueError, UnicodeError):
        return _attempt_outcome("not_sent")
    if (
        type(body) is not bytes
        or len(body) > RESEARCH_MAX_REQUEST_BYTES
        or type(api_key) is not str
        or not api_key
        or "\n" in api_key
        or "\r" in api_key
        or not valid_attempt_id
        or parts.scheme not in {"http", "https"}
        or not parts.netloc
        or host is None
        or parts.username is not None
        or parts.password is not None
        or parts.path.rstrip("/") != "/v1"
        or parts.query
        or parts.fragment
    ):
        return _attempt_outcome("not_sent")
    loop = asyncio.get_running_loop()
    remaining = lease.deadline_monotonic - loop.time()
    wall_remaining = lease.expires_at_unix_ms / 1000 - time.time()
    if not 0 < remaining <= RESEARCH_MAX_SECONDS or not 0 < wall_remaining <= RESEARCH_MAX_SECONDS:
        return _attempt_outcome("not_sent")
    deadline = min(lease.deadline_monotonic, loop.time() + wall_remaining)
    url = urlunsplit((parts.scheme, parts.netloc, "/research/v1/chat/completions", "", ""))
    headers = {
        "Accept": "text/event-stream",
        "Accept-Encoding": "identity",
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "X-Sakura-Attempt-Id": attempt_id,
        "X-Sakura-Deadline-Unix-Ms": str(lease.expires_at_unix_ms),
    }
    received = 0
    try:
        async with asyncio.timeout_at(deadline):
            async with aiohttp.ClientSession(
                auto_decompress=False, timeout=aiohttp.ClientTimeout(total=None)
            ) as session:
                async with session.post(
                    url, data=body, headers=headers, allow_redirects=False
                ) as response:
                    raw = bytearray()
                    async for chunk in response.content.iter_chunked(64 * 1024):
                        received += len(chunk)
                        if received > RESEARCH_MAX_RESPONSE_BYTES:
                            return _attempt_outcome(
                                "unknown",
                                status=response.status,
                                response_bytes=RESEARCH_MAX_RESPONSE_BYTES,
                            )
                        raw.extend(chunk)
                    trusted_send = response.headers.get(
                        "X-Sakura-Attempt-Id"
                    ) == attempt_id and response.headers.get("X-Sakura-Upstream-Send")
                    if response.status < 200 or response.status >= 300:
                        state = (
                            "not_sent"
                            if trusted_send == "not-sent"
                            else ("known_failed" if trusted_send == "sent" else "unknown")
                        )
                        return _attempt_outcome(
                            state, status=response.status, response_bytes=received
                        )
                    if trusted_send != "sent":
                        return _attempt_outcome(
                            "unknown", status=response.status, response_bytes=received
                        )
                    stream_state, content, finish_reason, usage = _parse_research_stream(bytes(raw))
                    if stream_state == "incomplete":
                        return _attempt_outcome(
                            "unknown", status=response.status, response_bytes=received
                        )
                    if stream_state == "invalid":
                        return _attempt_outcome(
                            "known_failed", status=response.status, response_bytes=received
                        )
                    if finish_reason != "stop" or not content.strip():
                        return _attempt_outcome(
                            "known_failed",
                            status=response.status,
                            finish_reason=finish_reason,
                            usage=usage,
                            response_bytes=received,
                        )
                    return ResearchCompletion(
                        content,
                        AttemptOutcome(
                            "succeeded",
                            response.status,
                            finish_reason,
                            *usage,
                            received,
                        ),
                    )
    except asyncio.CancelledError:
        raise
    except (TimeoutError, aiohttp.ClientError, OSError):
        return _attempt_outcome("unknown", response_bytes=received)


def _observation_integer(value: Any, minimum: int = 0) -> int:
    if type(value) is not int or not minimum <= value <= 1_000_000_000:
        raise ValueError("OBSERVATION_INVALID")
    return value


class JudgeObservation:
    """Single-invoke, in-memory diagnostics; never reuse the agent/model or collector.

    Only ``accepted`` exposes copied scalar rows. Rejection clears the entire
    diagnostic, not the model result. This is not a ledger or a diagnostic writer.
    """

    def __init__(self) -> None:
        self._status = "pending"
        self._rows: list[dict[str, Any]] = []
        self._current: dict[str, Any] | None = None
        self._stream_open = False
        self._started_ns = 0
        self._seen: set[str] = set()

    @property
    def status(self) -> str:
        return self._status

    @property
    def rows(self) -> tuple[dict[str, Any], ...]:
        return tuple(dict(row) for row in self._rows) if self._status == "accepted" else ()

    def _reject(self, *, size: bool = False) -> None:
        self._status = "OBSERVATION_SIZE" if size else "OBSERVATION_INVALID"
        self._rows.clear()
        self._current = None
        self._stream_open = False
        self._started_ns = 0
        self._seen.clear()

    @contextmanager
    def _guard(self) -> Iterator[None]:
        try:
            yield
        except BaseException:
            # Diagnostics must not replace a model result, exception or cancellation.
            # Do not retain the exception (including its traceback / raw references).
            self._reject()

    def _start_stream(self) -> None:
        if self._status != "recording":
            return
        if self._stream_open:
            self._reject()
        else:
            self._stream_open = True

    def _request(self, max_tokens: Any, effort: Any, choice: Any) -> None:
        if self._status != "recording":
            return
        with self._guard():
            if not self._stream_open or self._current is not None:
                raise ValueError("OBSERVATION_INVALID")
            if len(self._rows) >= 2:
                # Reject diagnostics before the third call, but never stop the model.
                self._reject(size=True)
                return
            ordinal = _observation_integer(len(self._rows) + 1, 1)
            if type(effort) is not str or effort not in {"low", "medium", "high"}:
                raise ValueError("OBSERVATION_INVALID")
            if type(choice) is not str or choice not in {"required", "auto", "none"}:
                raise ValueError("OBSERVATION_INVALID")
            self._current = {
                "schema_version": 1,
                "request_ordinal": ordinal,
                "max_tokens": _observation_integer(max_tokens, 1),
                "reasoning_effort": effort,
                "tool_choice": choice,
                "elapsed_ms": 0,
                "stream_status": "completed",
                "finish_reason": None,
                "usage_present": False,
                "prompt_tokens": None,
                "completion_tokens": None,
                "reasoning_tokens": None,
            }
            self._started_ns = time.monotonic_ns()

    def _chunk(self, event: dict[str, Any]) -> None:
        if self._status != "recording":
            return
        with self._guard():
            if type(event) is not dict:
                raise ValueError("OBSERVATION_INVALID")
            kind = event.get("chunk_type")
            if type(kind) is not str:
                raise ValueError("OBSERVATION_INVALID")
            if kind not in {"message_stop", "metadata"}:
                return  # Never read content, reasoning, tool, or other chunk data.
            if self._current is None or kind in self._seen:
                raise ValueError("OBSERVATION_INVALID")
            self._seen.add(kind)
            value = event.get("data")
            if kind == "message_stop":
                if type(value) is not str:
                    raise ValueError("OBSERVATION_INVALID")
                known = {"stop", "length", "tool_calls", "content_filter", "function_call"}
                self._current["finish_reason"] = value if value in known else "unknown"
                return
            if value is not None and type(value) is not CompletionUsage:
                raise ValueError("OBSERVATION_INVALID")
            details = None if value is None else getattr(value, "completion_tokens_details", None)
            if details is not None and type(details) is not CompletionTokensDetails:
                raise ValueError("OBSERVATION_INVALID")
            self._current["usage_present"] = value is not None
            for key, owner in (
                ("prompt_tokens", value),
                ("completion_tokens", value),
                ("reasoning_tokens", details),
            ):
                number = None if owner is None else getattr(owner, key, None)
                self._current[key] = None if number is None else _observation_integer(number)
            completion, reasoning = (
                self._current["completion_tokens"],
                self._current["reasoning_tokens"],
            )
            if completion is not None and reasoning is not None and reasoning > completion:
                raise ValueError("OBSERVATION_INVALID")

    def _end_stream(self, status: str) -> None:
        if self._status != "recording":
            return
        with self._guard():
            row = self._current
            if row is None or not self._stream_open:
                raise ValueError("OBSERVATION_INVALID")
            if (
                type(status) is not str
                or status not in {"completed", "error", "cancelled"}
                or type(row["request_ordinal"]) is not int
                or row["request_ordinal"] != len(self._rows) + 1
                or not 1 <= row["request_ordinal"] <= 2
            ):
                raise ValueError("OBSERVATION_INVALID")
            row["elapsed_ms"] = _observation_integer(
                (time.monotonic_ns() - self._started_ns) // 1_000_000
            )
            row["stream_status"] = status
            if (
                len(json.dumps(row, separators=(",", ":")).encode("ascii")) > 512
                or len(json.dumps([*self._rows, row], separators=(",", ":")).encode("ascii")) > 2048
            ):
                self._reject(size=True)
                return
            self._rows.append(row)
            self._current = None
            self._stream_open = False
            self._started_ns = 0
            self._seen.clear()


def _preserved_reasoning_content(message: Message) -> str | None:
    if message["role"] != "assistant":
        return None

    reasoning_parts: list[str] = []
    for content in message["content"]:
        reasoning_content = content.get("reasoningContent")
        if reasoning_content is None:
            continue
        if reasoning_content.get("redactedContent") is not None:
            raise TypeError("redacted reasoningContent cannot be replayed to Kimi")
        reasoning_text = reasoning_content.get("reasoningText")
        if not isinstance(reasoning_text, dict):
            raise TypeError("assistant reasoningContent must include reasoningText")
        text = reasoning_text.get("text")
        if not isinstance(text, str) or not text:
            raise TypeError("assistant reasoningContent.reasoningText.text must be a string")
        reasoning_parts.append(text)

    return "".join(reasoning_parts) or None


def _message_without_reasoning_content(message: Message) -> Message:
    return {
        **message,
        "content": [content for content in message["content"] if "reasoningContent" not in content],
    }


class SakuraKimiModel(OpenAIModel):
    _judge_observation: JudgeObservation | None = None

    def bind_judge_observation(self, observation: object) -> bool:
        """Opt in once; foreign objects/subclasses are rejected without inspecting them."""
        current = self._judge_observation
        if current is not None:
            current._reject()
        if type(observation) is not JudgeObservation:
            return False
        if current is not None or observation.status != "pending":
            observation._reject()
            return False
        observation._status = "recording"
        self._judge_observation = observation
        return True

    def unbind_judge_observation(self) -> None:
        observation, self._judge_observation = self._judge_observation, None
        if observation is not None and observation.status == "recording":
            if observation._stream_open or not observation._rows:
                observation._reject()
            else:
                observation._status = "accepted"

    def format_request(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
        request = super().format_request(*args, **kwargs)
        observation = self._judge_observation
        if observation is not None and observation.status == "recording":
            if type(request) is not dict:
                observation._reject()
            else:
                observation._request(
                    request.get("max_tokens"),
                    request.get("reasoning_effort"),
                    request.get("tool_choice"),
                )
        return request

    def format_chunk(self, event: dict[str, Any], **kwargs: Any) -> StreamEvent:
        if self._judge_observation is not None:
            self._judge_observation._chunk(event)
        return super().format_chunk(event, **kwargs)

    def stream(self, *args: Any, **kwargs: Any) -> AsyncGenerator[StreamEvent, None]:
        stream = super().stream(*args, **kwargs)
        observation = self._judge_observation
        if observation is None:
            return stream
        return self._stream_with_judge_observation(stream, observation)

    @staticmethod
    async def _stream_with_judge_observation(
        stream: AsyncGenerator[StreamEvent, None], observation: JudgeObservation
    ) -> AsyncGenerator[StreamEvent, None]:
        observation._start_stream()
        status = "completed"
        try:
            async with aclosing(stream):
                async for chunk in stream:
                    yield chunk
        except (asyncio.CancelledError, GeneratorExit):
            status = "cancelled"
            raise
        except BaseException:
            status = "error"
            raise
        finally:
            observation._end_stream(status)

    @classmethod
    def _format_regular_messages(cls, messages: Messages, **kwargs: Any) -> list[dict[str, Any]]:
        formatted_messages: list[dict[str, Any]] = []

        for message in messages:
            reasoning_content = _preserved_reasoning_content(message)
            formatted_batch = super()._format_regular_messages(
                [_message_without_reasoning_content(message)], **kwargs
            )
            if reasoning_content is not None:
                if not formatted_batch:
                    raise TypeError("assistant reasoningContent produced no formatted message")
                first_message = formatted_batch[0]
                if first_message.get("role") != "assistant":
                    raise TypeError(
                        "assistant reasoningContent must map to an assistant request message"
                    )
                first_message["reasoning_content"] = reasoning_content
            formatted_messages.extend(formatted_batch)

        return formatted_messages
