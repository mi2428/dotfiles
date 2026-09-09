from __future__ import annotations

import asyncio
import unittest
from unittest.mock import patch

import deep_research_runtime as rt
from test_research_jobs import FakeProvider, completion, request
from test_support import RuntimeTestCase


class RuntimeOrchestrationTests(RuntimeTestCase):
    def test_retired_execution_entrypoints_are_absent(self) -> None:
        self.assertFalse(hasattr(rt, "run_research"))
        self.assertFalse(hasattr(rt, "reserve_run"))

    def test_job_worker_dispatches_only_one_job_at_a_time(self) -> None:
        async def run() -> None:
            queued = ["job-1", "job-2"]
            active = 0
            maximum = 0
            completed: list[str] = []

            async def next_job(_runtime: rt.Runtime) -> str | None:
                if queued:
                    return queued.pop(0)
                raise asyncio.CancelledError()

            async def execute(_runtime: rt.Runtime, job_id: str) -> None:
                nonlocal active, maximum
                active += 1
                maximum = max(maximum, active)
                await asyncio.sleep(0)
                completed.append(job_id)
                active -= 1

            with (
                patch.object(rt, "next_queued_job", new=next_job),
                patch.object(rt, "execute_research_job", new=execute),
                self.assertRaises(asyncio.CancelledError),
            ):
                await rt.research_job_worker(self.runtime)
            self.assertEqual(completed, ["job-1", "job-2"])
            self.assertEqual(maximum, 1)

        asyncio.run(run())

    def test_invalid_fresh_action_stops_incomplete_without_extractive_publication(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            provider = FakeProvider(
                [completion("not one JSON action"), completion("still not one JSON action")]
            )
            with patch.object(rt, "complete_research", new=provider):
                await rt.execute_research_job(self.runtime, submitted["job_id"])
            row = self.runtime.db.execute(
                "SELECT status, error_code, best_revision_id, selected_publication_id "
                "FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            self.assertEqual(
                (
                    row["status"],
                    row["error_code"],
                    row["best_revision_id"],
                    row["selected_publication_id"],
                ),
                ("incomplete", "assignment_result_invalid", None, None),
            )
            self.assertEqual(len(provider.bodies), 2)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) AS count FROM publications WHERE job_id = ?",
                    (submitted["job_id"],),
                ).fetchone()["count"],
                0,
            )

        asyncio.run(run())

    def test_restart_pauses_claimed_job_without_resetting_queued_work(self) -> None:
        async def run() -> None:
            claimed = await rt.submit_research_job(self.runtime, "owner-1", request())
            queued = await rt.submit_research_job(
                self.runtime, "owner-1", request(action_id="action-2")
            )
            self.assertTrue(await rt.claim_research_job(self.runtime, claimed["job_id"]))
            await rt.recover_research_jobs(self.runtime)
            claimed_status = await rt.research_job_status(
                self.runtime, "owner-1", claimed["job_id"]
            )
            queued_status = await rt.research_job_status(self.runtime, "owner-1", queued["job_id"])
            self.assertEqual(
                (claimed_status["status"], claimed_status["error_code"]),
                ("paused", "restart_interrupted"),
            )
            self.assertEqual(queued_status["status"], "queued")
            self.assertEqual(await rt.next_queued_job(self.runtime), queued["job_id"])

        asyncio.run(run())

    def test_cancelled_job_cannot_resume_after_its_absolute_deadline(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(self.runtime, "owner-1", request())
            cancelled = await rt.cancel_research_job(self.runtime, "owner-1", submitted["job_id"])
            deadline = rt.unix_ms() + rt.JOB_SAVE_RESERVE_SECONDS * 1000
            self.runtime.db.execute(
                "UPDATE research_jobs SET deadline_at_ms = ? WHERE job_id = ?",
                (deadline, submitted["job_id"]),
            )
            self.runtime.db.commit()
            with self.assertRaises(rt.HTTPException) as rejected:
                await rt.resume_research_job(
                    self.runtime,
                    "owner-1",
                    submitted["job_id"],
                    cancelled["revision"],
                )
            self.assertEqual(rejected.exception.status_code, 409)
            row = self.runtime.db.execute(
                "SELECT deadline_at_ms, attempts_used FROM research_jobs WHERE job_id = ?",
                (submitted["job_id"],),
            ).fetchone()
            self.assertEqual((row["deadline_at_ms"], row["attempts_used"]), (deadline, 0))

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main(verbosity=2)
