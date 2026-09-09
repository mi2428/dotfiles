from __future__ import annotations

import asyncio
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from typing import cast
from unittest.mock import AsyncMock, patch

import token_accounting as accounting
from sakura_kimi_model import AttemptOutcome, ResearchCompletion, prepare_research_request
from test_support import RuntimeTestCase, rt

MODEL = "preview/Kimi-K2.7-Code"
GATEWAY = "http://llm.local/v1"


class TokenCounterTests(unittest.TestCase):
    def setUp(self) -> None:
        accounting._expected_profile.cache_clear()

    def test_pinned_offline_counter_and_real_request_boundary_are_stable(self) -> None:
        expected = accounting.expected_profile(MODEL, GATEWAY)
        self.assertEqual(
            expected["local_counts"],
            {"english": 22, "japanese": 25, "mixed": 32, "boundary-64k": 23190},
        )
        _name, system, user = accounting.boundary_case(MODEL)
        self.assertEqual(len(prepare_research_request(MODEL, system, user)), 65_535)
        accounting.verify_assets(accounting.default_asset_dir())

    def test_profile_validates_receipt_counts_identity_and_counter_implementation(self) -> None:
        db = sqlite3.connect(":memory:")
        db.row_factory = sqlite3.Row
        accounting.create_profile_tables(db)
        expected = accounting.expected_profile(MODEL, GATEWAY)
        counts = cast(dict[str, int], expected["local_counts"])
        self.assertIsInstance(counts, dict)
        accounting.record_verified_profile(db, MODEL, GATEWAY, counts, "fixture")
        self.assertTrue(accounting.profile_is_verified(db, MODEL, GATEWAY))
        for column, value in (
            ("cases_hash", "0" * 64),
            ("local_counts_json", json.dumps({"english": 1})),
            ("observed_counts_json", json.dumps({"english": 1})),
            ("counter_fingerprint", "0" * 64),
            ("verified_input_ceiling_tokens", 262_144),
        ):
            with self.subTest(column=column):
                accounting.record_verified_profile(db, MODEL, GATEWAY, counts, "fixture")
                db.execute(f"UPDATE token_accounting_profiles SET {column} = ?", (value,))
                self.assertFalse(accounting.profile_is_verified(db, MODEL, GATEWAY))
        accounting.record_verified_profile(db, MODEL, GATEWAY, counts, "fixture")
        with patch.object(accounting, "PATTERN", accounting.PATTERN + "|x"):
            accounting._expected_profile.cache_clear()
            self.assertFalse(accounting.profile_is_verified(db, MODEL, GATEWAY))
        accounting._expected_profile.cache_clear()
        db.close()

    def test_calibration_uses_existing_transport_and_persists_intent_usage_and_profile(
        self,
    ) -> None:
        async def run() -> None:
            with tempfile.TemporaryDirectory() as directory:
                path = str(Path(directory) / "shared.db")
                bodies: list[bytes] = []

                async def complete(
                    _base_url: str, _api_key: str, body: bytes, _lease: object
                ) -> ResearchCompletion:
                    bodies.append(body)
                    payload = json.loads(body)
                    messages = payload["messages"]
                    prompt_tokens = accounting.count_fresh_prompt_tokens(
                        messages[0]["content"], messages[1]["content"]
                    )
                    return ResearchCompletion(
                        "OK",
                        AttemptOutcome("succeeded", 200, "stop", prompt_tokens, 1, None, 10),
                    )

                with patch.object(accounting, "complete_research", new=complete):
                    await accounting.calibrate(
                        db_path=path,
                        base_url=GATEWAY,
                        api_key="fixture-key",
                        model=MODEL,
                        operator_id="fixture-operator",
                        timeout_seconds=1,
                        asset_dir=accounting.default_asset_dir(),
                    )
                self.assertEqual(len(bodies), 4)
                self.assertEqual(max(map(len, bodies)), 65_535)
                db = sqlite3.connect(path)
                db.row_factory = sqlite3.Row
                self.assertTrue(accounting.profile_is_verified(db, MODEL, GATEWAY))
                attempts = db.execute(
                    "SELECT state, input_tokens_estimated, output_tokens_reserved "
                    "FROM token_calibration_attempts"
                ).fetchall()
                self.assertEqual(len(attempts), 4)
                self.assertTrue(all(row["state"] == "succeeded" for row in attempts))
                self.assertTrue(all(row["output_tokens_reserved"] == 16_384 for row in attempts))
                db.close()

        asyncio.run(run())

    def test_unknown_calibration_blocks_blind_replay_until_exact_operator_abandon(self) -> None:
        async def run() -> None:
            with tempfile.TemporaryDirectory() as directory:
                path = str(Path(directory) / "shared.db")
                unknown = AsyncMock(
                    return_value=ResearchCompletion(
                        "", AttemptOutcome("unknown", None, None, None, None, None, 0)
                    )
                )
                with patch.object(accounting, "complete_research", new=unknown):
                    with self.assertRaisesRegex(RuntimeError, "blind replay"):
                        await accounting.calibrate(
                            db_path=path,
                            base_url=GATEWAY,
                            api_key="fixture-key",
                            model=MODEL,
                            operator_id="fixture-operator",
                            timeout_seconds=1,
                            asset_dir=accounting.default_asset_dir(),
                        )
                    with self.assertRaisesRegex(RuntimeError, "operator resolution"):
                        await accounting.calibrate(
                            db_path=path,
                            base_url=GATEWAY,
                            api_key="fixture-key",
                            model=MODEL,
                            operator_id="fixture-operator",
                            timeout_seconds=1,
                            asset_dir=accounting.default_asset_dir(),
                        )
                self.assertEqual(unknown.await_count, 1)
                db = sqlite3.connect(path)
                attempt_id = db.execute(
                    "SELECT attempt_id FROM token_calibration_attempts WHERE state = 'unknown'"
                ).fetchone()[0]
                db.close()
                accounting.abandon_calibration_attempt(
                    path,
                    attempt_id,
                    "operator-calibration-1",
                    "fixture-operator",
                    accounting.UNKNOWN_RISK_ACK,
                )
                accounting.abandon_calibration_attempt(
                    path,
                    attempt_id,
                    "operator-calibration-1",
                    "fixture-operator",
                    accounting.UNKNOWN_RISK_ACK,
                )

        asyncio.run(run())


