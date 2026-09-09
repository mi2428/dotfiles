from __future__ import annotations

import asyncio
import json
from unittest.mock import AsyncMock, patch

import httpx

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class ProviderUsageTests(RuntimeTestCase):
    def test_fresh_install_accepts_authenticated_request_without_calibration(self) -> None:
        async def run() -> None:
            tables = {row[0] for row in self.runtime.db.execute("SELECT name FROM sqlite_master")}
            self.assertNotIn("token_accounting_profiles", tables)
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=rt.app), base_url="http://test"
            ) as client:
                health = await client.get("/health")
                self.assertEqual(
                    health.json(),
                    {
                        "status": "ok",
                        "token_accounting": {"mode": "provider_usage"},
                    },
                )
                request = {"action_id": "fresh-action", "query": "Read public documentation"}
                denied = await client.post("/research/jobs", json=request)
                self.assertEqual(denied.status_code, 401)
                headers = {
                    "Authorization": f"Bearer {self.runtime.settings.api_key}",
                    "X-Research-Owner": "owner-1",
                }
                accepted = await client.post("/research/jobs", json=request, headers=headers)
                self.assertEqual(accepted.status_code, 202)
                replay = await client.post("/research/jobs", json=request, headers=headers)
                self.assertEqual(accepted.json()["job_id"], replay.json()["job_id"])
                headers["X-Research-Owner"] = "other-owner"
                denied = await client.get(accepted.json()["status_url"], headers=headers)
                self.assertEqual(denied.status_code, 404)
            self.assertEqual(
                self.runtime.db.execute("SELECT COUNT(*) FROM research_attempts").fetchone()[0], 0
            )

        asyncio.run(run())

    def test_reported_usage_and_unknown_preserve_attempt_accounting(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(
                self.runtime, "owner-1", rt.ResearchJobRequest(action_id="usage", query="q")
            )
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            before = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertIsNone(before["tokens"]["reported_total_tokens"])
            self.assertFalse(before["tokens"]["usage_complete"])
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion(
                        "receipt", AttemptOutcome("succeeded", 200, "stop", 10, 5, 15, 100)
                    ),
                    ResearchCompletion(
                        "", AttemptOutcome("unknown", None, None, None, None, None, 0)
                    ),
                ]
            )
            with patch.object(rt, "complete_research", new=provider):
                await rt.invoke_job_model(self.runtime, job_id, "first", "system", "user", str)
                complete = await rt.research_job_status(self.runtime, "owner-1", job_id)
                self.assertTrue(complete["tokens"]["usage_complete"])
                with self.assertRaises(rt.JobPaused):
                    await rt.invoke_job_model(self.runtime, job_id, "second", "system", "user", str)
                with self.assertRaises(rt.JobPaused):
                    await rt.invoke_job_model(self.runtime, job_id, "third", "system", "user", str)
            after = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(provider.await_count, 2)
            self.assertEqual(after["attempts"]["used"], 2)
            self.assertEqual(after["deadline_at_ms"], before["deadline_at_ms"])
            self.assertTrue(after["dispatch_blocked"])
            self.assertEqual(
                after["tokens"],
                {
                    "source": "provider_usage",
                    "reported_prompt_tokens": 10,
                    "reported_completion_tokens": 5,
                    "reported_total_tokens": 15,
                    "reported_attempts": 1,
                    "attempts": 2,
                    "usage_complete": False,
                },
            )

        asyncio.run(run())

    def test_existing_schema_and_request_limits_need_no_token_profile(self) -> None:
        async def run() -> None:
            # Old accounting records remain intact, but do not gate admission anymore.
            self.runtime.db.execute(
                "ALTER TABLE research_jobs ADD COLUMN token_allowance INTEGER NOT NULL DEFAULT 0"
            )
            self.runtime.db.execute(
                "ALTER TABLE research_jobs ADD COLUMN tokens_reserved INTEGER NOT NULL DEFAULT 999"
            )
            self.runtime.db.execute("CREATE TABLE token_accounting_profiles (obsolete TEXT)")
            self.runtime.db.execute("INSERT INTO token_accounting_profiles VALUES ('stale')")
            self.runtime.db.commit()
            submitted = await rt.submit_research_job(
                self.runtime, "owner-1", rt.ResearchJobRequest(action_id="bounded", query="q")
            )
            job_id = submitted["job_id"]
            self.assertTrue(await rt.claim_research_job(self.runtime, job_id))
            provider = AsyncMock(
                return_value=ResearchCompletion(
                    "receipt", AttemptOutcome("succeeded", 200, "stop", None, None, None, 10)
                )
            )
            with patch.object(rt, "complete_research", new=provider):
                with self.assertRaises(rt.JobIncomplete):
                    await rt.invoke_job_model(
                        self.runtime, job_id, "oversize", "system", "a" * 70_000, str
                    )
                provider.assert_not_awaited()
                await rt.invoke_job_model(
                    self.runtime, job_id, "within-byte-limit", "system", "a" * 60_000, str
                )
                assert provider.await_args is not None
                body = json.loads(provider.await_args.args[2])
                self.assertEqual(body["max_tokens"], 16_384)
                self.assertLessEqual(len(provider.await_args.args[2]), 65_536)
                self.runtime.db.execute(
                    "UPDATE research_jobs SET attempts_used = max_attempts WHERE job_id = ?",
                    (job_id,),
                )
                self.runtime.db.commit()
                with self.assertRaisesRegex(rt.JobIncomplete, "attempt_budget_exhausted"):
                    await rt.invoke_job_model(
                        self.runtime, job_id, "over-budget", "system", "user", str
                    )
            self.assertEqual(provider.await_count, 1)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT tokens_reserved FROM research_jobs WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                999,
            )
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT obsolete FROM token_accounting_profiles"
                ).fetchone()[0],
                "stale",
            )

        asyncio.run(run())
