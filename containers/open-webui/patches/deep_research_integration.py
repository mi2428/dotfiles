"""Trusted Open WebUI boundary for the managed Deep Research Pipe."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import time
import uuid
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any

MODEL_ID = "sacloud.kimi-k2.7-deep-research"
PIPE_ID = "deep_research_pipe"
MARKER = "dotfiles:kimi-k2.7-deep-research"
TRUST_KEY = "_deep_research_trusted"
BINDING_KEY = "deep_research"
RUNTIME_RESPONSE_MAX_BYTES = 2 * 1024 * 1024
FINAL_STATES = {
    "delivered",
    "needs_review",
    "paused",
    "failed",
    "cancelled",
    "cancel_requested",
}


def report_title(user_message: str) -> str:
    """Derive an immutable Note title from the immutable request."""
    request_title = re.sub(r"\s+", " ", user_message).strip()
    if match := re.match(
        r"^(.+?[。\N{FULLWIDTH EXCLAMATION MARK}\N{FULLWIDTH QUESTION MARK}])",
        request_title,
    ):
        request_title = match.group(1)
    if request_title:
        return request_title[:120]
    return "Deep Research"


def _dict(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if hasattr(value, "model_dump"):
        return value.model_dump()
    return {}


def _reject(detail: str, status_code: int = 400) -> None:
    from fastapi import HTTPException

    raise HTTPException(status_code=status_code, detail=detail)


def query_hash(query: str) -> str:
    return hashlib.sha256(query.encode()).hexdigest()


def _signing_key(key: str | None = None) -> bytes:
    if key is None:
        from open_webui.env import WEBUI_SECRET_KEY

        key = WEBUI_SECRET_KEY
    if not isinstance(key, str) or not key:
        raise RuntimeError("Open WebUI signing key is not configured")
    return key.encode()


def action_signature(
    *,
    owner_id: str,
    chat_id: str,
    action_id: str,
    request_hash: str,
    key: str | None = None,
) -> str:
    value = json.dumps(
        [MARKER, MODEL_ID, owner_id, chat_id, action_id, request_hash],
        ensure_ascii=True,
        separators=(",", ":"),
    ).encode()
    return hmac.new(_signing_key(key), value, hashlib.sha256).hexdigest()


def job_signature(intent_signature: str, job_id: str, key: str | None = None) -> str:
    return hmac.new(
        _signing_key(key), f"{intent_signature}:{job_id}".encode(), hashlib.sha256
    ).hexdigest()


def validate_action_binding(
    binding: Any,
    *,
    owner_id: str,
    chat_id: str,
    action_id: str,
    query: str,
    key: str | None = None,
) -> dict[str, Any]:
    binding = _dict(binding)
    request_hash = query_hash(query)
    expected_intent = action_signature(
        owner_id=owner_id,
        chat_id=chat_id,
        action_id=action_id,
        request_hash=request_hash,
        key=key,
    )
    valid = (
        binding.get("marker") == MARKER
        and binding.get("owner_id") == owner_id
        and binding.get("chat_id") == chat_id
        and binding.get("action_id") == action_id
        and binding.get("query_hash") == request_hash
        and isinstance(binding.get("intent_signature"), str)
        and hmac.compare_digest(binding["intent_signature"], expected_intent)
    )
    if not valid:
        raise RuntimeError("Deep Research action provenance is invalid")
    job_id = binding.get("job_id")
    if job_id is not None and (
        not isinstance(job_id, str)
        or not job_id
        or not isinstance(binding.get("job_signature"), str)
        or not hmac.compare_digest(
            binding["job_signature"], job_signature(expected_intent, job_id, key)
        )
    ):
        raise RuntimeError("Deep Research job provenance is invalid")
    return binding


def validate_managed_model_contract(
    model_id: str,
    model_info: Any,
    function: Any,
    *,
    registry_model: Any = None,
    missing_base_model: bool = False,
    require_registry: bool = False,
    direct: bool = False,
) -> bool:
    """Return False for ordinary models and fail closed for the reserved ID."""
    if model_id != MODEL_ID:
        return False

    model = _dict(model_info)
    function_data = _dict(function)
    model_meta = _dict(model.get("meta"))
    function_meta = _dict(function_data.get("meta"))
    params = _dict(model.get("params"))
    registry = _dict(registry_model)
    forbidden_model_inputs = (
        model_meta.get("knowledge"),
        model_meta.get("filterIds"),
        model_meta.get("toolIds"),
        model_meta.get("skillIds"),
        model_meta.get("defaultFeatureIds"),
    )
    valid = (
        not direct
        and model.get("id") == MODEL_ID
        and model.get("base_model_id") == PIPE_ID
        and model.get("is_active") is True
        and model_meta.get("provisioned_by") == MARKER
        and not any(forbidden_model_inputs)
        and not params.get("system")
        and function_data.get("id") == PIPE_ID
        and function_data.get("type") == "pipe"
        and function_data.get("is_active") is True
        and function_data.get("is_global") is False
        and function_meta.get("provisioned_by") == MARKER
    )
    if not valid:
        raise RuntimeError(
            "managed Deep Research model or Pipe is not provisioned safely"
        )
    if require_registry and (
        missing_base_model
        or registry.get("id") != MODEL_ID
        or _dict(registry.get("pipe")).get("type") != "pipe"
    ):
        raise RuntimeError(
            "managed Deep Research Pipe is missing from the model registry"
        )
    return True


async def is_managed_deep_research_model(
    model_id: str,
    model_info: Any,
    *,
    registry_model: Any = None,
    missing_base_model: bool = False,
    require_registry: bool = False,
    direct: bool = False,
) -> bool:
    if model_id != MODEL_ID:
        return False
    from open_webui.models.functions import Functions

    function = await Functions.get_function_by_id(PIPE_ID)
    try:
        return validate_managed_model_contract(
            model_id,
            model_info,
            function,
            registry_model=registry_model,
            missing_base_model=missing_base_model,
            require_registry=require_registry,
            direct=direct,
        )
    except RuntimeError as exc:
        _reject(str(exc), 503)
    return False


def is_trusted_deep_research(metadata: Any) -> bool:
    metadata = _dict(metadata)
    trusted = _dict(metadata.get(TRUST_KEY))
    basic = (
        trusted.get("marker") == MARKER
        and trusted.get("model_id") == MODEL_ID
        and trusted.get("owner_id") == metadata.get("user_id")
        and trusted.get("action_id") == metadata.get("message_id")
        and trusted.get("chat_id") == metadata.get("chat_id")
        and isinstance(trusted.get("query"), str)
        and bool(trusted.get("query"))
    )
    if not basic:
        return False
    try:
        validate_action_binding(
            trusted,
            owner_id=trusted["owner_id"],
            chat_id=trusted["chat_id"],
            action_id=trusted["action_id"],
            query=trusted["query"],
        )
    except RuntimeError:
        return False
    return True


def managed_pipe_payload(
    form_data: dict[str, Any], metadata: dict[str, Any]
) -> dict[str, Any]:
    if not is_trusted_deep_research(metadata):
        raise RuntimeError("untrusted Deep Research context")
    trusted = metadata[TRUST_KEY]
    return {
        "model": form_data["model"],
        "stream": False,
        "messages": [{"role": "user", "content": trusted["query"]}],
        "metadata": metadata,
    }


def _has_enabled_feature(features: Any) -> bool:
    return not isinstance(features, dict) or any(
        bool(value) for value in features.values()
    )


def _validate_auxiliary_inputs(
    form_data: dict[str, Any], metadata: dict[str, Any]
) -> None:
    forbidden = {
        "attachments": metadata.get("files") or form_data.get("files"),
        "filters": metadata.get("filter_ids"),
        "tools": metadata.get("tool_ids")
        or metadata.get("tool_servers")
        or form_data.get("tools"),
        "skills": form_data.get("skill_ids"),
        "terminal": form_data.get("terminal_id"),
        "folder": metadata.get("folder_id"),
        "variables": form_data.get("variables"),
        "system prompt": _dict(form_data.get("params")).get("system"),
        "regeneration prompt": form_data.get("regeneration_prompt"),
    }
    enabled = next((name for name, value in forbidden.items() if value), None)
    if enabled:
        _reject(f"Deep Research does not accept {enabled}")
    if metadata.get("internal") is True or metadata.get("automation_id"):
        _reject("Deep Research accepts only an explicit user chat action")
    if _has_enabled_feature(metadata.get("features") or {}):
        _reject("Deep Research does not accept chat features")
    if any(
        message.get("content")
        for message in form_data.get("messages", [])
        if isinstance(message, dict)
    ):
        _reject("Deep Research does not accept caller-provided conversation context")


def _validate_user_message(message: Any, expected_id: str) -> str:
    message = _dict(message)
    content = message.get("content")
    if (
        message.get("id") != expected_id
        or message.get("role") != "user"
        or not isinstance(content, str)
        or not content.strip()
        or message.get("files")
        or _dict(message.get("meta")).get("internal") is True
    ):
        _reject("Deep Research requires one plain-text owned user message")
    return content.strip()


def _validate_bound_assistant(
    message: Any,
    *,
    chat_id: str,
    action_id: str,
    user_message_id: str,
    owner_id: str,
    query: str,
) -> dict[str, Any] | None:
    message = _dict(message)
    if not message:
        return None
    if (
        message.get("id") != action_id
        or message.get("role") != "assistant"
        or message.get("parentId") != user_message_id
        or message.get("model") != MODEL_ID
    ):
        _reject("Deep Research action does not match the pending assistant response")
    binding = _dict(_dict(message.get("meta")).get(BINDING_KEY))
    if not binding:
        return None
    try:
        return validate_action_binding(
            binding,
            owner_id=owner_id,
            chat_id=chat_id,
            action_id=action_id,
            query=query,
        )
    except RuntimeError:
        _reject("Deep Research response binding is inconsistent", 409)
    return None


async def prepare_deep_research_request(
    *,
    form_data: dict[str, Any],
    metadata: dict[str, Any],
    user_id: str,
    message_ids: list[dict[str, Any]],
    is_new_chat: bool,
    active_task_ids: list[str],
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Replace client context with one DB-verified owner/query/action tuple."""
    from open_webui.models.chats import Chats

    _validate_auxiliary_inputs(form_data, metadata)
    chat_id = metadata.get("chat_id")
    user_message_id = metadata.get("user_message_id")
    if (
        not isinstance(chat_id, str)
        or not chat_id
        or not isinstance(user_message_id, str)
    ):
        _reject("Deep Research requires a saved chat and user message")
    if len(message_ids) != 1 or message_ids[0].get("model_id") != MODEL_ID:
        _reject("Deep Research requires exactly one managed response")
    action_id = message_ids[0].get("message_id")
    if not isinstance(action_id, str) or not re.fullmatch(
        r"[A-Za-z0-9._:-]{1,200}", action_id
    ):
        _reject("Deep Research requires an assistant response ID")

    supplied_user_message = metadata.get("user_message")
    if is_new_chat:
        query = _validate_user_message(supplied_user_message, user_message_id)
        if _dict(supplied_user_message).get("parentId") is not None:
            _reject("new Deep Research chat must start with a root user message")
        trusted_user_message = _dict(supplied_user_message)
        assistant_message = None
    else:
        chat = await Chats.get_chat_by_id(chat_id)
        if chat is None or chat.user_id != user_id:
            _reject("Deep Research chat was not found", 404)
        stored_user_message = await Chats.get_message_by_id_and_message_id(
            chat_id, user_message_id
        )
        query = _validate_user_message(stored_user_message, user_message_id)
        supplied_query = _validate_user_message(supplied_user_message, user_message_id)
        if supplied_query != query or _dict(supplied_user_message).get(
            "parentId"
        ) != _dict(stored_user_message).get("parentId"):
            _reject("Deep Research user message differs from the stored action", 409)
        trusted_user_message = _dict(stored_user_message)
        assistant_message = await Chats.get_message_by_id_and_message_id(
            chat_id, action_id
        )

    binding = _validate_bound_assistant(
        assistant_message,
        chat_id=chat_id,
        action_id=action_id,
        user_message_id=user_message_id,
        owner_id=user_id,
        query=query,
    )
    if assistant_message and binding is None:
        _reject("existing Deep Research response has no signed action intent", 409)
    reattach_id = metadata.get("assistant_message_id")
    if (
        binding is not None
        and reattach_id != action_id
        and not active_task_ids
        and _dict(assistant_message).get("done") is not True
    ):
        _reject("Deep Research reattach requires the original response ID", 409)
    if binding is None and reattach_id is not None:
        _reject("Deep Research reattach has no durable job binding", 409)
    if active_task_ids and binding is None:
        _reject("another chat task is already active", 409)

    request_hash = query_hash(query)
    intent_signature = action_signature(
        owner_id=user_id,
        chat_id=chat_id,
        action_id=action_id,
        request_hash=request_hash,
    )
    metadata = {
        **metadata,
        "model_id": MODEL_ID,
        "filter_ids": [],
        "tool_ids": [],
        "tool_servers": [],
        "files": [],
        "features": {},
        "user_message": trusted_user_message,
        "message_id": action_id,
        TRUST_KEY: {
            "marker": MARKER,
            "model_id": MODEL_ID,
            "owner_id": user_id,
            "chat_id": chat_id,
            "action_id": action_id,
            "query": query,
            "query_hash": request_hash,
            "intent_signature": intent_signature,
            "reattach": binding is not None,
            "job_id": binding.get("job_id") if binding else None,
            **(
                {"job_signature": binding["job_signature"]}
                if binding and binding.get("job_id")
                else {}
            ),
            "active_task_ids": list(active_task_ids) if binding else [],
            "completed": bool(
                binding is not None
                and _dict(assistant_message).get("done") is True
                and binding.get("state") in FINAL_STATES
            ),
        },
    }
    return managed_pipe_payload(form_data, metadata), metadata