class RuntimeTokenAdmissionTests(RuntimeTestCase):
    def test_send_reserves_exact_input_and_output_and_missing_usage_never_refunds(self) -> None:
        async def run() -> None:
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="token-reserve", query="q", depth="deep"),
            )
            job_id = str(submitted["job_id"])
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'running' WHERE job_id = ?", (job_id,)
            )
            self.runtime.db.commit()
            completion = ResearchCompletion(
                "receipt",
                AttemptOutcome("succeeded", 200, "stop", None, None, None, 10),
            )
            with patch.object(rt, "complete_research", new=AsyncMock(return_value=completion)):
                self.assertEqual(
                    await rt.invoke_job_model(
                        self.runtime, job_id, "assignment", "system", "user", lambda value: value
                    ),
                    "receipt",
                )
            attempt = self.runtime.db.execute(
                "SELECT input_tokens_estimated, output_tokens_reserved, accounting_profile "
                "FROM research_attempts WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            job = self.runtime.db.execute(
                "SELECT tokens_reserved FROM research_jobs WHERE job_id = ?", (job_id,)
            ).fetchone()
            expected_input = accounting.count_fresh_prompt_tokens("system", "user")
            self.assertEqual(attempt["input_tokens_estimated"], expected_input)
            self.assertEqual(attempt["output_tokens_reserved"], 16_384)
            self.assertTrue(attempt["accounting_profile"])
            self.assertEqual(job["tokens_reserved"], expected_input + 16_384)

            unknown_job = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="token-unknown", query="q", depth="deep"),
            )
            unknown_job_id = str(unknown_job["job_id"])
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'running' WHERE job_id = ?",
                (unknown_job_id,),
            )
            self.runtime.db.commit()
            unknown = ResearchCompletion(
                "", AttemptOutcome("unknown", None, None, None, None, None, 0)
            )
            with (
                patch.object(rt, "complete_research", new=AsyncMock(return_value=unknown)),
                self.assertRaises(rt.JobPaused),
            ):
                await rt.invoke_job_model(
                    self.runtime,
                    unknown_job_id,
                    "assignment",
                    "system",
                    "user",
                    lambda value: value,
                )
            held = self.runtime.db.execute(
                "SELECT tokens_reserved FROM research_jobs WHERE job_id = ?", (unknown_job_id,)
            ).fetchone()
            self.assertEqual(held["tokens_reserved"], expected_input + 16_384)

        asyncio.run(run())

    def test_missing_or_out_of_profile_admission_fails_before_provider_dispatch(self) -> None:
        async def run() -> None:
            self.runtime.db.execute("DELETE FROM token_accounting_profiles")
            self.runtime.db.commit()
            with self.assertRaises(rt.HTTPException) as missing:
                await rt.submit_research_job(
                    self.runtime,
                    "owner-1",
                    rt.ResearchJobRequest(action_id="missing-profile", query="q", depth="deep"),
                )
            self.assertEqual(missing.exception.status_code, 503)
            expected = accounting.expected_profile(
                self.runtime.settings.model, self.runtime.settings.llm_base_url
            )
            counts = cast(dict[str, int], expected["local_counts"])
            self.assertIsInstance(counts, dict)
            accounting.record_verified_profile(
                self.runtime.db,
                self.runtime.settings.model,
                self.runtime.settings.llm_base_url,
                counts,
                "synthetic-test-fixture",
            )
            self.runtime.db.commit()
            submitted = await rt.submit_research_job(
                self.runtime,
                "owner-1",
                rt.ResearchJobRequest(action_id="over-ceiling", query="q", depth="deep"),
            )
            job_id = str(submitted["job_id"])
            self.runtime.db.execute(
                "UPDATE research_jobs SET status = 'running' WHERE job_id = ?", (job_id,)
            )
            self.runtime.db.commit()
            provider = AsyncMock(side_effect=AssertionError("provider dispatched"))
            with (
                patch.object(rt, "complete_research", new=provider),
                self.assertRaises(rt.JobIncomplete),
            ):
                await rt.invoke_job_model(
                    self.runtime,
                    job_id,
                    "assignment",
                    "system",
                    "a " * 30_000,
                    lambda value: value,
                )
            provider.assert_not_awaited()
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM research_attempts WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                0,
            )

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
