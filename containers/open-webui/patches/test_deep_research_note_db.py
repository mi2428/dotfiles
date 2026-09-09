from __future__ import annotations

import asyncio
import hashlib
import os
import tempfile
import time
import unittest
from contextlib import asynccontextmanager
from pathlib import Path
from unittest.mock import patch

TEST_ENABLED = os.environ.get("DEEP_RESEARCH_NOTE_DB_TEST") == "1"
if TEST_ENABLED:
    from open_webui.internal import db as app_db
    from open_webui.models import access_grants as access_grants_module
    from open_webui.models import notes as notes_module
    from open_webui.models.access_grants import AccessGrant
    from open_webui.models.notes import Note, NoteForm, Notes
    from open_webui.utils.deep_research_integration import (
        MARKER,
        note_id_for,
        persist_deep_research_note,
        report_title,
    )
    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


@unittest.skipUnless(
    TEST_ENABLED, "set DEEP_RESEARCH_NOTE_DB_TEST=1 in the built Open WebUI image"
)
class DeepResearchNoteDBTests(unittest.IsolatedAsyncioTestCase):
    async def test_concurrent_note_is_unique_private_exact_and_never_overwritten(
        self,
    ) -> None:
        root = Path(os.environ["DEEP_RESEARCH_TEST_TMPDIR"])
        with tempfile.TemporaryDirectory(
            prefix="deep-research-note-", dir=root
        ) as directory:
            engine = create_async_engine(
                f"sqlite+aiosqlite:///{Path(directory) / 'notes.db'}",
                connect_args={"timeout": 30},
            )
            sessions = async_sessionmaker(engine, expire_on_commit=False)

            @asynccontextmanager
            async def db_context(existing=None):
                if existing is not None:
                    yield existing
                else:
                    async with sessions() as session:
                        yield session

            async with engine.begin() as connection:
                await connection.run_sync(
                    lambda sync_connection: app_db.Base.metadata.create_all(
                        sync_connection,
                        tables=[Note.__table__, AccessGrant.__table__],
                    )
                )

            owner_id = "owner-db"
            job_id = "job-db"
            publication_id = "publication-db"
            query = "公開情報を調査してください。"
            markdown = "# Exact report\n\nEvidence [S1]"
            content_hash = hashlib.sha256(markdown.encode()).hexdigest()
            values = {
                "owner_id": owner_id,
                "job_id": job_id,
                "publication_id": publication_id,
                "content_hash": content_hash,
                "markdown": markdown,
                "query": query,
            }

            try:
                with (
                    patch.object(app_db, "get_async_db_context", db_context),
                    patch.object(
                        access_grants_module, "get_async_db_context", db_context
                    ),
                    patch.object(notes_module, "get_async_db_context", db_context),
                ):
                    before_ns = time.time_ns()
                    ids = await asyncio.gather(
                        persist_deep_research_note(**values),
                        persist_deep_research_note(**values),
                    )
                    after_ns = time.time_ns()
                    expected_id = note_id_for(owner_id, job_id, publication_id)
                    self.assertEqual(ids, [expected_id, expected_id])

                    async with sessions() as session:
                        notes = (await session.execute(select(Note))).scalars().all()
                        grants = (
                            (await session.execute(select(AccessGrant))).scalars().all()
                        )
                    self.assertEqual(len(notes), 1)
                    self.assertEqual(grants, [])
                    self.assertEqual(notes[0].user_id, owner_id)
                    self.assertEqual(notes[0].title, report_title(query))
                    self.assertLessEqual(before_ns, notes[0].created_at)
                    self.assertLessEqual(notes[0].created_at, after_ns)
                    self.assertEqual(notes[0].updated_at, notes[0].created_at)
                    self.assertEqual(
                        notes[0].data,
                        {"content": {"json": None, "html": "", "md": markdown}},
                    )
                    self.assertEqual(
                        notes[0].meta,
                        {
                            "provisioned_by": MARKER,
                            "deep_research_job_id": job_id,
                            "deep_research_publication_id": publication_id,
                            "deep_research_content_hash": content_hash,
                        },
                    )

                    normal = await Notes.insert_new_note(
                        owner_id,
                        NoteForm(
                            title="Normal note",
                            data={"content": {"md": "Normal note"}},
                            access_grants=[],
                        ),
                    )
                    self.assertGreater(normal.updated_at, notes[0].updated_at)
                    async with sessions() as session:
                        ordered_ids = (
                            (
                                await session.execute(
                                    select(Note.id).order_by(Note.updated_at.desc())
                                )
                            )
                            .scalars()
                            .all()
                        )
                    self.assertEqual(ordered_ids, [normal.id, expected_id])

                    changed_markdown = "# Different report"
                    with self.assertRaisesRegex(RuntimeError, "was changed"):
                        await persist_deep_research_note(
                            **{
                                **values,
                                "markdown": changed_markdown,
                                "content_hash": hashlib.sha256(
                                    changed_markdown.encode()
                                ).hexdigest(),
                            }
                        )

                    async with sessions() as session:
                        note = await session.get(Note, expected_id)
                        self.assertEqual(note.data["content"]["md"], markdown)
                        note.title = "edited by user"
                        await session.commit()

                    with self.assertRaisesRegex(RuntimeError, "was changed"):
                        await persist_deep_research_note(**values)
                    async with sessions() as session:
                        note = await session.get(Note, expected_id)
                        self.assertEqual(note.title, "edited by user")
                        self.assertEqual(note.data["content"]["md"], markdown)
            finally:
                await engine.dispose()


if __name__ == "__main__":
    unittest.main()