async def runtime_json(
    method: str, path: str, owner_id: str, payload: dict[str, Any] | None = None
) -> tuple[int, dict[str, Any]]:
    import aiohttp

    base_url = os.environ.get("DEEP_RESEARCH_RUNTIME_URL", "").rstrip("/")
    api_key = os.environ.get("DEEP_RESEARCH_RUNTIME_API_KEY", "")
    if not base_url.startswith(("http://", "https://")) or not api_key:
        raise RuntimeError("Deep Research Runtime is not configured")
    timeout = aiohttp.ClientTimeout(total=20)
    headers = {"Authorization": f"Bearer {api_key}", "X-Research-Owner": owner_id}
    async with (
        aiohttp.ClientSession(timeout=timeout, headers=headers) as session,
        session.request(
            method,
            f"{base_url}{path}",
            json=payload,
            allow_redirects=False,
        ) as response,
    ):
        if response.status not in {200, 202}:
            raise RuntimeError(
                f"Deep Research Runtime request failed (HTTP {response.status})"
            )
        data = await bounded_response_json(response)
        retry_after = bounded_retry_after(response.headers.get("Retry-After"))
    return response.status, {**data, "_adapter_retry_after_seconds": retry_after}


async def bounded_response_json(response: Any) -> dict[str, Any]:
    body = bytearray()
    while chunk := await response.content.read(
        min(64 * 1024, RUNTIME_RESPONSE_MAX_BYTES + 1 - len(body))
    ):
        body.extend(chunk)
        if len(body) > RUNTIME_RESPONSE_MAX_BYTES:
            raise RuntimeError("Deep Research Runtime response exceeded the byte limit")
    try:
        data = json.loads(body)
    except (UnicodeDecodeError, ValueError, RecursionError) as exc:
        raise RuntimeError("Deep Research Runtime returned invalid JSON") from exc
    if not isinstance(data, dict):
        raise TypeError("Deep Research Runtime returned an invalid response")
    return data


