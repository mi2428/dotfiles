"""Adapter for Kimi K2.7 preserved thinking on top of Strands' OpenAIModel.

Kimi K2.7 Code keeps preserved thinking enabled for tool loops, so each assistant
tool-call message must carry its original ``reasoning_content`` back into the next
Chat Completions request. Strands 1.54 intentionally drops ``reasoningContent`` when
formatting follow-up requests for the stock Chat Completions API because most
OpenAI-compatible providers do not accept it. Sakura's OpenAI-compatible Kimi proxy
does require that replay, so this subclass restores only that one field while
leaving Strands' normal text, tool call, and tool result formatting unchanged.
"""

from __future__ import annotations

from typing import Any

from strands.models.openai import OpenAIModel
from strands.types.content import Message, Messages


def _preserved_reasoning_content(message: Message) -> str | None:
    if message["role"] != "assistant":
        return None

    reasoning_parts: list[str] = []
    for content in message["content"]:
        reasoning_content = content.get("reasoningContent")
        if reasoning_content is None:
            continue
        if reasoning_content.get("redactedContent") is not None:
            raise TypeError("redacted reasoningContent cannot be replayed to Kimi")
        reasoning_text = reasoning_content.get("reasoningText")
        if not isinstance(reasoning_text, dict):
            raise TypeError("assistant reasoningContent must include reasoningText")
        text = reasoning_text.get("text")
        if not isinstance(text, str) or not text:
            raise TypeError("assistant reasoningContent.reasoningText.text must be a string")
        reasoning_parts.append(text)

    return "".join(reasoning_parts) or None


def _message_without_reasoning_content(message: Message) -> Message:
    return {
        **message,
        "content": [
            content for content in message["content"] if "reasoningContent" not in content
        ],
    }


class SakuraKimiModel(OpenAIModel):
    @classmethod
    def _format_regular_messages(cls, messages: Messages, **kwargs: Any) -> list[dict[str, Any]]:
        formatted_messages: list[dict[str, Any]] = []

        for message in messages:
            reasoning_content = _preserved_reasoning_content(message)
            formatted_batch = super()._format_regular_messages(
                [_message_without_reasoning_content(message)], **kwargs
            )
            if reasoning_content is not None:
                if not formatted_batch:
                    raise TypeError("assistant reasoningContent produced no formatted message")
                first_message = formatted_batch[0]
                if first_message.get("role") != "assistant":
                    raise TypeError(
                        "assistant reasoningContent must map to an assistant request message"
                    )
                first_message["reasoning_content"] = reasoning_content
            formatted_messages.extend(formatted_batch)

        return formatted_messages
