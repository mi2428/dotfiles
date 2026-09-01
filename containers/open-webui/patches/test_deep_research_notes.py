from __future__ import annotations

import unittest
from types import SimpleNamespace
from typing import Any

from deep_research_notes import ORIGIN, persist_deep_research_note, report_title


class Form(SimpleNamespace):
    def __init__(self, **values: Any) -> None:
        super().__init__(**values)


class FakeNotes:
    def __init__(self) -> None:
        self.items: list[SimpleNamespace] = []

    async def get_notes_by_user_id(
        self, user_id: str, limit: int | None = None
    ) -> list[SimpleNamespace]:
        self.last_limit = limit
        return list(self.items)

    async def insert_new_note(self, user_id: str, form: Form) -> SimpleNamespace:
        note = SimpleNamespace(
            id="note-1",
            user_id=user_id,
            title=form.title,
            data=form.data,
            meta=form.meta,
            access_grants=form.access_grants,
        )
        self.items.append(note)
        return note

    async def update_note_by_id(
        self, note_id: str, form: Form
    ) -> SimpleNamespace | None:
        note = next((item for item in self.items if item.id == note_id), None)
        if note is not None:
            note.title = form.title
            note.data = form.data
            note.meta = form.meta
        return note


class DeepResearchNotesTests(unittest.IsolatedAsyncioTestCase):
    def test_report_title_prefers_first_h1(self) -> None:
        self.assertEqual(
            report_title("intro\n# Report title\nbody", "fallback"), "Report title"
        )
        self.assertEqual(
            report_title("## Section", "First request。More detail。"),
            "First request。",
        )

    async def test_persistence_is_private_exact_and_idempotent(self) -> None:
        notes = FakeNotes()
        values = {
            "notes": notes,
            "note_form": Form,
            "note_update_form": Form,
            "user_id": "user-1",
            "message_id": "message-1",
            "chat_id": "chat-1",
            "user_message": "Research request",
        }

        note_id = await persist_deep_research_note(
            markdown="# First\nExact [S1]", **values
        )
        same_id = await persist_deep_research_note(
            markdown="# Revised\nExact [S2]", **values
        )

        self.assertEqual(note_id, same_id)
        self.assertEqual(len(notes.items), 1)
        self.assertEqual(notes.items[0].access_grants, [])
        self.assertEqual(notes.items[0].data["content"]["md"], "# Revised\nExact [S2]")
        self.assertEqual(notes.items[0].meta["provisioned_by"], ORIGIN)
        self.assertEqual(notes.items[0].meta["deep_research_message_id"], "message-1")
        self.assertIsNone(notes.last_limit)


if __name__ == "__main__":
    unittest.main()