def bounded_retry_after(value: Any, *, now: datetime | None = None) -> float:
    """Parse Retry-After without allowing the peer to stall the adapter indefinitely."""
    seconds = 2.0
    if value is not None:
        try:
            seconds = float(value)
        except (TypeError, ValueError):
            try:
                target = parsedate_to_datetime(str(value))
                current = now or datetime.now(timezone.utc)
                seconds = (target - current).total_seconds()
            except (TypeError, ValueError, OverflowError):
                seconds = 2.0
    return min(10.0, max(0.1, seconds))


def note_id_for(owner_id: str, job_id: str, publication_id: str) -> str:
    return str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            f"open-webui:deep-research:{owner_id}:{job_id}:{publication_id}",
        )
    )


def _expected_note(
    *,
    owner_id: str,
    job_id: str,
    publication_id: str,
    content_hash: str,
    markdown: str,
    query: str,
) -> dict[str, Any]:
    return {
        "id": note_id_for(owner_id, job_id, publication_id),
        "user_id": owner_id,
        "title": report_title(query),
        "data": {"content": {"json": None, "html": "", "md": markdown}},
        "meta": {
            "provisioned_by": MARKER,
            "deep_research_job_id": job_id,
            "deep_research_publication_id": publication_id,
            "deep_research_content_hash": content_hash,
        },
    }


