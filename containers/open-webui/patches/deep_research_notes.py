"""Persist trusted Deep Research output independently of its chat record.

The patched Open WebUI middleware calls this before exposing direct tool output. The
message ID makes retries update one private Note, and any save failure prevents the chat
turn from being reported as successful.
"""

from __future__ import annotations

import re
from typing import Any

ORIGIN = "dotfiles:deep-research-runtime"


def report_title(markdown: str, user_message: str) -> str:
    """Choose a short title from the report heading or the first request sentence."""
    heading = next(
        (
            match.group(1).strip()
            for line in markdown.splitlines()
            if (match := re.match(r"^#{1,2}\s+(.+)$", line.strip()))
        ),
        "",
    )
    fallback = re.sub(r"\s+", " ", user_message).strip()
    if match := re.match(r"^(.+?[。！？])", fallback):
        fallback = match.group(1)
    return (heading or fallback or "Deep Research")[:120]


async def persist_deep_research_note(
    *,
    notes: Any,
    note_form: type[Any],
    note_update_form: type[Any],
    user_id: str,
    message_id: str,
    chat_id: str,
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
    title = report_title(markdown, user_message)
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
