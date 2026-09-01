"""
title: Deep Research Status
description: Shows immediate progress while Deep Research is running.
version: 1.0.0
"""


class Filter:
    """Emit transient Open WebUI status events without changing the chat payload."""

    async def inlet(self, body: dict, __event_emitter__=None) -> dict:
        if __event_emitter__:
            await __event_emitter__(
                {
                    "type": "status",
                    "data": {
                        "action": "deep_research",
                        "description": "Deep Researchを実行しています…",
                        "done": False,
                    },
                }
            )
        return body

    async def outlet(self, body: dict, __event_emitter__=None) -> dict:
        if __event_emitter__:
            await __event_emitter__(
                {
                    "type": "status",
                    "data": {
                        "action": "deep_research",
                        "description": "Deep Researchを実行しています…",
                        "done": True,
                        "hidden": True,
                    },
                }
            )
        return body
