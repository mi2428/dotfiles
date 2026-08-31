from __future__ import annotations

import asyncio
import logging
import time
import unittest
from collections.abc import AsyncIterator, Sequence
from types import SimpleNamespace

from strands.event_loop.streaming import process_stream
from strands.models.openai import logger as openai_model_logger
from strands.types._events import ModelStopReason
from strands.types.content import Message
from strands.types.streaming import StreamEvent

from sakura_kimi_model import SakuraKimiModel


async def _iterate_chunks(chunks: Sequence[StreamEvent]) -> AsyncIterator[StreamEvent]:
    for chunk in chunks:
        yield chunk


def _completion_message(reasoning_field: str) -> SimpleNamespace:
    tool_call = SimpleNamespace(
        id="tool-1",
        function=SimpleNamespace(name="lookup", arguments='{"topic":"preserved thinking"}'),
    )
    return SimpleNamespace(
        content="visible answer",
        tool_calls=[tool_call],
        **{reasoning_field: "internal reasoning"},
    )


async def _assistant_message_from_response(reasoning_field: str) -> Message:
    model = SakuraKimiModel(model_id="kimi-k2.7-code", stream=False)
    response = SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=_completion_message(reasoning_field),
                finish_reason="tool_calls",
            )
        ],
        usage=SimpleNamespace(prompt_tokens=1, completion_tokens=1, total_tokens=2),
    )
    stop_event: ModelStopReason | None = None
    chunks = model._format_non_streaming_response(response)
    async for event in process_stream(_iterate_chunks(chunks), time.time()):
        if isinstance(event, ModelStopReason):
            stop_event = event
    if stop_event is None:
        raise AssertionError("missing model stop event")
    return stop_event["stop"][1]


class SakuraKimiModelTests(unittest.TestCase):
    def test_reasoning_is_replayed_with_tool_call_for_both_provider_fields(self) -> None:
        async def run() -> None:
            model = SakuraKimiModel(model_id="kimi-k2.7-code")
            tool_result_message: Message = {
                "role": "user",
                "content": [
                    {
                        "toolResult": {
                            "toolUseId": "tool-1",
                            "status": "success",
                            "content": [{"text": "tool output"}],
                        }
                    }
                ],
            }

            for reasoning_field in ("reasoning_content", "reasoning"):
                with self.subTest(reasoning_field=reasoning_field):
                    assistant_message = await _assistant_message_from_response(reasoning_field)
                    with self.assertNoLogs(openai_model_logger, level=logging.WARNING):
                        formatted = model.format_request_messages(
                            [assistant_message, tool_result_message]
                        )

                    self.assertEqual(formatted[0]["role"], "assistant")
                    self.assertEqual(formatted[0]["reasoning_content"], "internal reasoning")
                    self.assertEqual(
                        formatted[0]["content"], [{"text": "visible answer", "type": "text"}]
                    )
                    self.assertEqual(formatted[0]["tool_calls"][0]["id"], "tool-1")
                    self.assertEqual(formatted[0]["tool_calls"][0]["function"]["name"], "lookup")
                    self.assertEqual(
                        formatted[1],
                        {"role": "tool", "tool_call_id": "tool-1", "content": "tool output"},
                    )

        asyncio.run(run())

    def test_redacted_reasoning_is_rejected(self) -> None:
        model = SakuraKimiModel(model_id="kimi-k2.7-code")
        with self.assertRaisesRegex(TypeError, "redacted reasoningContent"):
            model.format_request_messages(
                [
                    {
                        "role": "assistant",
                        "content": [
                            {"reasoningContent": {"redactedContent": b"secret"}},
                            {
                                "toolUse": {
                                    "toolUseId": "tool-1",
                                    "name": "lookup",
                                    "input": {"topic": "preserved thinking"},
                                }
                            },
                        ],
                    }
                ]
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
