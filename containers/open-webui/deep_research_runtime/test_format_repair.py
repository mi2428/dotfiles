import asyncio
import json
from unittest.mock import AsyncMock, patch

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class FormatRepairTests(RuntimeTestCase):
    def test_json_fence_accepts_one_object_and_rejects_trailing_content(self) -> None:
        for text in (
            '```json{"value":"q"}```',
            '```json\n{"value":"q"}\n```',
        ):
            self.assertEqual(rt.parse_json_object(text)["value"], "q")
        for text in (
            '```json{"value":"q"}{"extra":1}```',
            '{"value":"q"} trailing prose',
        ):
            with self.assertRaises(ValueError):
                rt.parse_json_object(text)

    def test_completed_empty_research_response_gets_one_charged_correction(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime, "owner", rt.ResearchJobRequest(action_id="empty", query="q")
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion(
                        "", AttemptOutcome("known_failed", 200, "stop", 10, 10, 20, 100)
                    ),
                    ResearchCompletion(
                        "receipt", AttemptOutcome("succeeded", 200, "stop", 10, 10, 20, 100)
                    ),
                ]
            )
            with patch.object(rt, "complete_research", new=provider):
                self.assertEqual(
                    await rt.invoke_job_model(
                        self.runtime, job_id, "research_step_1", "system", "user", str
                    ),
                    "receipt",
                )
            self.assertEqual(provider.await_count, 2)
            self.assertEqual((await rt.load_job(self.runtime, job_id))["attempts_used"], 2)

        asyncio.run(run())

    def test_one_charged_repair_per_assignment_and_saved_receipt(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime, "owner", rt.ResearchJobRequest(action_id="format", query="q")
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            deadline = (await rt.load_job(self.runtime, job_id))["deadline_at_ms"]
            outcome = AttemptOutcome("succeeded", 200, "stop", 10, 10, 20, 100)
            good = '{"value":"q"}'
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion("not JSON", outcome),
                    ResearchCompletion(good, outcome),
                    ResearchCompletion("invalid again", outcome),
                    ResearchCompletion(good, outcome),
                ]
            )

            def accept(value: str) -> str:
                return json.dumps(rt.parse_json_object(value), separators=(",", ":"))

            with patch.object(rt, "complete_research", new=provider):
                first = await rt.invoke_job_model(
                    self.runtime, job_id, "research_step_1", "JSON schema", "q", accept
                )
                self.assertEqual(first, good)
                self.assertEqual(
                    await rt.invoke_job_model(
                        self.runtime, job_id, "research_step_1", "JSON schema", "q", accept
                    ),
                    good,
                )
                self.assertEqual(provider.await_count, 2)
                repair_request = json.loads(provider.await_args_list[1].args[2])
                self.assertIn(
                    "model output is not one JSON object",
                    repair_request["messages"][0]["content"],
                )
                self.assertEqual(
                    await rt.invoke_job_model(
                        self.runtime, job_id, "candidate_1_ledger", "JSON schema", "q", accept
                    ),
                    good,
                )
            self.assertEqual(provider.await_count, 4)
            saved = await rt.load_job(self.runtime, job_id)
            self.assertEqual(saved["attempts_used"], 4)
            self.assertEqual(saved["deadline_at_ms"], deadline)

        asyncio.run(run())

    def test_numeric_repair_repeats_both_coupled_constraints(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime, "owner", rt.ResearchJobRequest(action_id="numeric", query="q")
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            outcome = AttemptOutcome("succeeded", 200, "stop", 10, 10, 20, 100)
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion("bad", outcome),
                    ResearchCompletion("good", outcome),
                ]
            )

            def accept(value: str) -> str:
                if value == "bad":
                    raise ValueError(
                        "every Markdown block containing a digit needs an admitted citation "
                        "in that block"
                    )
                return value

            with patch.object(rt, "complete_research", new=provider):
                self.assertEqual(
                    await rt.invoke_job_model(
                        self.runtime, job_id, "candidate_1_author_unit_1", "system", "user", accept
                    ),
                    "good",
                )
            repair_request = json.loads(provider.await_args_list[1].args[2])
            repair_prompt = repair_request["messages"][0]["content"]
            self.assertIn("every Markdown block containing a digit", repair_prompt)
            self.assertIn("every numeric derivation needs explicit assumptions", repair_prompt)

        asyncio.run(run())

    def test_retryable_http_failures_use_exponential_backoff(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime, "owner", rt.ResearchJobRequest(action_id="backoff", query="q")
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion(
                        "", AttemptOutcome("not_sent", 502, None, None, None, None, 70)
                    ),
                    ResearchCompletion(
                        "", AttemptOutcome("known_failed", 429, None, None, None, None, 80)
                    ),
                    ResearchCompletion(
                        "receipt",
                        AttemptOutcome("succeeded", 200, "stop", 1, 2, 3, 90),
                    ),
                ]
            )
            sleep = AsyncMock()
            with (
                patch.object(rt, "complete_research", new=provider),
                patch.object(rt.random, "uniform", return_value=0),
                patch.object(rt.asyncio, "sleep", new=sleep),
            ):
                for _ in range(2):
                    self.assertEqual(
                        await rt.invoke_job_model(
                            self.runtime,
                            job_id,
                            "candidate_1_author_unit_1",
                            "system",
                            "user",
                            str,
                        ),
                        "receipt",
                    )
            self.assertEqual([call.args[0] for call in sleep.await_args_list], [1.0, 2.0])
            self.assertEqual(provider.await_count, 3)
            self.assertEqual((await rt.load_job(self.runtime, job_id))["attempts_used"], 3)
            attempt_ids = [call.args[3].attempt_id for call in provider.await_args_list]
            self.assertEqual(len(attempt_ids), len(set(attempt_ids)))
            rows = self.runtime.db.execute(
                "SELECT assignment_key,state,http_status FROM research_attempts "
                "WHERE job_id=? ORDER BY created_at_ms",
                (job_id,),
            ).fetchall()
            self.assertEqual(
                [tuple(row) for row in rows],
                [
                    ("candidate_1_author_unit_1", "not_sent", 502),
                    ("candidate_1_author_unit_1:transport-retry-1", "known_failed", 429),
                    ("candidate_1_author_unit_1:transport-retry-2", "succeeded", 200),
                ],
            )

        asyncio.run(run())

    def test_failed_correction_and_unknown_transport_are_not_replayed(self) -> None:
        async def run() -> None:
            for suffix, outputs, expected in (
                (
                    "invalid",
                    [
                        ResearchCompletion(
                            "bad", AttemptOutcome("succeeded", 200, "stop", 1, 1, 2, 10)
                        ),
                        ResearchCompletion(
                            "still bad", AttemptOutcome("succeeded", 200, "stop", 1, 1, 2, 10)
                        ),
                    ],
                    rt.JobIncomplete,
                ),
                (
                    "unknown",
                    [
                        ResearchCompletion(
                            "", AttemptOutcome("unknown", None, None, None, None, None, 10)
                        )
                    ],
                    rt.JobPaused,
                ),
            ):
                job = await rt.submit_research_job(
                    self.runtime,
                    "owner",
                    rt.ResearchJobRequest(action_id=suffix, query="q"),
                )
                job_id = job["job_id"]
                await rt.claim_research_job(self.runtime, job_id)
                provider = AsyncMock(side_effect=outputs)
                with patch.object(rt, "complete_research", new=provider):
                    with self.assertRaises(expected):
                        await rt.invoke_job_model(
                            self.runtime,
                            job_id,
                            "candidate_1_ledger",
                            "system",
                            "user",
                            lambda value: json.dumps(rt.parse_json_object(value)),
                        )
                    with self.assertRaises(expected):
                        await rt.invoke_job_model(
                            self.runtime,
                            job_id,
                            "candidate_1_ledger",
                            "system",
                            "user",
                            lambda value: json.dumps(rt.parse_json_object(value)),
                        )
                self.assertEqual(provider.await_count, len(outputs))

        asyncio.run(run())

    def test_permanent_client_error_is_not_retried(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime,
                "owner",
                rt.ResearchJobRequest(action_id="client-error-stops", query="q"),
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            provider = AsyncMock(
                return_value=ResearchCompletion(
                    "", AttemptOutcome("known_failed", 401, None, None, None, None, 10)
                )
            )
            with patch.object(rt, "complete_research", new=provider):
                for _ in range(2):
                    with self.assertRaises(rt.JobIncomplete):
                        await rt.invoke_job_model(
                            self.runtime,
                            job_id,
                            "candidate_1_author_unit_1",
                            "system",
                            "user",
                            str,
                        )
            self.assertEqual(provider.await_count, 1)
            self.assertEqual(
                self.runtime.db.execute(
                    "SELECT COUNT(*) FROM research_attempts WHERE job_id = ?", (job_id,)
                ).fetchone()[0],
                1,
            )

        asyncio.run(run())
