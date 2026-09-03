"""Persist trusted Deep Research output independently of its chat record.

The patched Open WebUI middleware calls this before exposing direct tool output. The
message ID makes retries update one private Note, and any save failure prevents the chat
turn from being reported as successful.
"""

from __future__ import annotations

import re
from typing import Any

ORIGIN = "dotfiles:deep-research-runtime"


def report_title(chat_title: str, user_message: str) -> str:
    """Reuse the generated chat title, with the request as a race-safe fallback."""

    title = re.sub(r"\s+", " ", chat_title).strip()
    if title and title.casefold() != "new chat":
        return title[:120]

    request_title = re.sub(r"\s+", " ", user_message).strip()
    if match := re.match(
        r"^(.+?[。\N{FULLWIDTH EXCLAMATION MARK}\N{FULLWIDTH QUESTION MARK}])",
        request_title,
    ):
        request_title = match.group(1)
    if request_title:
        return request_title[:120]
    return "Deep Research"


async def persist_deep_research_note(
    *,
    notes: Any,
    note_form: type[Any],
    note_update_form: type[Any],
    user_id: str,
    message_id: str,
    chat_id: str,
    chat_title: str,
    markdown: str,
    user_message: str,
) -> str:
    """Create or update the private Note owned by one Open WebUI message."""
    if not user_id or not message_id or not markdown:
        raise ValueError(
            "user, message, and Markdown are required for Note persistence"
        )

    meta = {
        "provisioned_by": ORIGIN,
        "deep_research_message_id": message_id,
        "deep_research_chat_id": chat_id,
    }
    data = {"content": {"json": None, "html": "", "md": markdown}}
    title = report_title(chat_title, user_message)
    # ponytail: linear scan is enough for personal Notes; add an indexed origin key if volume grows.
    existing = next(
        (
            note
            for note in await notes.get_notes_by_user_id(user_id, limit=None)
            if note.user_id == user_id
            and (note.meta or {}).get("provisioned_by") == ORIGIN
            and (note.meta or {}).get("deep_research_message_id") == message_id
        ),
        None,
    )
    if existing is None:
        saved = await notes.insert_new_note(
            user_id,
            note_form(title=title, data=data, meta=meta, access_grants=[]),
        )
    else:
        saved = await notes.update_note_by_id(
            existing.id,
            note_update_form(title=title, data=data, meta=meta),
        )
    if saved is None:
        raise RuntimeError("Open WebUI did not save the Deep Research Note")
    return saved.id
