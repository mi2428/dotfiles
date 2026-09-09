from __future__ import annotations

import asyncio
import hashlib
import json
import os
import sys
import unittest
from contextlib import asynccontextmanager
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import AsyncMock, patch

import deep_research_integration as integration

FUNCTIONS_DIR = Path(__file__).parents[1] / "functions"
sys.path.insert(0, str(FUNCTIONS_DIR))
from deep_research_pipe import ADAPTER_MAX_SECONDS, Pipe, shorten_adapter_deadline

RUNTIME_MARKDOWN = (
    "# 調査報告\n\n"
    "## 主な結果\n\n根拠 [S1]\n\n"
    "## 結論\n\n結論 [S1]\n\n"
    "## 限界\n\n公開情報の範囲です。\n\n"
    "## 情報源\n\n"
    "- [S1] [Primary source](https://example.com/source) — Publisher"
)


class HTTPException(Exception):
    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


class FakeChats:
    def __init__(self) -> None:
        self.owner = "owner-1"
        self.messages: dict[str, dict] = {}

    async def get_chat_by_id(self, chat_id: str):
        return SimpleNamespace(id=chat_id, user_id=self.owner)

    async def get_message_by_id_and_message_id(self, chat_id: str, message_id: str):
        return self.messages.get(message_id)

    async def get_messages_map_by_chat_id(self, chat_id: str):
        return self.messages

    async def is_chat_owner(self, chat_id: str, owner_id: str) -> bool:
        return owner_id == self.owner

    async def upsert_message_to_chat_by_id_and_message_id(
        self, chat_id: str, message_id: str, values: dict, **_kwargs
    ):
        if message_id not in self.messages:
            return None
        self.messages[message_id] = {**self.messages[message_id], **values}
        return SimpleNamespace(id=chat_id)


class FakeNote:
    def __init__(self, **values) -> None:
        self.__dict__.update(values)


class FakeSession:
    def __init__(self) -> None:
        self.notes: dict[str, FakeNote] = {}
        self.add_count = 0
        self.pending: FakeNote | None = None

    async def get(self, _model, note_id: str):
        return self.notes.get(note_id)

    def add(self, note: FakeNote) -> None:
        self.add_count += 1
        self.pending = note

    async def commit(self) -> None:
        if self.pending is None:
            return
        note = self.pending
        self.pending = None
        if note.id in self.notes:
            raise RuntimeError("unique constraint")
        self.notes[note.id] = note

    async def rollback(self) -> None:
        self.pending = None


def module_tree(
    chats: FakeChats, session: FakeSession | None = None
) -> dict[str, ModuleType]:
    modules = {
        name: ModuleType(name)
        for name in (
            "open_webui",
            "open_webui.config",
            "open_webui.env",
            "open_webui.internal",
            "open_webui.internal.db",
            "open_webui.models",
            "open_webui.models.access_grants",
            "open_webui.models.chats",
            "open_webui.models.functions",
            "open_webui.models.models",
            "open_webui.models.notes",
            "open_webui.utils",
            "sqlalchemy",
            "sqlalchemy.exc",
            "fastapi",
        )
    }
    modules["open_webui.env"].WEBUI_SECRET_KEY = "test-signing-key"
    modules["open_webui.models.chats"].Chats = chats
    modules["open_webui.utils.deep_research_integration"] = integration
    modules["fastapi"].HTTPException = HTTPException
    modules["sqlalchemy.exc"].IntegrityError = RuntimeError

    class Functions:
        @staticmethod
        async def get_function_by_id(_function_id):
            return {
                "id": integration.PIPE_ID,
                "type": "pipe",
                "is_active": True,
                "is_global": False,
                "meta": {"provisioned_by": integration.MARKER},
            }

    class Models:
        @staticmethod
        async def get_model_by_id(_model_id):
            return {
                "id": integration.MODEL_ID,
                "base_model_id": integration.PIPE_ID,
                "is_active": True,
                "meta": {"provisioned_by": integration.MARKER},
                "params": {},
            }

    modules["open_webui.models.functions"].Functions = Functions
    modules["open_webui.models.models"].Models = Models
    if session is not None:

        @asynccontextmanager
        async def get_async_db_context():
            yield session

        class AccessGrants:
            @staticmethod
            async def get_grants_by_resource(*_args, **_kwargs):
                return []

        modules["open_webui.internal.db"].get_async_db_context = get_async_db_context
        modules["open_webui.models.access_grants"].AccessGrants = AccessGrants
        modules["open_webui.models.notes"].Note = FakeNote
    return modules


