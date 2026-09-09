from __future__ import annotations

import asyncio
import hashlib
import json
from typing import Any, Literal
from unittest.mock import AsyncMock, patch

import httpx
from pydantic import ValidationError

from sakura_kimi_model import AttemptOutcome, ResearchCompletion
from test_support import RuntimeTestCase, rt


def completion(
    content: str,
    state: Literal["not_sent", "succeeded", "known_failed", "unknown"] = "succeeded",
) -> ResearchCompletion:
    return ResearchCompletion(
        content if state == "succeeded" else "",
        AttemptOutcome(state, 200 if state != "unknown" else None, "stop", 10, 10, 20, 100),
    )


def request(action_id: str = "action-1", **changes: Any) -> rt.ResearchJobRequest:
    return rt.ResearchJobRequest(
        **{"action_id": action_id, "query": "Need a source-grounded answer", **changes}
    )


def plan_json(*, language: str = "en") -> str:
    return json.dumps(
        {
            "requested_language": language,
            "time_horizon": "current public evidence",
            "exclusions": [],
            "checklist": [
                {
                    "id": "C1",
                    "question": "What does the public evidence establish?",
                    "essential": True,
                    "preferred_source_types": ["primary documentation"],
                    "fragment_ids": ["F1"],
                }
            ],
            "initial_queries": [
                {
                    "query": f"primary evidence query {index}",
                    "purpose": "establish the requested finding",
                    "checklist_ids": ["C1"],
                }
                for index in range(1, 4)
            ],
        },
        separators=(",", ":"),
    )


def selection_json(*result_ids: str) -> str:
    return json.dumps(
        {
            "documents": [
                {
                    "result_id": result_id,
                    "purpose": "establish the requested finding",
                    "checklist_ids": ["C1"],
                }
                for result_id in result_ids
            ]
        },
        separators=(",", ":"),
    )


def assessment_json(
    *passage_ids: str,
    status: str = "covered",
    limitation: str | None = None,
    follow_ups: list[dict[str, Any]] | None = None,
    stop_reason: str | None = "Essential evidence is adequate.",
) -> str:
    return json.dumps(
        {
            "items": [
                {
                    "checklist_id": "C1",
                    "status": status,
                    "passage_ids": list(passage_ids),
                    "origin": "primary source",
                    "authority": "official documentation",
                    "limitation": limitation,
                }
            ],
            "follow_up_queries": follow_ups or [],
            "stop_reason": stop_reason,
        },
        separators=(",", ":"),
    )


def ledger_json(*passage_ids: str, language: str = "en") -> str:
    title = "Evidence-based answer" if language == "en" else "根拠に基づく回答"
    return json.dumps(
        {
            "title": title,
            "entries": [
                {
                    "id": "K-FACT",
                    "statement": "The finding must retain its evidence conditions.",
                    "metric": "finding",
                    "unit": "text",
                    "comparator": "source",
                    "direction": "match",
                    "mode_stage": "report",
                    "condition": "public evidence",
                    "kind": "source_fact",
                    "reference_ids": [passage_ids[0]],
                    "conflict_status": "none",
                }
            ],
            "outline": [
                {
                    "unit": unit,
                    "heading": f"Unit {unit}" if language == "en" else f"分析{unit}",
                    "purpose": "Answer and analyze" if unit == 1 else "Synthesize implications",
                    "checklist_ids": ["C1"],
                    "ledger_ids": ["K-FACT"],
                    "passage_ids": list(passage_ids),
                    "limitations_analysis": False,
                    "context_units": [1] if unit == 2 else [],
                    "handoff": "Carry the supported finding forward.",
                }
                for unit in (1, 2)
            ],
        },
        separators=(",", ":"),
    )


def unit_markdown(unit: int, passage_id: str, *, language: str = "en", label: str = "") -> str:
    heading = f"Unit {unit}" if language == "en" else f"分析{unit}"
    topics = (
        "scope",
        "definitions",
        "source authority",
        "time horizon",
        "direct evidence",
        "counterevidence",
        "comparison basis",
        "assumptions",
        "practical effects",
        "uncertainty",
        "decision relevance",
        "conclusion",
    )
    body = " ".join(
        f"{label} The {topic} analysis applies the admitted evidence to the requested finding "
        "under its stated conditions and distinguishes direct support from decision implications."
        for topic in topics
    )
    return f"## {heading}\n\n{body} [{passage_id}]"


def clean_review_json() -> str:
    return '{"patches":[],"notes":[],"unsupported":[],"regenerate_reason":null}'


def research_outputs(*, limitation: str | None = None) -> list[ResearchCompletion]:
    passage_id = "S1:P0-80"
    return [
        completion(plan_json()),
        completion(selection_json("W1-1")),
        completion(assessment_json(passage_id, limitation=limitation)),
    ]


def default_outputs(*, limitation: str | None = None, label: str = "") -> list[ResearchCompletion]:
    passage_id = "S1:P0-80"
    return [
        *research_outputs(limitation=limitation),
        completion(ledger_json(passage_id)),
        completion(unit_markdown(1, passage_id, label=label)),
        completion(unit_markdown(2, passage_id, label=label)),
        completion(clean_review_json()),
    ]


class FakeProvider:
    def __init__(self, outputs: list[ResearchCompletion]) -> None:
        self.outputs = list(outputs)
        self.bodies: list[bytes] = []
        self.leases: list[Any] = []

    async def __call__(
        self, _base_url: str, _api_key: str, body: bytes, lease: Any
    ) -> ResearchCompletion:
        self.bodies.append(body)
        self.leases.append(lease)
        if not self.outputs:
            raise AssertionError("unexpected provider call")
        return self.outputs.pop(0)


