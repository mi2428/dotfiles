from __future__ import annotations

import asyncio
import json
from contextlib import ExitStack
from typing import Any
from unittest.mock import AsyncMock, patch

import test_research_jobs as fixtures
from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class ResearchReceiptBoundaryTests(RuntimeTestCase):
    def test_saved_ledger_integrity_is_checked_before_reuse(self) -> None:
        async def run() -> None:
            fixture = fixtures.ResearchJobTests()
            fixture.runtime = self.runtime
            job_id, provider = await fixture.run_path(
                [
                    *fixtures.research_outputs(),
                    fixtures.completion(fixtures.ledger_json()),
                    fixtures.completion("## Unit 1\n\n公開本文です。[S1:P0-80]"),
                    fixtures.completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
                ]
            )
            saved = await rt.editorial_revision(self.runtime, job_id, 1, "ledger")
            assert saved is not None
            changed = json.loads(saved["data_json"])
            changed["entries"][0]["condition"] = "保存後に条件が破損しました。"
            self.runtime.db.execute(
                "UPDATE editorial_revisions SET data_json = ? WHERE id = ?",
                (json.dumps(changed), saved["id"]),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
                await rt.editorial_revision(self.runtime, job_id, 1, "ledger")
            self.assertEqual(len(provider.bodies), 7)

        asyncio.run(run())

    def test_corrupted_review_cannot_erase_material_findings_on_resume(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(self.runtime, "owner-1", fixtures.request())
            job_id = job["job_id"]
            provider = fixtures.FakeProvider(
                [
                    *fixtures.research_outputs(),
                    fixtures.completion(fixtures.ledger_json()),
                    fixtures.completion("## Unit 1\n\n確認が必要な条件です。[S1:P0-80]"),
                    fixtures.completion(
                        '{"patches":[{"block_ids":["D:c1:r1:b002"],'
                        '"ledger_ids":["K-FACT"],"source_ids":["S1:P0-80"],'
                        '"reason":"The condition must be corrected."}],'
                        '"notes":[],"regenerate_reason":null}'
                    ),
                ]
            )
            fixture = fixtures.ResearchJobTests()
            fixture.runtime = self.runtime
            with ExitStack() as stack:
                for context in fixture.patches(provider):
                    stack.enter_context(context)
                with (
                    patch.object(
                        rt, "edit_candidate", new=AsyncMock(side_effect=asyncio.CancelledError)
                    ),
                    self.assertRaises(asyncio.CancelledError),
                ):
                    await rt.execute_research_job(self.runtime, job_id)
                self.assertEqual(len(provider.bodies), 7)
                self.runtime.db.execute(
                    "UPDATE review_records SET result_json = ? WHERE job_id = ?",
                    ('{"patches":[],"notes":[],"regenerate_reason":null}', job_id),
                )
                self.runtime.db.commit()
                status = await rt.research_job_status(self.runtime, "owner-1", job_id)
                await rt.resume_research_job(self.runtime, "owner-1", job_id, status["revision"])
                await rt.execute_research_job(self.runtime, job_id)
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(status["status"], "failed")
            self.assertEqual(len(provider.bodies), 7)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM publications WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                0,
            )

        asyncio.run(run())

    def test_editor_links_findings_to_targets_and_rechecks_all_affected_blocks(self) -> None:
        original = "## Unit 1\n\n第一の条件。[S1:P0-80]\n\n第二の条件。[S1:P0-80]"
        blocks = rt.draft_blocks(original, 1, 1)
        first, second = blocks[1].id, blocks[2].id
        findings = [
            {"id": "F001", "block_ids": [first]},
            {"id": "F002", "block_ids": [second]},
        ]
        unrelated = rt.EditResult(
            base_revision=1,
            replacements=[
                rt.EditReplacement(
                    block_id=first,
                    finding_ids=["F001", "F002"],
                    markdown="第一の条件だけを直しました。[S1:P0-80]",
                )
            ],
        )
        with self.assertRaises(ValueError):
            rt.apply_editor_result(original, blocks, unrelated, findings, {"S1:P0-80"})

        related = unrelated.model_copy(
            update={
                "replacements": [
                    unrelated.replacements[0].model_copy(update={"finding_ids": ["F001"]})
                ]
            }
        )
        _edited, _dismissals, affected = rt.apply_editor_result(
            original,
            blocks,
            related,
            [{"id": "F001", "block_ids": [first, second]}],
            {"S1:P0-80"},
        )
        self.assertEqual(affected, {2, 3})

    def test_cancel_does_not_overwrite_a_terminal_transition_after_owner_lookup(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(self.runtime, "owner", fixtures.request())
            job_id = job["job_id"]
            stale = await rt.owned_job(self.runtime, "owner", job_id)
            await rt.set_job_terminal(self.runtime, job_id, "failed", "integrity_failure")
            with patch.object(rt, "owned_job", new=AsyncMock(return_value=stale)):
                await rt.cancel_research_job(self.runtime, "owner", job_id)
            self.assertEqual((await rt.load_job(self.runtime, job_id))["status"], "failed")

        asyncio.run(run())

    def test_resume_checks_current_revision_not_the_owner_lookup_snapshot(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(self.runtime, "owner", fixtures.request())
            job_id = job["job_id"]
            await rt.set_job_terminal(self.runtime, job_id, "cancelled", "cancelled")
            stale = await rt.owned_job(self.runtime, "owner", job_id)
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'queued', revision = revision + 1 "
                "WHERE job_id = ?",
                (job_id,),
            )
            self.runtime.db.commit()
            with (
                patch.object(rt, "owned_job", new=AsyncMock(return_value=stale)),
                self.assertRaises(rt.HTTPException) as raised,
            ):
                await rt.resume_research_job(self.runtime, "owner", job_id, stale["revision"])
            self.assertEqual(raised.exception.status_code, 409)
            self.assertEqual(
                (await rt.load_job(self.runtime, job_id))["revision"], stale["revision"] + 1
            )

        asyncio.run(run())

    def test_completed_publication_rejects_corrupted_saved_markdown(self) -> None:
        async def run() -> None:
            fixture = fixtures.ResearchJobTests()
            fixture.runtime = self.runtime
            job_id, provider = await fixture.run_path(
                [
                    *fixtures.research_outputs(),
                    fixtures.completion(fixtures.ledger_json()),
                    fixtures.completion("## Unit 1\n\n根拠のある公開本文です。[S1:P0-80]"),
                    fixtures.completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
                ]
            )
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(status["status"], "completed")
            self.runtime.db.execute(
                "UPDATE publications SET markdown = ? WHERE job_id = ?",
                ("保存後に破損した本文です。", job_id),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
                await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(len(provider.bodies), 7)

        asyncio.run(run())

    def test_saved_model_receipt_is_reused_but_corruption_is_not_accepted(self) -> None:
        async def run() -> None:
            request = rt.ResearchJobRequest(action_id="receipt-check", query="Public research")
            submitted = await rt.submit_research_job(self.runtime, "owner", request)
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            provider = AsyncMock(
                return_value=ResearchCompletion(
                    "保存する公開本文です。",
                    AttemptOutcome("succeeded", 200, "stop", 10, 10, 20, 100),
                )
            )
            args = (self.runtime, job_id, "boundary:receipt", "Public task", "Public input")
            with patch.object(rt, "complete_research", new=provider):
                first = await rt.invoke_job_model(*args, rt.validate_visible_markdown)
                second = await rt.invoke_job_model(*args, rt.validate_visible_markdown)
                self.assertEqual(first, second)
                self.assertEqual(provider.await_count, 1)
                self.runtime.db.execute(
                    "UPDATE research_attempts SET result_receipt = ? "
                    "WHERE job_id = ? AND assignment_key = ?",
                    ("破損により別の本文になりました。", job_id, "boundary:receipt"),
                )
                self.runtime.db.commit()
                with self.assertRaises(rt.IntegrityError):
                    await rt.invoke_job_model(*args, rt.validate_visible_markdown)
                self.assertEqual(provider.await_count, 1)

        asyncio.run(run())

    def test_restart_after_research_receipt_does_not_resend_with_changed_budget(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", fixtures.request())
            job_id = submitted["job_id"]
            provider = fixtures.FakeProvider(
                [
                    *fixtures.research_outputs(),
                    fixtures.completion(fixtures.ledger_json()),
                    fixtures.completion("## Unit 1\n\n公開資料に基づく本文です。[S1:P0-80]"),
                    fixtures.completion('{"patches":[],"notes":[],"regenerate_reason":null}'),
                ]
            )
            fixture = fixtures.ResearchJobTests()
            fixture.runtime = self.runtime
            save = rt.save_research_state
            interrupted = False

            async def interrupt_once(*args: Any, **kwargs: Any) -> None:
                nonlocal interrupted
                if not interrupted:
                    interrupted = True
                    raise asyncio.CancelledError
                await save(*args, **kwargs)

            with ExitStack() as stack:
                for context in fixture.patches(provider):
                    stack.enter_context(context)
                with (
                    patch.object(rt, "save_research_state", new=interrupt_once),
                    self.assertRaises(asyncio.CancelledError),
                ):
                    await rt.execute_research_job(self.runtime, job_id)
                self.assertEqual(len(provider.bodies), 1)
                await rt.recover_research_jobs(self.runtime)
                status = await rt.research_job_status(self.runtime, "owner-1", job_id)
                await rt.resume_research_job(self.runtime, "owner-1", job_id, status["revision"])
                await rt.execute_research_job(self.runtime, job_id)
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            error = self.runtime.db.execute(
                "SELECT error_code FROM research_jobs WHERE job_id = ?", (job_id,)
            ).fetchone()["error_code"]
            self.assertEqual(status["status"], "completed", str(error))
            self.assertEqual(len(provider.bodies), 7)
            self.assertFalse(provider.outputs)

        asyncio.run(run())
