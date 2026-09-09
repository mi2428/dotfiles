"""
title: Deep Research Pipe
description: Runs one durable managed Deep Research job and delivers exact Markdown.
version: 1.0.0
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import re
import time
from typing import Any

ACTIVE = {"queued", "running"}
TERMINAL = {"completed", "incomplete", "failed", "cancelled"}
ADAPTER_MAX_SECONDS = 4_800
PHASES = {
    "scoping": "調査範囲を整理しています…",
    "researching": "情報源を調査しています…",
    "writing": "調査結果を執筆しています…",
    "supervising": "調査結果を検証しています…",
}


def shorten_adapter_deadline(
    current_deadline: float, deadline_at_ms: Any, *, now_ms: int, monotonic_now: float
) -> float:
    if (
        isinstance(deadline_at_ms, bool)
        or not isinstance(deadline_at_ms, int)
        or deadline_at_ms <= 0
    ):
        raise RuntimeError("Deep Research Runtime returned an invalid deadline")
    runtime_deadline = monotonic_now + max(0, deadline_at_ms - now_ms) / 1_000
    return min(current_deadline, runtime_deadline)


class Pipe:
    async def _runtime(
        self,
        method: str,
        path: str,
        owner_id: str,
        payload: dict[str, Any] | None = None,
    ) -> tuple[int, dict[str, Any]]:
        from open_webui.utils.deep_research_integration import runtime_json

        return await runtime_json(method, path, owner_id, payload)

    async def _bind(self, **values: Any) -> None:
        from open_webui.utils.deep_research_integration import persist_job_binding

        await persist_job_binding(**values)

    async def _note(self, **values: Any) -> str:
        from open_webui.utils.deep_research_integration import (
            persist_deep_research_note,
        )

        return await persist_deep_research_note(**values)

    async def _emit(self, emitter: Any, phase: str, *, done: bool = False) -> None:
        if emitter:
            await emitter(
                {
                    "type": "status",
                    "data": {
                        "action": "deep_research",
                        "phase": phase,
                        "description": PHASES.get(
                            phase, "Deep Researchを実行しています…"
                        ),
                        "done": done,
                        **({"hidden": True} if done else {}),
                    },
                }
            )

    @staticmethod
    def _trusted(
        metadata: Any, user: Any, chat_id: Any, message_id: Any
    ) -> dict[str, str]:
        from open_webui.utils.deep_research_integration import (
            TRUST_KEY,
            is_trusted_deep_research,
        )

        metadata = metadata if isinstance(metadata, dict) else {}
        trusted = metadata.get(TRUST_KEY)
        user_id = user.get("id") if isinstance(user, dict) else None
        if (
            not is_trusted_deep_research(metadata)
            or not isinstance(trusted, dict)
            or trusted.get("owner_id") != user_id
            or trusted.get("owner_id") != metadata.get("user_id")
            or trusted.get("action_id") != message_id
            or metadata.get("message_id") != message_id
            or metadata.get("chat_id") != chat_id
            or not isinstance(trusted.get("query"), str)
            or not trusted["query"]
        ):
            raise RuntimeError("Deep Research Pipe requires server-verified context")
        return trusted

    @staticmethod
    def _field(payload: dict[str, Any], name: str) -> str:
        value = payload.get(name)
        if (
            not isinstance(value, str)
            or not value
            or not re.fullmatch(r"[A-Za-z0-9._:-]{1,200}", value)
        ):
            raise RuntimeError(f"Deep Research Runtime returned an invalid {name}")
        return value

    @staticmethod
    def _markdown(payload: dict[str, Any]) -> tuple[str, str]:
        markdown = payload.get("answer_markdown")
        content_hash = payload.get("content_hash")
        if (
            not isinstance(markdown, str)
            or not markdown
            or not isinstance(content_hash, str)
        ):
            raise RuntimeError("Deep Research Runtime returned an invalid result")
        if not re.fullmatch(r"[0-9a-f]{64}", content_hash):
            raise RuntimeError("Deep Research Runtime returned an invalid content hash")
        actual_hash = hashlib.sha256(markdown.encode()).hexdigest()
        if not hmac.compare_digest(actual_hash, content_hash):
            raise RuntimeError("Deep Research Runtime result hash does not match")
        return markdown, content_hash

    async def pipe(
        self,
        body: dict,
        __user__: dict | None = None,
        __chat_id__: str | None = None,
        __message_id__: str | None = None,
        __metadata__: dict | None = None,
        __event_emitter__=None,
    ) -> str:
        trusted = self._trusted(__metadata__, __user__, __chat_id__, __message_id__)
        owner_id = trusted["owner_id"]
        action_id = trusted["action_id"]
        query = trusted["query"]
        job_id: str | None = None
        adapter_deadline = time.monotonic() + ADAPTER_MAX_SECONDS

        async def runtime(
            method: str, path: str, payload: dict[str, Any] | None = None
        ):
            remaining = adapter_deadline - time.monotonic()
            if remaining <= 0:
                raise asyncio.TimeoutError
            return await asyncio.wait_for(
                self._runtime(method, path, owner_id, payload),
                timeout=remaining,
            )

        try:
            from open_webui.utils.deep_research_integration import research_job_payload

            _, submitted = await runtime(
                "POST",
                "/research/jobs",
                research_job_payload(query, action_id),
            )
            job_id = self._field(submitted, "job_id")
            if trusted.get("job_id") and trusted["job_id"] != job_id:
                raise RuntimeError(
                    "Deep Research Runtime job differs from the durable binding"
                )
            await self._bind(
                chat_id=__chat_id__,
                message_id=action_id,
                owner_id=owner_id,
                query=query,
                job_id=job_id,
                state=str(submitted.get("status") or "queued"),
            )

            emitted: set[str] = set()
            while True:
                _, status = await runtime("GET", f"/research/jobs/{job_id}")
                if self._field(status, "job_id") != job_id:
                    raise RuntimeError("Deep Research Runtime returned a different job")
                state = status.get("status")
                phase = status.get("phase")
                now_ms = time.time_ns() // 1_000_000
                adapter_deadline = shorten_adapter_deadline(
                    adapter_deadline,
                    status.get("deadline_at_ms"),
                    now_ms=now_ms,
                    monotonic_now=time.monotonic(),
                )
                if phase in PHASES and phase not in emitted:
                    emitted.add(phase)
                    await self._emit(__event_emitter__, phase)
                if state in TERMINAL:
                    break
                if state == "paused":
                    await self._bind(
                        chat_id=__chat_id__,
                        message_id=action_id,
                        owner_id=owner_id,
                        query=query,
                        job_id=job_id,
                        state="paused",
                    )
                    await self._emit(__event_emitter__, "paused", done=True)
                    return (
                        "> **paused:** 調査jobは保持されています。自動resumeは行いません。"
                        "明示的なresumeまたはoperator対応が必要です。"
                    )
                if state not in ACTIVE:
                    raise RuntimeError(
                        "Deep Research Runtime returned an invalid job state"
                    )
                remaining = adapter_deadline - time.monotonic()
                if remaining <= 0:
                    raise asyncio.TimeoutError
                retry_after = status.get("_adapter_retry_after_seconds", 2.0)
                if not isinstance(retry_after, (int, float)) or isinstance(
                    retry_after, bool
                ):
                    retry_after = 2.0
                await asyncio.sleep(min(max(0.1, retry_after), 10.0, remaining))

            _, result = await runtime("GET", f"/research/jobs/{job_id}/result")
            if result.get("job_id") != job_id or result.get("status") != state:
                raise RuntimeError(
                    "Deep Research Runtime returned an inconsistent result"
                )
            if state == "incomplete":
                if result.get("delivery_status") != "needs_review":
                    raise RuntimeError(
                        "incomplete Deep Research result is not marked needs_review"
                    )
                if (
                    result.get("answer_markdown") is None
                    and result.get("content_hash") is None
                ):
                    await self._bind(
                        chat_id=__chat_id__,
                        message_id=action_id,
                        owner_id=owner_id,
                        query=query,
                        job_id=job_id,
                        state="needs_review",
                    )
                    await self._emit(__event_emitter__, "needs_review", done=True)
                    return (
                        "> **needs_review:** 調査は安全に完了できず、レビュー可能な稿もありません。"
                        "Noteには保存されていません。"
                    )
                markdown, content_hash = self._markdown(result)
                await self._bind(
                    chat_id=__chat_id__,
                    message_id=action_id,
                    owner_id=owner_id,
                    query=query,
                    job_id=job_id,
                    content_hash=content_hash,
                    state="needs_review",
                )
                await self._emit(__event_emitter__, "needs_review", done=True)
                return (
                    "> **needs_review:** この調査稿は未完了で、Noteには保存されていません。\n\n"
                    + markdown
                )
            if state != "completed":
                await self._bind(
                    chat_id=__chat_id__,
                    message_id=action_id,
                    owner_id=owner_id,
                    query=query,
                    job_id=job_id,
                    state=state,
                    done=True,
                )
                raise RuntimeError(f"Deep Research ended with status {state}")

            publication_id = self._field(result, "publication_id")
            markdown, content_hash = self._markdown(result)
            note_id = await self._note(
                owner_id=owner_id,
                job_id=job_id,
                publication_id=publication_id,
                content_hash=content_hash,
                markdown=markdown,
                query=query,
            )
            await self._bind(
                chat_id=__chat_id__,
                message_id=action_id,
                owner_id=owner_id,
                query=query,
                job_id=job_id,
                publication_id=publication_id,
                content_hash=content_hash,
                note_id=note_id,
                state="delivery_pending",
            )
            _, delivery = await runtime(
                "POST",
                f"/research/jobs/{job_id}/delivery",
                {
                    "publication_id": publication_id,
                    "content_hash": content_hash,
                    "note_id": note_id,
                },
            )
            receipt = delivery.get("delivery") or delivery
            if (
                delivery.get("delivery_status") != "delivered"
                or not isinstance(receipt, dict)
                or receipt.get("publication_id") != publication_id
                or receipt.get("content_hash") != content_hash
                or receipt.get("note_id") != note_id
            ):
                raise RuntimeError(
                    "Deep Research Runtime did not acknowledge Note delivery"
                )
            await self._bind(
                chat_id=__chat_id__,
                message_id=action_id,
                owner_id=owner_id,
                query=query,
                job_id=job_id,
                publication_id=publication_id,
                content_hash=content_hash,
                note_id=note_id,
                state="delivered",
            )
            await self._emit(__event_emitter__, "completed", done=True)
            return markdown
        except asyncio.TimeoutError as exc:
            raise RuntimeError("Deep Research adapter deadline exceeded") from exc
        except asyncio.CancelledError:
            raise