class ResearchJobTests(RuntimeTestCase):
    def patches(
        self,
        provider: FakeProvider,
        *,
        results: list[rt.SearchResult] | None = None,
    ) -> tuple[Any, ...]:
        source_text = ("Evidence supports the measured finding and its condition. " * 5)[:80]
        search_results = results or [
            rt.SearchResult("https://example.com/source", "Primary Source", "Evidence", "engine")
        ]
        return (
            patch.object(rt, "complete_research", new=provider),
            patch.object(rt, "search_searxng", new=AsyncMock(return_value=search_results)),
            patch.object(
                rt,
                "fetch_source_blob",
                new=AsyncMock(
                    return_value=rt.FetchedSourceBlob(
                        search_results[0].url,
                        search_results[0].url,
                        "Primary Source",
                        "Publisher",
                        "text/html",
                        b"complete raw source",
                    )
                ),
            ),
            patch.object(
                rt,
                "extract_source_blob",
                new=AsyncMock(
                    return_value=rt.ExtractedSource(
                        source_text,
                        [{"page": 1, "start": 0, "end": len(source_text)}],
                        [],
                    )
                ),
            ),
        )

    async def run_path(
        self,
        outputs: list[ResearchCompletion],
        job_request: rt.ResearchJobRequest | None = None,
    ) -> tuple[str, FakeProvider]:
        submitted = await rt.submit_research_job(self.runtime, "owner-1", job_request or request())
        provider = FakeProvider(outputs)
        contexts = self.patches(provider)
        with contexts[0], contexts[1], contexts[2], contexts[3]:
            await rt.execute_research_job(self.runtime, submitted["job_id"])
        return str(submitted["job_id"]), provider

    def test_dedicated_request_schema_requires_deep_and_max_units_four(self) -> None:
        value = request()
        self.assertEqual((value.depth, value.profile, value.max_units), ("deep", "deep", 4))
        for change in (
            {"depth": "quick"},
            {"profile": "single_unit"},
            {"max_units": 1},
            {"units": 1},
        ):
            with self.subTest(change=change), self.assertRaises(ValidationError):
                rt.ResearchJobRequest.model_validate({"action_id": "a", "query": "q", **change})

    def test_authenticated_attach_and_read_do_not_dispatch(self) -> None:
        async def run() -> None:
            transport = httpx.ASGITransport(app=rt.app)
            headers = {
                "Authorization": "Bearer test-api-key",
                "X-Research-Owner": "owner-1",
            }
            body = request().model_dump()
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                first = await client.post("/research/jobs", headers=headers, json=body)
                attached = await client.post("/research/jobs", headers=headers, json=body)
                self.assertEqual(first.json()["job_id"], attached.json()["job_id"])
                changed = await client.post(
                    "/research/jobs", headers=headers, json={**body, "query": "changed"}
                )
                self.assertEqual(changed.status_code, 409)
                with patch.object(
                    rt,
                    "complete_research",
                    new=AsyncMock(side_effect=AssertionError("read dispatched")),
                ):
                    status_response = await client.get(first.json()["status_url"], headers=headers)
                    result_response = await client.get(first.json()["result_url"], headers=headers)
                self.assertEqual(
                    (status_response.status_code, result_response.status_code), (200, 202)
                )

        asyncio.run(run())

    def test_full_path_persists_plan_assessment_two_units_and_runtime_publication(self) -> None:
        async def run() -> None:
            job_id, provider = await self.run_path(default_outputs())
            code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (code, result["status"], result["quality_outcome"]),
                (200, "completed", "publish"),
            )
            self.assertTrue(result["answer_markdown"].startswith("# Evidence-based answer\n\n"))
            self.assertEqual(result["answer_markdown"].count("\n## Unit "), 2)
            self.assertIn("\n\n## Limitations\n- None", result["answer_markdown"])
            self.assertRegex(
                result["answer_markdown"],
                r"## Sources\n- \[S1\] \[Primary Source\]\(https://example.com/source\)",
            )
            self.assertEqual(
                result["content_hash"],
                hashlib.sha256(result["answer_markdown"].encode()).hexdigest(),
            )
            state = await rt.load_research_state(self.runtime, job_id)
            self.assertEqual(len(state["research_rounds"]), 1)
            self.assertEqual(len(state["searched_queries"]), 3)
            self.assertEqual(state["assessment"]["items"][0]["status"], "covered")
            self.assertEqual(len(provider.bodies), 7)

        asyncio.run(run())

    def test_limitation_alone_does_not_select_publish_with_caveats(self) -> None:
        async def run() -> None:
            job_id, _provider = await self.run_path(
                default_outputs(limitation="A benign extraction limitation remains.")
            )
            _code, result = await rt.research_job_result(self.runtime, "owner-1", job_id)
            self.assertEqual(result["quality_outcome"], "publish")
            self.assertIn("A benign extraction limitation remains.", result["answer_markdown"])

        asyncio.run(run())

    def test_unknown_attempt_is_not_replayed(self) -> None:
        async def run() -> None:
            job_id, provider = await self.run_path([completion("", "unknown")])
            status = await rt.research_job_status(self.runtime, "owner-1", job_id)
            self.assertEqual(
                (status["status"], status["blocked_reason"]),
                ("paused", "unknown_attempt"),
            )
            with self.assertRaises(rt.HTTPException):
                await rt.resume_research_job(self.runtime, "owner-1", job_id, status["revision"])
            self.assertEqual(len(provider.bodies), 1)

        asyncio.run(run())


if __name__ == "__main__":
    import unittest

    unittest.main(verbosity=2)