def validate_existing_note(
    note: Any, grants: list[Any], expected: dict[str, Any]
) -> None:
    actual = _dict(note) or {
        key: getattr(note, key, None)
        for key in ("id", "user_id", "title", "data", "meta")
    }
    for key in ("id", "user_id", "title", "data", "meta"):
        if actual.get(key) != expected[key]:
            raise RuntimeError(
                "existing Deep Research Note was changed; refusing to overwrite it"
            )
    if grants:
        raise RuntimeError(
            "existing Deep Research Note is not private; refusing to overwrite it"
        )


async def persist_deep_research_note(
    *,
    owner_id: str,
    job_id: str,
    publication_id: str,
    content_hash: str,
    markdown: str,
    query: str,
) -> str:
    """Insert one deterministic private Note; never update an existing Note."""
    from open_webui.internal.db import get_async_db_context
    from open_webui.models.access_grants import AccessGrants
    from open_webui.models.notes import Note
    from sqlalchemy.exc import IntegrityError

    if not hmac.compare_digest(
        hashlib.sha256(markdown.encode()).hexdigest(), content_hash
    ):
        raise RuntimeError("Deep Research publication content hash does not match")
    expected = _expected_note(
        owner_id=owner_id,
        job_id=job_id,
        publication_id=publication_id,
        content_hash=content_hash,
        markdown=markdown,
        query=query,
    )
    async with get_async_db_context() as db:
        now = int(time.time_ns())
        db.add(Note(**expected, created_at=now, updated_at=now))
        try:
            await db.commit()
        except IntegrityError:
            await db.rollback()
        note = await db.get(Note, expected["id"])
        if note is None:
            raise RuntimeError("Open WebUI did not save the Deep Research Note")
        grants = await AccessGrants.get_grants_by_resource(
            "note", expected["id"], db=db
        )
        validate_existing_note(note, grants, expected)
    return expected["id"]


