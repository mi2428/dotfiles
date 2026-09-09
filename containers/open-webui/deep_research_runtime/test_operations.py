from __future__ import annotations

import asyncio
import hashlib
import unittest
from dataclasses import replace
from unittest.mock import AsyncMock

import httpx

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class OperationsTests(RuntimeTestCase):
    async def job_with_publication(
        self, action_id: str = "action-delivery"
    ) -> tuple[str, str, str]:
        submitted = await rt.submit_research_job(
            self.runtime,
            "owner-1",
            rt.ResearchJobRequest(action_id=action_id, query="q", depth="deep"),
        )
        job_id = str(submitted["job_id"])
        markdown = "# exact publication\n"
        content_hash = hashlib.sha256(markdown.encode()).hexdigest()
        now = rt.unix_ms()
        cursor = self.runtime.db.execute(
            "INSERT INTO editorial_revisions "
            "(job_id, candidate_no, revision_no, kind, unit_no, markdown, data_json, "
            "manifest_json, content_hash, created_at_ms) VALUES (?, 1, 1, 'edited', 0, ?, '{}', "
            "'[]', ?, ?)",
            (job_id, markdown, "0" * 64, now),
        )
        publication_id = "publication-1-" + action_id
        self.runtime.db.execute(
            "INSERT INTO publications (publication_id, job_id, candidate_no, revision_id, "
            "quality_outcome, markdown, content_hash, created_at_ms) "
            "VALUES (?, ?, 1, ?, 'publish', ?, ?, ?)",
            (publication_id, job_id, cursor.lastrowid, markdown, content_hash, now),
        )
        self.runtime.db.execute(
            "UPDATE research_jobs SET status = 'completed', selected_publication_id = ?, "
            "delivery_status = 'pending' WHERE job_id = ?",
            (publication_id, job_id),
        )
        self.runtime.db.commit()
        return job_id, publication_id, content_hash

    def test_delivery_ack_is_owner_scoped_exact_and_idempotent(self) -> None:
        async def run() -> None:
            job_id, publication_id, content_hash = await self.job_with_publication()
            transport = httpx.ASGITransport(app=rt.app)
            headers = {
                "Authorization": "Bearer test-api-key",
                "X-Research-Owner": "owner-1",
            }
            body = {
                "publication_id": publication_id,
                "content_hash": content_hash,
                "note_id": "note-1",
            }
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                status_before = (
                    await client.get(f"/research/jobs/{job_id}", headers=headers)
                ).json()
                self.assertEqual(status_before["delivery_status"], "pending")
                self.assertIsNone(status_before["delivery"])
                first = await client.post(
                    f"/research/jobs/{job_id}/delivery", headers=headers, json=body
                )
                second = await client.post(
                    f"/research/jobs/{job_id}/delivery", headers=headers, json=body
                )
                conflict = await client.post(
                    f"/research/jobs/{job_id}/delivery",
                    headers=headers,
                    json={**body, "note_id": "note-2"},
                )
                wrong_owner = await client.post(
                    f"/research/jobs/{job_id}/delivery",
                    headers={**headers, "X-Research-Owner": "owner-2"},
                    json=body,
                )
                result = (
                    await client.get(f"/research/jobs/{job_id}/result", headers=headers)
                ).json()
            self.assertEqual((first.status_code, second.status_code), (200, 200))
            self.assertEqual(first.json(), second.json())
            self.assertEqual((conflict.status_code, wrong_owner.status_code), (409, 404))
            self.assertEqual(result["delivery_status"], "delivered")
            self.assertEqual(result["delivery"]["note_id"], "note-1")

        asyncio.run(run())

    def test_action_cancel_before_submit_is_atomic_idempotent_and_hash_bound(self) -> None:
        async def run() -> None:
            request = rt.ResearchJobRequest(action_id="action-pre-cancel", query="q", depth="deep")
            provider = rt.complete_research
            dispatched = AsyncMock(side_effect=AssertionError("inference dispatched"))
            rt.complete_research = dispatched
            try:
                transport = httpx.ASGITransport(app=rt.app)
                headers = {
                    "Authorization": "Bearer test-api-key",
                    "X-Research-Owner": "owner-1",
                }
                async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                    first = await client.post(
                        "/research/actions/action-pre-cancel/cancel",
                        headers=headers,
                        json=request.model_dump(),
                    )
                    second = await client.post(
                        "/research/actions/action-pre-cancel/cancel",
                        headers=headers,
                        json=request.model_dump(),
                    )
                    conflict = await client.post(
                        "/research/actions/action-pre-cancel/cancel",
                        headers=headers,
                        json={**request.model_dump(), "query": "changed"},
                    )
            finally:
                rt.complete_research = provider
            self.assertEqual(first.json(), second.json())
            self.assertEqual(
                first.json(),
                {"action_id": "action-pre-cancel", "status": "cancelled", "job_id": None},
            )
            self.assertEqual(conflict.status_code, 409)
            dispatched.assert_not_awaited()
            with self.assertRaises(rt.HTTPException) as late_submit:
                await rt.submit_research_job(self.runtime, "owner-1", request)
            self.assertEqual(
                (late_submit.exception.status_code, late_submit.exception.detail),
                (409, "action_cancelled"),
            )
            self.assertEqual(
                self.runtime.db.execute("SELECT COUNT(*) FROM research_jobs").fetchone()[0], 0
            )

        asyncio.run(run())

    def test_action_cancel_after_submit_observes_running_job_and_blocks_late_submit(self) -> None:
        async def run() -> None:
            request = rt.ResearchJobRequest(action_id="action-post-cancel", query="q", depth="deep")
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request)
            job_id = str(submitted["job_id"])
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'running' WHERE job_id = ?", (job_id,)
            )
            self.runtime.db.commit()
            cancelled = await rt.cancel_research_action(
                self.runtime, "owner-1", request.action_id, request
            )
            self.assertEqual(
                cancelled,
                {
                    "action_id": request.action_id,
                    "status": "cancel_requested",
                    "job_id": job_id,
                },
            )
            row = self.runtime.db.execute(
                "SELECT status, cancel_requested FROM research_jobs WHERE job_id = ?", (job_id,)
            ).fetchone()
            self.assertEqual(tuple(row), ("running", 1))
            with self.assertRaises(rt.HTTPException) as late_submit:
                await rt.submit_research_job(self.runtime, "owner-1", request)
            self.assertEqual(late_submit.exception.detail, "action_cancelled")

        asyncio.run(run())

    def test_action_cancel_and_submit_race_leaves_no_dispatchable_job(self) -> None:
        async def run() -> None:
            request = rt.ResearchJobRequest(action_id="action-race", query="q", depth="deep")

            async def submit() -> object:
                try:
                    return await rt.submit_research_job(self.runtime, "owner-1", request)
                except rt.HTTPException as exc:
                    return exc

            await asyncio.gather(
                submit(),
                rt.cancel_research_action(self.runtime, "owner-1", request.action_id, request),
            )
            cancellation = self.runtime.db.execute(
                "SELECT request_hash, job_id FROM research_action_cancellations "
                "WHERE owner_id = 'owner-1' AND action_id = 'action-race'"
            ).fetchone()
            self.assertIsNotNone(cancellation)
            rows = self.runtime.db.execute(
                "SELECT status, cancel_requested FROM research_jobs WHERE action_id = 'action-race'"
            ).fetchall()
            self.assertTrue(not rows or tuple(rows[0]) == ("cancelled", 1))
            self.assertIsNone(await rt.next_queued_job(self.runtime))

        asyncio.run(run())

    def test_delivery_ack_rejects_corrupted_stored_publication(self) -> None:
        async def run() -> None:
            job_id, publication_id, content_hash = await self.job_with_publication("action-corrupt")
            self.runtime.db.execute(
                "UPDATE publications SET markdown = 'corrupt' WHERE publication_id = ?",
                (publication_id,),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.IntegrityError):
                await rt.acknowledge_research_delivery(
                    self.runtime,
                    "owner-1",
                    job_id,
                    rt.DeliveryAckRequest(
                        publication_id=publication_id,
                        content_hash=content_hash,
                        note_id="note-corrupt",
                    ),
                )
            self.assertIsNone(
                self.runtime.db.execute(
                    "SELECT 1 FROM publication_deliveries WHERE job_id = ?", (job_id,)
                ).fetchone()
            )

        asyncio.run(run())

    def test_operator_exact_ack_abandons_unknown_and_releases_only_matching_account(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="action-unknown", query="q", depth="deep"),
            )
            job_id = str(submitted["job_id"])
            attempt_id = "attempt-unknown"
            now = rt.unix_ms()
            self.runtime.db.execute(
                "INSERT INTO research_attempts "
                "(attempt_id, job_id, assignment, assignment_key, candidate_no, state, "
                "expires_at_ms, request_hash, created_at_ms, updated_at_ms) "
                "VALUES (?, ?, 'research', 'research', 0, 'unknown', ?, ?, ?, ?)",
                (attempt_id, job_id, now, "0" * 64, now, now),
            )
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'paused', revision = 7, attempts_used = 1 "
                "WHERE job_id = ?",
                (job_id,),
            )
            self.runtime.db.execute(
                "INSERT INTO account_admissions "
                "(account_id, state, lease_id, purpose, cooldown_until_ms, updated_at_ms) "
                "VALUES ('account-public-a', 'unknown', ?, 'research', 0, ?)",
                (attempt_id, now),
            )
            self.runtime.db.commit()
            body = {
                "job_id": job_id,
                "attempt_id": attempt_id,
                "action_id": "operator-action-1",
                "expected_revision": 7,
                "risk_ack": rt.UNKNOWN_RISK_ACK,
            }
            transport = httpx.ASGITransport(app=rt.app)
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                denied = await client.post(
                    "/internal/research/attempts/abandon",
                    headers={"Authorization": "Bearer test-api-key"},
                    json=body,
                )
                first = await client.post(
                    "/internal/research/attempts/abandon",
                    headers={"Authorization": "Bearer test-operator-key"},
                    json=body,
                )
                second = await client.post(
                    "/internal/research/attempts/abandon",
                    headers={"Authorization": "Bearer test-operator-key"},
                    json=body,
                )
            self.assertEqual(denied.status_code, 401)
            self.assertEqual((first.status_code, second.status_code), (200, 200))
            self.assertEqual(first.json(), second.json())
            attempt = self.runtime.db.execute(
                "SELECT state, resolution_operator_id, resolution_action_id FROM research_attempts "
                "WHERE attempt_id = ?",
                (attempt_id,),
            ).fetchone()
            job = self.runtime.db.execute(
                "SELECT status, error_code, attempts_used FROM research_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            account = self.runtime.db.execute(
                "SELECT state, lease_id FROM account_admissions "
                "WHERE account_id = 'account-public-a'"
            ).fetchone()
            self.assertEqual(
                tuple(attempt), ("abandoned_unresolved", "test-operator", "operator-action-1")
            )
            self.assertEqual(tuple(job), ("incomplete", "abandoned_unresolved", 1))
            self.assertEqual(tuple(account), ("available", None))
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM account_admission_audit WHERE lease_id = ?",
                    (attempt_id,),
                ).fetchone()[0],
                1,
            )

        asyncio.run(run())

    def test_retention_purges_only_old_delivered_safe_jobs_and_leaves_tombstone(self) -> None:
        async def run() -> None:
            job_id, publication_id, content_hash = await self.job_with_publication("action-old")
            await rt.acknowledge_research_delivery(
                self.runtime,
                "owner-1",
                job_id,
                rt.DeliveryAckRequest(
                    publication_id=publication_id, content_hash=content_hash, note_id="note-old"
                ),
            )
            now = rt.unix_ms()
            old = now - 31 * 24 * 60 * 60 * 1000
            self.runtime.db.execute(
                "UPDATE research_jobs SET updated_at_ms = ? WHERE job_id = ?", (old, job_id)
            )
            self.runtime.db.commit()
            self.assertEqual(await rt.purge_expired_jobs(self.runtime, now_ms=now), 1)
            with self.assertRaises(rt.HTTPException) as expired:
                await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(expired.exception.status_code, 410)
            with self.assertRaises(rt.HTTPException) as replay:
                await rt.submit_research_job(
                    self.runtime,
                    "owner-1",
                    rt.ResearchJobRequest(action_id="action-old", query="q", depth="deep"),
                )
            self.assertEqual(replay.exception.status_code, 410)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM research_job_tombstones WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                1,
            )

        asyncio.run(run())

    def test_retention_purges_terminal_without_publication_but_keeps_publication_and_unknown(
        self,
    ) -> None:
        async def run() -> None:
            now = rt.unix_ms()
            old = now - 31 * 24 * 60 * 60 * 1000
            failed = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="action-failed", query="q", depth="deep"),
            )
            pending_id, _publication_id, _content_hash = await self.job_with_publication(
                "action-pending"
            )
            unknown = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="action-held", query="q", depth="deep"),
            )
            unknown_id = str(unknown["job_id"])
            self.runtime.db.execute(
                "INSERT INTO research_attempts "
                "(attempt_id, job_id, assignment, assignment_key, candidate_no, state, "
                "expires_at_ms, request_hash, created_at_ms, updated_at_ms) "
                "VALUES ('attempt-held', ?, 'a', 'a', 0, 'unknown', ?, ?, ?, ?)",
                (unknown_id, old, "0" * 64, old, old),
            )
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'failed', updated_at_ms = ? "
                "WHERE job_id IN (?, ?)",
                (old, str(failed["job_id"]), unknown_id),
            )
            self.runtime.db.execute(
                "UPDATE research_jobs SET updated_at_ms = ? WHERE job_id = ?", (old, pending_id)
            )
            self.runtime.db.commit()
            self.assertEqual(await rt.purge_expired_jobs(self.runtime, now_ms=now), 1)
            remaining = {
                str(row["job_id"])
                for row in self.runtime.db.execute("SELECT job_id FROM research_jobs")
            }
            self.assertEqual(remaining, {pending_id, unknown_id})

        asyncio.run(run())

    def test_operator_can_exactly_resolve_orphan_unknown_account_lease(self) -> None:
        async def run() -> None:
            now = rt.unix_ms()
            self.runtime.db.execute(
                "INSERT INTO account_admissions "
                "(account_id, state, lease_id, purpose, cooldown_until_ms, updated_at_ms) "
                "VALUES ('orphan-account', 'unknown', 'orphan-lease', 'normal', 0, ?)",
                (now,),
            )
            self.runtime.db.commit()
            body = rt.AbandonOrphanAccountRequest(
                account_id="orphan-account",
                lease_id="orphan-lease",
                action_id="operator-orphan-1",
                risk_ack=rt.UNKNOWN_RISK_ACK,
            )
            first = await rt.abandon_orphan_account_lease(self.runtime, body)
            second = await rt.abandon_orphan_account_lease(self.runtime, body)
            self.assertEqual(first, second)
            row = self.runtime.db.execute(
                "SELECT state, lease_id FROM account_admissions WHERE account_id = 'orphan-account'"
            ).fetchone()
            audit = self.runtime.db.execute(
                "SELECT event, actor, risk_ack FROM account_admission_audit "
                "WHERE action_id = 'operator-orphan-1'"
            ).fetchone()
            self.assertEqual(tuple(row), ("available", None))
            self.assertEqual(
                tuple(audit), ("operator_orphan_unknown", "test-operator", rt.UNKNOWN_RISK_ACK)
            )

        asyncio.run(run())

    def test_stop_observes_current_call_and_persists_known_result(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="action-stop", query="q", depth="deep"),
            )
            job_id = str(submitted["job_id"])
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'running' WHERE job_id = ?", (job_id,)
            )
            self.runtime.db.commit()
            started = asyncio.Event()
            release = asyncio.Event()

            async def provider(*_args: object) -> ResearchCompletion:
                started.set()
                await release.wait()
                return ResearchCompletion(
                    "known-result",
                    AttemptOutcome("succeeded", 200, "stop", 3, 2, 5, 20),
                )

            original = rt.complete_research
            rt.complete_research = provider
            try:
                task = asyncio.create_task(
                    rt.invoke_job_model(
                        self.runtime, job_id, "assignment", "system", "user", lambda value: value
                    )
                )
                await asyncio.wait_for(started.wait(), timeout=1)
                await rt.cancel_research_job(self.runtime, "owner-1", job_id)
                self.assertFalse(task.done())
                release.set()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            finally:
                rt.complete_research = original
            attempt = self.runtime.db.execute(
                "SELECT state, result_receipt FROM research_attempts WHERE job_id = ?", (job_id,)
            ).fetchone()
            self.assertEqual(tuple(attempt), ("succeeded", "known-result"))

        asyncio.run(run())

    def test_global_logical_quota_rejects_payload_without_partial_write(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="action-quota", query="q", depth="deep"),
            )
            job_id = str(submitted["job_id"])
            used = rt.logical_storage_bytes(self.runtime.db)
            self.runtime.settings = replace(self.runtime.settings, global_logical_bytes=used + 10)
            with self.assertRaises(rt.StorageQuotaExceeded):
                await rt.store_source_blob(
                    self.runtime,
                    job_id,
                    rt.FetchedSourceBlob(
                        "https://example.com/a",
                        "https://example.com/a",
                        "title",
                        "publisher",
                        "text/plain",
                        b"payload",
                    ),
                )
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM source_blobs WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                0,
            )

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
