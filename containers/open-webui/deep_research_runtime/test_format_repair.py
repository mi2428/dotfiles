import asyncio
import json
from unittest.mock import AsyncMock, patch

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


class FormatRepairTests(RuntimeTestCase):
    def test_single_object_fence_does_not_require_line_breaks(self) -> None:
        for text in (
            '```json{"action":"search","query":"q"}```',
            '```json\n{"action":"search","query":"q"}\n```',
        ):
            self.assertEqual(rt.parse_research_action(text).action, "search")
        with self.assertRaises(ValueError):
            rt.parse_research_action('```json{"action":"search","query":"q"}{"extra":1}```')

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

    def test_one_charged_repair_and_saved_receipt_without_replaying_unknown(self) -> None:
        async def run() -> None:
            job = await rt.submit_research_job(
                self.runtime, "owner", rt.ResearchJobRequest(action_id="format", query="q")
            )
            job_id = job["job_id"]
            await rt.claim_research_job(self.runtime, job_id)
            deadline = (await rt.load_job(self.runtime, job_id))["deadline_at_ms"]
            outcome = AttemptOutcome("succeeded", 200, "stop", 10, 10, 20, 100)
            good = '{"action":"search","query":"q"}'
            provider = AsyncMock(
                side_effect=[
                    ResearchCompletion("not JSON", outcome),
                    ResearchCompletion(good, outcome),
                    ResearchCompletion("invalid again", outcome),
                ]
            )

            def accept(value: str) -> str:
                return json.dumps(
                    rt.parse_research_action(value).model_dump(), separators=(",", ":")
                )

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
                with self.assertRaises(rt.JobIncomplete):
                    await rt.invoke_job_model(
                        self.runtime, job_id, "research_step_2", "JSON schema", "q", accept
                    )
            self.assertEqual(provider.await_count, 3)
            saved = await rt.load_job(self.runtime, job_id)
            self.assertEqual(saved["attempts_used"], 3)
            self.assertEqual(saved["deadline_at_ms"], deadline)

        asyncio.run(run())