async def persist_job_binding(
    *,
    chat_id: str,
    message_id: str,
    owner_id: str,
    query: str,
    job_id: str,
    publication_id: str | None = None,
    content_hash: str | None = None,
    note_id: str | None = None,
    state: str | None = None,
    done: bool | None = None,
) -> None:
    from open_webui.models.chats import Chats

    message = await Chats.get_message_by_id_and_message_id(chat_id, message_id)
    if (
        not message
        or message.get("role") != "assistant"
        or message.get("model") != MODEL_ID
    ):
        raise RuntimeError("Deep Research response disappeared before binding")
    meta = _dict(message.get("meta"))
    binding = validate_action_binding(
        meta.get(BINDING_KEY),
        owner_id=owner_id,
        chat_id=chat_id,
        action_id=message_id,
        query=query,
    )
    if binding.get("job_id") not in {None, job_id}:
        raise RuntimeError("Deep Research response binding changed")
    update = {
        **binding,
        "job_id": job_id,
        "job_signature": job_signature(binding["intent_signature"], job_id),
        **({"publication_id": publication_id} if publication_id else {}),
        **({"content_hash": content_hash} if content_hash else {}),
        **({"note_id": note_id} if note_id else {}),
        **({"state": state} if state else {}),
    }
    saved = await Chats.upsert_message_to_chat_by_id_and_message_id(
        chat_id,
        message_id,
        {
            "meta": {**meta, BINDING_KEY: update},
            **({"done": done} if done is not None else {}),
        },
        touch=False,
    )
    if saved is None:
        raise RuntimeError("Open WebUI did not save the Deep Research job binding")


