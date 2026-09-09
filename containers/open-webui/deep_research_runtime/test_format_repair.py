import asyncio
import json
from unittest.mock import AsyncMock, patch

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class FormatRepairTests(RuntimeTestCase):
    def test_json_fence_and_repeated_objects_use_the_first_complete_object(self) -> None:
        for text in (
            '```json{"value":"q"}```',
            '```json\n{"value":"q"}\n```',
            '```json{"value":"q"}{"extra":1}```',
        ):
            self.assertEqual(rt.parse_json_object(text)["value"], "q")
        with self.assertRaises(ValueError):
            rt.parse_json_object('{"value":"q"} trailing prose')

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

    def test_rate_limit_gets_one_new_bounded_attempt(self) -> None:
        async def run() -> None:
            for suffix, outputs, succeeds in (
                (
                    "recovers",
                    [
                        ResearchCompletion(
                            "", AttemptOutcome("known_failed", 429, None, None, None, None, 10)
                        ),
                        ResearchCompletion(
                            "receipt", AttemptOutcome("succeeded", 200, "stop", 1, 1, 2, 10)
                        ),
                    ],
                    True,
                ),
                (
                    "stops",
                    [
                        ResearchCompletion(
                            "", AttemptOutcome("known_failed", 429, None, None, None, None, 10)
                        ),
                        ResearchCompletion(
                            "", AttemptOutcome("known_failed", 429, None, None, None, None, 10)
                        ),
                    ],
                    False,
                ),
            ):
                job = await rt.submit_research_job(
                    self.runtime,
                    "owner",
                    rt.ResearchJobRequest(action_id=f"rate-{suffix}", query="q"),
                )
                job_id = job["job_id"]
                await rt.claim_research_job(self.runtime, job_id)
                provider = AsyncMock(side_effect=outputs)
                with patch.object(rt, "complete_research", new=provider):
                    if succeeds:
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
                    else:
                        with self.assertRaises(rt.JobIncomplete):
                            await rt.invoke_job_model(
                                self.runtime,
                                job_id,
                                "candidate_1_author_unit_1",
                                "system",
                                "user",
                                str,
                            )
                        with self.assertRaises(rt.JobIncomplete):
                            await rt.invoke_job_model(
                                self.runtime,
                                job_id,
                                "candidate_1_author_unit_1",
                                "system",
                                "user",
                                str,
                            )
                self.assertEqual(provider.await_count, 2)

        asyncio.run(run())