def user_message(message_id: str = "user-1", parent_id=None) -> dict:
    return {
        "id": message_id,
        "parentId": parent_id,
        "childrenIds": [],
        "role": "user",
        "content": "2026年の公開情報を調査してください。",
        "models": [integration.MODEL_ID],
    }


def request_fixture(
    *, action_id: str = "action-1", user: dict | None = None, reattach: bool = False
) -> tuple[dict, dict, list[dict]]:
    user = user or user_message()
    form = {
        "model": integration.MODEL_ID,
        "stream": True,
        "params": {},
        "features": {"memory": False, "web_search": False},
        "variables": {},
    }
    metadata = {
        "user_id": "owner-1",
        "chat_id": "chat-1",
        "user_message": dict(user),
        "user_message_id": user["id"],
        "assistant_message_id": action_id if reattach else None,
        "session_id": "session-1",
        "automation_id": None,
        "folder_id": None,
        "filter_ids": [],
        "tool_ids": None,
        "tool_servers": [],
        "files": None,
        "features": form["features"],
        "internal": False,
    }
    return form, metadata, [{"model_id": integration.MODEL_ID, "message_id": action_id}]


def signed_binding(
    query: str,
    *,
    action_id: str = "action-1",
    job_id: str | None = None,
    state: str | None = None,
) -> dict:
    request_hash = integration.query_hash(query)
    intent = integration.action_signature(
        owner_id="owner-1",
        chat_id="chat-1",
        action_id=action_id,
        request_hash=request_hash,
        key="test-signing-key",
    )
    return {
        "marker": integration.MARKER,
        "owner_id": "owner-1",
        "chat_id": "chat-1",
        "action_id": action_id,
        "query_hash": request_hash,
        "intent_signature": intent,
        **(
            {
                "job_id": job_id,
                "job_signature": integration.job_signature(
                    intent, job_id, key="test-signing-key"
                ),
            }
            if job_id
            else {}
        ),
        **({"state": state} if state else {}),
    }


class FakePipe(Pipe):
    def __init__(
        self, session: FakeSession, *, fail_delivery_ack: bool = False
    ) -> None:
        markdown = RUNTIME_MARKDOWN
        content_hash = hashlib.sha256(markdown.encode()).hexdigest()
        self.session = session
        self.calls = []
        self.responses = [
            {"job_id": "job-1", "status": "queued"},
            {
                "job_id": "job-1",
                "status": "completed",
                "phase": "supervising",
                "deadline_at_ms": 9_999_999_999_999,
            },
            {
                "job_id": "job-1",
                "status": "completed",
                "delivery_status": "pending",
                "publication_id": "publication-1",
                "answer_markdown": markdown,
                "content_hash": content_hash,
            },
            {
                "delivery_status": "delivered",
                "delivery": {
                    "publication_id": "publication-1",
                    "content_hash": content_hash,
                    "note_id": integration.note_id_for(
                        "owner-1", "job-1", "publication-1"
                    ),
                    "delivered_at_ms": 1,
                },
            },
        ]
        if fail_delivery_ack:
            self.responses[-1] = {"delivery_status": "pending"}

    async def _runtime(self, method, path, owner_id, payload=None):
        self.calls.append((method, path, owner_id, payload, len(self.session.notes)))
        return (202 if path == "/research/jobs" else 200), self.responses.pop(0)