async def persist_deep_research_intent(metadata: dict[str, Any]) -> None:
    """Durably record signed action provenance before the runtime submit can occur."""
    from open_webui.models.chats import Chats

    if not is_trusted_deep_research(metadata):
        raise RuntimeError("cannot persist untrusted Deep Research action intent")
    trusted = metadata[TRUST_KEY]
    message = await Chats.get_message_by_id_and_message_id(
        trusted["chat_id"], trusted["action_id"]
    )
    if (
        not message
        or message.get("role") != "assistant"
        or message.get("parentId") != metadata.get("user_message_id")
        or message.get("model") != MODEL_ID
    ):
        raise RuntimeError("Deep Research assistant response was not persisted")
    meta = _dict(message.get("meta"))
    existing = _dict(meta.get(BINDING_KEY))
    intent = {
        key: trusted[key]
        for key in (
            "marker",
            "owner_id",
            "chat_id",
            "action_id",
            "query_hash",
            "intent_signature",
        )
    }
    if existing:
        validate_action_binding(
            existing,
            owner_id=trusted["owner_id"],
            chat_id=trusted["chat_id"],
            action_id=trusted["action_id"],
            query=trusted["query"],
        )
        return
    saved = await Chats.upsert_message_to_chat_by_id_and_message_id(
        trusted["chat_id"],
        trusted["action_id"],
        {"meta": {**meta, BINDING_KEY: {**intent, "state": "submitting"}}},
        touch=False,
    )
    if saved is None:
        raise RuntimeError("Open WebUI did not save the Deep Research action intent")


def research_job_payload(query: str, action_id: str) -> dict[str, Any]:
    return {
        "query": query,
        "action_id": action_id,
        "profile": "deep",
        "max_units": 4,
    }


async def request_deep_research_stop(chat_id: str, owner_id: str) -> list[str]:
    """Cancel only DB-bound managed jobs selected by the authenticated Stop route."""
    from open_webui.models.chats import Chats
    from open_webui.models.models import Models

    messages = await Chats.get_messages_map_by_chat_id(chat_id) or {}
    pending = [
        message
        for message in messages.values()
        if message.get("role") == "assistant"
        and message.get("done") is False
        and message.get("model") == MODEL_ID
    ]
    if not pending:
        return []
    if not await Chats.is_chat_owner(chat_id, owner_id):
        _reject("Deep Research chat was not found", 404)
    if len(pending) != 1:
        _reject("multiple pending Deep Research responses are inconsistent", 409)
    await is_managed_deep_research_model(
        MODEL_ID, await Models.get_model_by_id(MODEL_ID)
    )

    message = pending[0]
    action_id = message.get("id")
    parent = messages.get(message.get("parentId"))
    query = _validate_user_message(parent, message.get("parentId"))
    binding = _validate_bound_assistant(
        message,
        chat_id=chat_id,
        action_id=action_id,
        user_message_id=message.get("parentId"),
        owner_id=owner_id,
        query=query,
    )
    if binding is None:
        _reject("pending Deep Research response has no signed action intent", 409)
    job_id = binding.get("job_id")
    if job_id is None:
        _, cancelled = await runtime_json(
            "POST",
            f"/research/actions/{action_id}/cancel",
            owner_id,
            research_job_payload(query, action_id),
        )
        if cancelled.get("action_id") != action_id:
            raise RuntimeError("Deep Research Runtime returned a different action")
        job_id = cancelled.get("job_id")
        if cancelled.get("status") not in {"cancelled", "cancel_requested"}:
            raise RuntimeError("Deep Research Runtime did not cancel the action")
        if job_id is not None:
            if not isinstance(job_id, str) or not job_id:
                raise RuntimeError("Deep Research Runtime returned an invalid job_id")
            await persist_job_binding(
                chat_id=chat_id,
                message_id=action_id,
                owner_id=owner_id,
                query=query,
                job_id=job_id,
                state="cancel_requested",
            )
            message = await Chats.get_message_by_id_and_message_id(chat_id, action_id)
            binding = _dict(_dict(_dict(message).get("meta")).get(BINDING_KEY))
    else:
        _, cancelled = await runtime_json(
            "POST", f"/research/jobs/{job_id}/cancel", owner_id
        )
        if cancelled.get("job_id") != job_id or not (
            cancelled.get("status") == "cancelled"
            or (
                cancelled.get("status") == "running"
                and cancelled.get("cancel_requested") is True
            )
        ):
            raise RuntimeError("Deep Research Runtime did not cancel the job")
    meta = _dict(message.get("meta"))
    meta[BINDING_KEY] = {**binding, "state": "cancel_requested"}
    saved = await Chats.upsert_message_to_chat_by_id_and_message_id(
        chat_id, action_id, {"done": True, "meta": meta}, touch=False
    )
    if saved is None:
        raise RuntimeError(
            "Open WebUI did not finalize the stopped Deep Research response"
        )
    return [action_id]