class TerminalPipe(Pipe):
    def __init__(self, responses) -> None:
        self.responses = list(responses)
        self.calls = []
        self.bindings = []
        self.notes = []

    async def _runtime(self, method, path, owner_id, payload=None):
        self.calls.append((method, path, payload))
        response = self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return 200, response

    async def _bind(self, **values):
        self.bindings.append(values)

    async def _note(self, **values):
        self.notes.append(values)
        return "note-1"


def trusted_metadata(query: str = "query", job_id: str | None = None) -> dict:
    binding = signed_binding(query, job_id=job_id)
    trusted = {
        **binding,
        "model_id": integration.MODEL_ID,
        "query": query,
        "reattach": job_id is not None,
        "active_task_ids": [],
        "completed": False,
        "job_id": job_id,
    }
    return {
        "user_id": "owner-1",
        "chat_id": "chat-1",
        "message_id": "action-1",
        integration.TRUST_KEY: trusted,
    }


class DeepResearchIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_runtime_http_rejects_redirects_and_bounds_json_response(
        self,
    ) -> None:
        class Content:
            def __init__(self, body: bytes) -> None:
                self.body = body

            async def read(self, size: int) -> bytes:
                chunk, self.body = self.body[:size], self.body[size:]
                return chunk

        class Response:
            def __init__(self, body: bytes, status: int = 200) -> None:
                self.content = Content(body)
                self.status = status
                self.headers = {}

            async def __aenter__(self):
                return self

            async def __aexit__(self, _type, _value, _traceback):
                return None

        response = Response(b'{"job_id":"job-1"}')

        class Session:
            request_args = None

            def __init__(self, **_kwargs) -> None:
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, _type, _value, _traceback):
                return None

            def request(self, *args, **kwargs):
                Session.request_args = (args, kwargs)
                return response

        aiohttp = ModuleType("aiohttp")
        aiohttp.ClientTimeout = SimpleNamespace
        aiohttp.ClientSession = Session
        with (
            patch.dict(sys.modules, {"aiohttp": aiohttp}),
            patch.dict(
                os.environ,
                {
                    "DEEP_RESEARCH_RUNTIME_URL": "https://runtime.invalid",
                    "DEEP_RESEARCH_RUNTIME_API_KEY": "test-api-key",
                },
            ),
        ):
            status, data = await integration.runtime_json(
                "GET", "/research/jobs/job-1", "owner-1"
            )
        self.assertEqual(status, 200)
        self.assertEqual(data["job_id"], "job-1")
        self.assertEqual(
            Session.request_args[0],
            ("GET", "https://runtime.invalid/research/jobs/job-1"),
        )
        self.assertFalse(Session.request_args[1]["allow_redirects"])

        with self.assertRaisesRegex(RuntimeError, "byte limit"):
            await integration.bounded_response_json(
                Response(b"x" * (integration.RUNTIME_RESPONSE_MAX_BYTES + 1))
            )
        with self.assertRaisesRegex(RuntimeError, "invalid JSON"):
            await integration.bounded_response_json(Response(b"{"))
        with self.assertRaisesRegex(TypeError, "invalid response"):
            await integration.bounded_response_json(Response(b"[]"))

    def test_adapter_deadline_and_retry_after_are_bounded(self) -> None:
        first = shorten_adapter_deadline(
            1_000.0, 15_000, now_ms=10_000, monotonic_now=100.0
        )
        self.assertEqual(first, 405.0)
        self.assertEqual(
            shorten_adapter_deadline(first, 40_000, now_ms=10_000, monotonic_now=101.0),
            first,
        )
        long_job = shorten_adapter_deadline(
            ADAPTER_MAX_SECONDS,
            5_400_000,
            now_ms=0,
            monotonic_now=0.0,
        )
        self.assertEqual(long_job, 5_700.0)
        self.assertGreater(long_job, 4_800.0)
        self.assertEqual(
            shorten_adapter_deadline(
                ADAPTER_MAX_SECONDS,
                10_800_000,
                now_ms=0,
                monotonic_now=0.0,
            ),
            11_100.0,
        )
        for invalid in (None, "15000", True, 0):
            with self.assertRaisesRegex(RuntimeError, "invalid deadline"):
                shorten_adapter_deadline(
                    1_000.0, invalid, now_ms=10_000, monotonic_now=100.0
                )
        self.assertEqual(integration.bounded_retry_after("999"), 10.0)
        self.assertEqual(integration.bounded_retry_after("-1"), 0.1)
        self.assertEqual(integration.bounded_retry_after("invalid"), 2.0)

    def test_model_and_hmac_provenance_fail_closed(self) -> None:
        model = {
            "id": integration.MODEL_ID,
            "base_model_id": integration.PIPE_ID,
            "is_active": True,
            "meta": {"provisioned_by": integration.MARKER},
            "params": {},
        }
        function = {
            "id": integration.PIPE_ID,
            "type": "pipe",
            "is_active": True,
            "is_global": False,
            "meta": {"provisioned_by": integration.MARKER},
        }
        registry_model = {"id": integration.MODEL_ID, "pipe": {"type": "pipe"}}
        self.assertTrue(
            integration.validate_managed_model_contract(
                integration.MODEL_ID,
                model,
                function,
                registry_model=registry_model,
                require_registry=True,
            )
        )
        with self.assertRaisesRegex(RuntimeError, "missing from the model registry"):
            integration.validate_managed_model_contract(
                integration.MODEL_ID,
                model,
                function,
                registry_model={"id": integration.MODEL_ID},
                missing_base_model=True,
                require_registry=True,
            )
        with self.assertRaisesRegex(RuntimeError, "missing from the model registry"):
            integration.validate_managed_model_contract(
                integration.MODEL_ID,
                model,
                function,
                registry_model={"id": "different", "pipe": {"type": "pipe"}},
                require_registry=True,
            )
        with self.assertRaisesRegex(RuntimeError, "not provisioned safely"):
            integration.validate_managed_model_contract(
                integration.MODEL_ID,
                model,
                function,
                registry_model=registry_model,
                require_registry=True,
                direct=True,
            )
        self.assertFalse(
            integration.validate_managed_model_contract(
                "ordinary-model",
                None,
                None,
                registry_model={"id": "ordinary-model"},
                missing_base_model=True,
                require_registry=True,
            )
        )
        forged = signed_binding("query")
        forged["intent_signature"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError, "provenance"):
            integration.validate_action_binding(
                forged,
                owner_id="owner-1",
                chat_id="chat-1",
                action_id="action-1",
                query="query",
                key="test-signing-key",
            )

    async def test_real_ui_shapes_new_long_and_regenerate_are_accepted(self) -> None:
        chats = FakeChats()
        with patch.dict(sys.modules, module_tree(chats), clear=False):
            form, metadata, ids = request_fixture(action_id="new-action")
            payload, prepared = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=True,
                active_task_ids=[],
            )
            self.assertFalse(payload["stream"])
            self.assertEqual(
                payload["messages"],
                [{"role": "user", "content": user_message()["content"]}],
            )
            self.assertEqual(
                integration.research_job_payload(
                    prepared[integration.TRUST_KEY]["query"],
                    prepared[integration.TRUST_KEY]["action_id"],
                ),
                {
                    "query": user_message()["content"],
                    "action_id": "new-action",
                    "profile": "deep",
                    "max_units": 4,
                },
            )

            # A long saved chat contributes no conversation context to the managed Pipe.
            chats.messages = {
                f"old-{index}": {
                    "id": f"old-{index}",
                    "parentId": None,
                    "childrenIds": [],
                    "role": "assistant",
                    "content": "old",
                    "done": True,
                    "model": "ordinary-model",
                }
                for index in range(100)
            }
            current = user_message("user-long", "old-99")
            chats.messages[current["id"]] = current
            form, metadata, ids = request_fixture(action_id="long-action", user=current)
            payload, prepared = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            self.assertEqual(len(payload["messages"]), 1)
            self.assertEqual(
                integration.research_job_payload(
                    prepared[integration.TRUST_KEY]["query"],
                    prepared[integration.TRUST_KEY]["action_id"],
                ),
                {
                    "query": current["content"],
                    "action_id": "long-action",
                    "profile": "deep",
                    "max_units": 4,
                },
            )

            # Regenerate is the same owned user message with a fresh assistant action ID.
            form, metadata, ids = request_fixture(
                action_id="regenerated-action", user=current
            )
            _, regenerated = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            self.assertEqual(
                regenerated[integration.TRUST_KEY]["action_id"], "regenerated-action"
            )
            self.assertFalse(regenerated[integration.TRUST_KEY]["reattach"])
            self.assertEqual(
                integration.research_job_payload(
                    regenerated[integration.TRUST_KEY]["query"],
                    regenerated[integration.TRUST_KEY]["action_id"],
                ),
                {
                    "query": current["content"],
                    "action_id": "regenerated-action",
                    "profile": "deep",
                    "max_units": 4,
                },
            )

    async def test_completed_replay_and_pre_job_binding_reattach_do_not_create_new_action(
        self,
    ) -> None:
        chats = FakeChats()
        current = user_message()
        chats.messages[current["id"]] = current
        with patch.dict(sys.modules, module_tree(chats), clear=False):
            intent = signed_binding(current["content"])
            chats.messages["action-1"] = {
                "id": "action-1",
                "parentId": current["id"],
                "childrenIds": [],
                "role": "assistant",
                "content": "",
                "done": False,
                "model": integration.MODEL_ID,
                "meta": {integration.BINDING_KEY: intent},
            }
            form, metadata, ids = request_fixture(reattach=True)
            _, reattached = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            context = reattached[integration.TRUST_KEY]
            self.assertTrue(context["reattach"])
            self.assertIsNone(context["job_id"])
            self.assertEqual(
                integration.research_job_payload(
                    context["query"], context["action_id"]
                ),
                {
                    "query": current["content"],
                    "action_id": "action-1",
                    "profile": "deep",
                    "max_units": 4,
                },
            )

            # A transport replay attaches to the already active server task without a new ID.
            form, metadata, ids = request_fixture()
            _, active = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=["task-1"],
            )
            self.assertEqual(
                active[integration.TRUST_KEY]["active_task_ids"], ["task-1"]
            )

            completed = signed_binding(
                current["content"], job_id="job-1", state="delivered"
            )
            chats.messages["action-1"].update(
                {
                    "done": True,
                    "content": "saved",
                    "meta": {integration.BINDING_KEY: completed},
                }
            )
            form, metadata, ids = request_fixture()
            _, replay = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            self.assertTrue(replay[integration.TRUST_KEY]["completed"])
            self.assertEqual(replay[integration.TRUST_KEY]["action_id"], "action-1")

    async def test_forged_pending_and_auxiliary_context_are_rejected_server_side(
        self,
    ) -> None:
        chats = FakeChats()
        current = user_message()
        chats.messages[current["id"]] = current
        chats.messages["action-1"] = {
            "id": "action-1",
            "parentId": current["id"],
            "childrenIds": [],
            "role": "assistant",
            "content": "",
            "done": False,
            "model": integration.MODEL_ID,
            "meta": {},
        }
        with patch.dict(sys.modules, module_tree(chats), clear=False):
            form, metadata, ids = request_fixture()
            with self.assertRaises(HTTPException) as caught:
                await integration.prepare_deep_research_request(
                    form_data=form,
                    metadata=metadata,
                    user_id="owner-1",
                    message_ids=ids,
                    is_new_chat=False,
                    active_task_ids=[],
                )
            self.assertEqual(caught.exception.status_code, 409)

            chats.messages.pop("action-1")
            form, metadata, ids = request_fixture(action_id="fresh-action")
            form["variables"] = {"private": "context"}
            with self.assertRaisesRegex(HTTPException, "variables"):
                await integration.prepare_deep_research_request(
                    form_data=form,
                    metadata=metadata,
                    user_id="owner-1",
                    message_ids=ids,
                    is_new_chat=False,
                    active_task_ids=[],
                )

            form, metadata, ids = request_fixture(action_id="fresh-action")
            form["params"] = {"system": "private context"}
            with self.assertRaisesRegex(HTTPException, "system prompt"):
                await integration.prepare_deep_research_request(
                    form_data=form,
                    metadata=metadata,
                    user_id="owner-1",
                    message_ids=ids,
                    is_new_chat=False,
                    active_task_ids=[],
                )

    async def test_guard_pipe_fake_runtime_and_note_delivery_positive_path(
        self,
    ) -> None:
        chats = FakeChats()
        session = FakeSession()
        current = user_message()
        chats.messages[current["id"]] = current
        modules = module_tree(chats, session)
        with patch.dict(sys.modules, modules, clear=False):
            form, metadata, ids = request_fixture()
            _, trusted = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            chats.messages["action-1"] = {
                "id": "action-1",
                "parentId": current["id"],
                "childrenIds": [],
                "role": "assistant",
                "content": "",
                "done": False,
                "model": integration.MODEL_ID,
                "meta": {},
            }
            await integration.persist_deep_research_intent(trusted)
            binding = chats.messages["action-1"]["meta"][integration.BINDING_KEY]
            json.dumps(binding)
            json.dumps(trusted[integration.TRUST_KEY])

            events = []

            async def emit(event):
                events.append(event)

            failed_delivery = FakePipe(session, fail_delivery_ack=True)
            with self.assertRaisesRegex(RuntimeError, "did not acknowledge"):
                await failed_delivery.pipe(
                    {},
                    __user__={"id": "owner-1"},
                    __chat_id__="chat-1",
                    __message_id__="action-1",
                    __metadata__=trusted,
                    __event_emitter__=emit,
                )
            expected_submission = {
                "query": current["content"],
                "action_id": "action-1",
                "profile": "deep",
                "max_units": 4,
            }
            self.assertEqual(
                failed_delivery.calls[0][:4],
                ("POST", "/research/jobs", "owner-1", expected_submission),
            )
            self.assertEqual(session.add_count, 1)
            self.assertEqual(
                chats.messages["action-1"]["meta"][integration.BINDING_KEY]["state"],
                "delivery_pending",
            )

            form, metadata, ids = request_fixture(reattach=True)
            _, retried = await integration.prepare_deep_research_request(
                form_data=form,
                metadata=metadata,
                user_id="owner-1",
                message_ids=ids,
                is_new_chat=False,
                active_task_ids=[],
            )
            events.clear()
            pipe = FakePipe(session)
            result = await pipe.pipe(
                {},
                __user__={"id": "owner-1"},
                __chat_id__="chat-1",
                __message_id__="action-1",
                __metadata__=retried,
                __event_emitter__=emit,
            )
            self.assertEqual(result, RUNTIME_MARKDOWN)
            self.assertEqual(
                pipe.calls[0][:4],
                ("POST", "/research/jobs", "owner-1", expected_submission),
            )
            self.assertEqual(len(session.notes), 1)
            self.assertEqual(pipe.calls[-1][1], "/research/jobs/job-1/delivery")
            self.assertEqual(
                pipe.calls[-1][4], 1, "Note must exist before delivery ack"
            )
            self.assertEqual(
                chats.messages["action-1"]["meta"][integration.BINDING_KEY]["state"],
                "delivered",
            )
            self.assertEqual(events[0]["data"]["phase"], "supervising")

            note = next(iter(session.notes.values()))
            self.assertGreater(note.created_at, 1_000_000_000_000_000_000)
            expected_hash = hashlib.sha256(RUNTIME_MARKDOWN.encode()).hexdigest()
            self.assertEqual(note.user_id, "owner-1")
            self.assertEqual(note.data["content"]["md"], RUNTIME_MARKDOWN)
            self.assertEqual(note.meta["deep_research_content_hash"], expected_hash)
            self.assertEqual(
                pipe.calls[-1][3],
                {
                    "publication_id": "publication-1",
                    "content_hash": expected_hash,
                    "note_id": note.id,
                },
            )
            same_id = await integration.persist_deep_research_note(
                owner_id="owner-1",
                job_id="job-1",
                publication_id="publication-1",
                content_hash=hashlib.sha256(result.encode()).hexdigest(),
                markdown=result,
                query=current["content"],
            )
            self.assertEqual(same_id, note.id)
            self.assertEqual(len(session.notes), 1)
            note.title = "edited"
            with self.assertRaisesRegex(RuntimeError, "was changed"):
                await integration.persist_deep_research_note(
                    owner_id="owner-1",
                    job_id="job-1",
                    publication_id="publication-1",
                    content_hash=hashlib.sha256(result.encode()).hexdigest(),
                    markdown=result,
                    query=current["content"],
                )

    async def test_paused_and_incomplete_without_draft_stop_safely_without_note(
        self,
    ) -> None:
        deadline = 9_999_999_999_999
        modules = module_tree(FakeChats())
        with patch.dict(sys.modules, modules, clear=False):
            paused = TerminalPipe(
                [
                    {"job_id": "job-1", "status": "queued"},
                    {
                        "job_id": "job-1",
                        "status": "running",
                        "phase": "researching",
                        "deadline_at_ms": deadline,
                        "_adapter_retry_after_seconds": 999,
                    },
                    {
                        "job_id": "job-1",
                        "status": "paused",
                        "phase": "researching",
                        "deadline_at_ms": deadline,
                    },
                ]
            )
            sleep = AsyncMock()
            with patch.object(asyncio, "sleep", sleep):
                result = await paused.pipe(
                    {},
                    __user__={"id": "owner-1"},
                    __chat_id__="chat-1",
                    __message_id__="action-1",
                    __metadata__=trusted_metadata(),
                )
            self.assertIn("**paused:**", result)
            self.assertIn("自動resumeは行いません", result)
            self.assertEqual(paused.notes, [])
            self.assertEqual(len(paused.calls), 3)
            sleep.assert_awaited_once_with(10.0)

            incomplete = TerminalPipe(
                [
                    {"job_id": "job-1", "status": "queued"},
                    {
                        "job_id": "job-1",
                        "status": "incomplete",
                        "phase": "supervising",
                        "deadline_at_ms": deadline,
                    },
                    {
                        "job_id": "job-1",
                        "status": "incomplete",
                        "delivery_status": "needs_review",
                    },
                ]
            )
            result = await incomplete.pipe(
                {},
                __user__={"id": "owner-1"},
                __chat_id__="chat-1",
                __message_id__="action-1",
                __metadata__=trusted_metadata(),
            )
            self.assertIn("レビュー可能な稿もありません", result)
            self.assertEqual(incomplete.notes, [])

    async def test_invalid_hash_raw_error_and_observer_cancellation_do_not_leak_or_cancel(
        self,
    ) -> None:
        modules = module_tree(FakeChats())
        deadline = 9_999_999_999_999
        with patch.dict(sys.modules, modules, clear=False):
            failed = TerminalPipe(
                [
                    {"job_id": "job-1", "status": "queued"},
                    {
                        "job_id": "job-1",
                        "status": "failed",
                        "phase": "researching",
                        "deadline_at_ms": deadline,
                    },
                    {
                        "job_id": "job-1",
                        "status": "failed",
                        "error_code": "provider-sensitive-detail",
                    },
                ]
            )
            with self.assertRaises(RuntimeError) as caught:
                await failed.pipe(
                    {},
                    __user__={"id": "owner-1"},
                    __chat_id__="chat-1",
                    __message_id__="action-1",
                    __metadata__=trusted_metadata(),
                )
            self.assertNotIn("provider-sensitive-detail", str(caught.exception))
            self.assertTrue(failed.bindings[-1]["done"])
            with self.assertRaisesRegex(RuntimeError, "invalid content hash"):
                Pipe._markdown(
                    {"answer_markdown": "draft", "content_hash": "not-a-hash"}
                )

            disconnected = TerminalPipe([asyncio.CancelledError()])
            with self.assertRaises(asyncio.CancelledError):
                await disconnected.pipe(
                    {},
                    __user__={"id": "owner-1"},
                    __chat_id__="chat-1",
                    __message_id__="action-1",
                    __metadata__=trusted_metadata(),
                )
            self.assertEqual(len(disconnected.calls), 1)
            self.assertFalse(
                any(path.endswith("/cancel") for _, path, _ in disconnected.calls)
            )

    async def test_stop_cancels_signed_pre_job_intent_without_submitting(self) -> None:
        chats = FakeChats()
        current = user_message()
        chats.messages[current["id"]] = current
        chats.messages["action-1"] = {
            "id": "action-1",
            "parentId": current["id"],
            "childrenIds": [],
            "role": "assistant",
            "content": "",
            "done": False,
            "model": integration.MODEL_ID,
            "meta": {integration.BINDING_KEY: signed_binding(current["content"])},
        }
        runtime = AsyncMock(
            return_value=(
                200,
                {"action_id": "action-1", "job_id": None, "status": "cancelled"},
            )
        )
        with (
            patch.dict(sys.modules, module_tree(chats), clear=False),
            patch.object(integration, "runtime_json", runtime),
        ):
            stopped = await integration.request_deep_research_stop("chat-1", "owner-1")
        self.assertEqual(stopped, ["action-1"])
        runtime.assert_awaited_once_with(
            "POST",
            "/research/actions/action-1/cancel",
            "owner-1",
            {
                "query": current["content"],
                "action_id": "action-1",
                "profile": "deep",
                "max_units": 4,
            },
        )
        self.assertFalse(
            any(call.args[1] == "/research/jobs" for call in runtime.await_args_list)
        )
        self.assertEqual(
            chats.messages["action-1"]["meta"][integration.BINDING_KEY]["state"],
            "cancel_requested",
        )
        self.assertTrue(chats.messages["action-1"]["done"])

    async def test_stop_cancels_only_the_signed_bound_job(self) -> None:
        chats = FakeChats()
        current = user_message()
        chats.messages[current["id"]] = current
        chats.messages["action-1"] = {
            "id": "action-1",
            "parentId": current["id"],
            "childrenIds": [],
            "role": "assistant",
            "content": "",
            "done": False,
            "model": integration.MODEL_ID,
            "meta": {
                integration.BINDING_KEY: signed_binding(
                    current["content"], job_id="job-1", state="running"
                )
            },
        }
        runtime = AsyncMock(
            return_value=(
                200,
                {"job_id": "job-1", "status": "running", "cancel_requested": True},
            )
        )
        with (
            patch.dict(sys.modules, module_tree(chats), clear=False),
            patch.object(integration, "runtime_json", runtime),
        ):
            stopped = await integration.request_deep_research_stop("chat-1", "owner-1")
        self.assertEqual(stopped, ["action-1"])
        runtime.assert_awaited_once_with(
            "POST", "/research/jobs/job-1/cancel", "owner-1"
        )
        self.assertTrue(chats.messages["action-1"]["done"])

    async def test_reserved_model_failure_prevents_fallback_and_ordinary_stop_is_unchanged(
        self,
    ) -> None:
        chats = FakeChats()
        modules = module_tree(chats)
        model = {
            "id": integration.MODEL_ID,
            "base_model_id": integration.PIPE_ID,
            "is_active": True,
            "meta": {"provisioned_by": integration.MARKER},
            "params": {},
        }
        fallback = AsyncMock()
        with patch.dict(sys.modules, modules, clear=False):

            async def guarded_dispatch():
                await integration.is_managed_deep_research_model(
                    integration.MODEL_ID,
                    model,
                    registry_model={"id": integration.MODEL_ID},
                    missing_base_model=True,
                    require_registry=True,
                )
                await fallback()

            with self.assertRaises(HTTPException) as caught:
                await guarded_dispatch()
            self.assertEqual(caught.exception.status_code, 503)
            fallback.assert_not_awaited()

            chats.messages["ordinary"] = {
                "id": "ordinary",
                "role": "assistant",
                "model": "ordinary-model",
                "done": False,
            }
            self.assertEqual(
                await integration.request_deep_research_stop(
                    "chat-1", "admin-not-owner"
                ),
                [],
            )


if __name__ == "__main__":
    unittest.main()
