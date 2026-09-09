from __future__ import annotations

import base64
import copy
import json
import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECONCILE = ROOT / "scripts" / "reconcile.sh"
OWNER = "admin-id"
MARKER = "dotfiles:kimi-k2.7-deep-research"

FAKE_CURL = r"""#!/usr/bin/env python3
import json
import os
import sys
from urllib.parse import unquote, urlsplit

state_path = os.environ["FAKE_API_STATE"]
log_path = os.environ["FAKE_API_MUTATIONS"]
state = json.loads(open(state_path, encoding="utf-8").read())
args = sys.argv[1:]
method = "GET"
payload = None
write_status = "--write-out" in args
for index, value in enumerate(args):
    if value == "--request":
        method = args[index + 1]
    elif value == "--data-binary":
        payload = args[index + 1]
if payload == "@-":
    payload = sys.stdin.read()
url = next(value for value in reversed(args) if value.startswith(("http://", "https://")))
parts = urlsplit(url)
path = unquote(parts.path)
query = parts.query

def save():
    with open(state_path, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False)

def mutate():
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(f"{method} {path}\n")

def model_registry():
    functions = {item["id"]: item for item in state["functions"]}
    rows = []
    for model in state["models"]:
        row = {
            "id": model["id"],
            "name": model["name"],
            "info": {
                "base_model_id": model.get("base_model_id"),
                "meta": model.get("meta", {}),
            },
        }
        pipe = functions.get(model.get("base_model_id"))
        if pipe and pipe.get("type") == "pipe" and pipe.get("is_active"):
            row["pipe"] = {"type": "pipe"}
        rows.append(row)
    return {"data": rows}

status = 200
body = None
if path == "/api/v1/auths/signin":
    body = state["profile"] | {"id": state["owner"], "token": "fake-token"}
elif path == "/api/v1/configs/tool_servers":
    if method == "GET":
        body = state["tool_servers"]
    else:
        mutate()
        state["tool_servers"] = json.loads(payload)
        save()
        body = state["tool_servers"]
elif path == "/api/v1/functions/export":
    body = state["functions"]
elif path == "/api/v1/functions/create":
    mutate()
    item = json.loads(payload)
    item |= {"user_id": state["owner"], "type": "pipe", "is_active": False, "is_global": False}
    item["meta"] = item.get("meta", {}) | {"manifest": {}}
    state["functions"].append(item)
    save()
    body = item
elif path.startswith("/api/v1/functions/id/"):
    suffix = path.removeprefix("/api/v1/functions/id/")
    function_id = suffix.split("/")[0]
    matches = [item for item in state["functions"] if item["id"] == function_id]
    if not matches:
        status, body = 401, {"detail": "not found"}
    elif method == "GET":
        body = matches[0]
    elif suffix.endswith("/update"):
        mutate()
        updated = json.loads(payload)
        matches[0].update(updated)
        matches[0]["meta"] = updated.get("meta", {}) | {"manifest": {}}
        save()
        body = matches[0]
    elif suffix.endswith("/toggle/global"):
        mutate()
        matches[0]["is_global"] = not matches[0]["is_global"]
        save()
        body = matches[0]
    elif suffix.endswith("/toggle"):
        mutate()
        matches[0]["is_active"] = not matches[0]["is_active"]
        save()
        body = matches[0]
    elif suffix.endswith("/delete"):
        mutate()
        state["functions"].remove(matches[0])
        save()
        body = True
elif path == "/api/v1/models/export":
    body = state["models"]
elif path == "/api/v1/models/base":
    body = state["models"]
elif path == "/api/v1/models/model" and method == "GET":
    model_id = query.removeprefix("id=")
    matches = [item for item in state["models"] if item["id"] == model_id]
    status, body = (200, matches[0]) if matches else (404, {"detail": "not found"})
elif path in {"/api/v1/models/create", "/api/v1/models/model/update"}:
    mutate()
    item = json.loads(payload) | {"user_id": state["owner"]}
    state["models"] = [row for row in state["models"] if row["id"] != item["id"]] + [item]
    save()
    body = item
elif path == "/api/v1/models/import":
    mutate()
    for item in json.loads(payload)["models"]:
        item |= {"user_id": state["owner"]}
        state["models"] = [row for row in state["models"] if row["id"] != item["id"]] + [item]
    save()
    body = True
elif path == "/api/models":
    body = model_registry()
elif path == "/api/v1/configs/models":
    if method == "GET":
        body = state["model_config"]
    else:
        mutate()
        state["model_config"] = json.loads(payload)
        save()
        body = state["model_config"]
elif path == "/api/v1/skills/export":
    body = state["skills"]
elif path.startswith("/api/v1/skills/id/") and path.endswith("/delete"):
    mutate()
    skill_id = path.removeprefix("/api/v1/skills/id/").removesuffix("/delete")
    state["skills"] = [item for item in state["skills"] if item["id"] != skill_id]
    save()
    body = True
elif path in {"/api/v1/users/user/settings", "/api/v1/users/user/settings"}:
    body = state["settings"]
elif path == "/api/v1/users/user/settings/update":
    mutate()
    state["settings"] = json.loads(payload)
    save()
    body = state["settings"]
elif path == "/api/v1/folders/":
    body = [{"id": item["id"], "name": item["name"], "parent_id": item.get("parent_id")} for item in state["folders"]]
elif path.startswith("/api/v1/folders/"):
    folder_id = path.removeprefix("/api/v1/folders/").split("/")[0]
    body = next(item for item in state["folders"] if item["id"] == folder_id)
elif path == "/api/v1/auths/update/profile":
    mutate()
    state["profile"] = json.loads(payload)
    save()
    body = state["profile"]
else:
    status, body = 500, {"detail": f"unsupported fake endpoint: {method} {path}"}

rendered = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
sys.stdout.write(rendered + (f"\n{status}" if write_status else ""))
"""


def visible_order(models: list[dict]) -> list[str]:
    visible = [item for item in models if not item.get("meta", {}).get("hidden", False)]

    def key(item: dict) -> tuple[str, int, str]:
        name = item["name"]
        base = re.sub(r" (Low|Medium|High|Max)$", "", name).lower()
        suffix = next((value for value in ("Low", "Medium", "High", "Max") if name.endswith(f" {value}")), None)
        rank = {None: -1, "Low": 0, "Medium": 1, "High": 2, "Max": 3}[suffix]
        return base, rank, item["id"]

    return [item["id"] for item in sorted(visible, key=key)]


class ReconcileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        result = subprocess.run(
            ["bash", str(RECONCILE), str(ROOT), "--dry-run"],
            check=True,
            capture_output=True,
            text=True,
            env={"PATH": os.environ["PATH"]},
        )
        cls.desired = json.loads(result.stdout)

    def test_dry_run_needs_no_secrets_and_makes_no_api_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake_bin = Path(directory)
            curl = fake_bin / "curl"
            curl.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
            curl.chmod(0o755)
            env = {"PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}"}
            result = subprocess.run(
                ["bash", str(RECONCILE), str(ROOT), "--dry-run"],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            desired = json.loads(result.stdout)
            self.assertEqual(desired["pipe"]["id"], "deep_research_pipe")
            self.assertEqual(desired["model"]["base_model_id"], "deep_research_pipe")
            self.assertEqual(desired["model"]["params"], {})
            self.assertEqual(desired["model"]["meta"]["toolIds"], [])
            self.assertEqual(desired["model"]["meta"]["filterIds"], [])
            self.assertNotIn("skill", desired)
            self.assertNotIn("status_filter", desired)

    def state(self) -> dict:
        desired = self.desired
        regular_models = copy.deepcopy(desired["model_import"]["models"])
        for regular_model in regular_models:
            regular_model["meta"].update(
                {"capabilities": None, "description": None, "knowledge": None}
            )
        model = copy.deepcopy(desired["model"])
        model["base_model_id"] = "sacloud.preview/Kimi-K2.6"
        model["meta"]["filterIds"] = ["deep_research_status"]
        model["meta"]["toolIds"] = ["server:deep-research"]
        model["params"] = {"function_calling": "native"}
        models = [item | {"user_id": OWNER} for item in regular_models] + [model | {"user_id": OWNER}]
        icon = "data:image/webp;base64," + base64.b64encode((ROOT / "assets/profile.webp").read_bytes()).decode()
        folders = []
        for index, key in enumerate(("folder", "translation_folder", "movie_akinator_folder", "books_movies_subculture_folder")):
            folders.append(copy.deepcopy(desired[key]) | {"id": f"folder-{index}", "user_id": OWNER})
        return {
            "owner": OWNER,
            "functions": [
                {
                    "id": "deep_research_status",
                    "name": "Deep Research Status",
                    "content": "legacy",
                    "meta": {"provisioned_by": MARKER},
                    "type": "filter",
                    "user_id": OWNER,
                    "is_active": True,
                    "is_global": False,
                }
            ],
            "models": models,
            "skills": [
                {
                    "id": "deep-research",
                    "user_id": OWNER,
                    "meta": {"tags": [MARKER]},
                }
            ],
            "tool_servers": {
                "TOOL_SERVER_CONNECTIONS": [
                    {"info": {"id": "other"}},
                    {
                        "info": {"id": "deep-research", "provisioned_by": "dotfiles:deep-research-runtime"},
                        "config": {"access_grants": [{"principal_type": "user", "principal_id": OWNER, "permission": "read"}]},
                    },
                ]
            },
            "settings": {
                "ui": {**desired["user_settings"]["ui"], "widescreenMode": True}
            },
            "folders": folders,
            "model_config": {"MODEL_ORDER_LIST": visible_order(models)},
            "profile": {
                "name": "admin",
                "profile_image_url": icon,
                "bio": None,
                "gender": None,
                "date_of_birth": None,
            },
        }

    def run_reconcile(self, state: dict, temp: Path) -> subprocess.CompletedProcess[str]:
        state_path = temp / "state.json"
        mutations = temp / "mutations"
        fake_bin = temp / "bin"
        fake_bin.mkdir(exist_ok=True)
        fake_curl = fake_bin / "curl"
        fake_curl.write_text(textwrap.dedent(FAKE_CURL), encoding="utf-8")
        fake_curl.chmod(0o755)
        state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
        mutations.write_text("", encoding="utf-8")
        env = {
            "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            "FAKE_API_STATE": str(state_path),
            "FAKE_API_MUTATIONS": str(mutations),
            "WEBUI_ADMIN_USERNAME": "admin",
            "WEBUI_ADMIN_EMAIL": "admin@example.invalid",
            "WEBUI_ADMIN_PASSWORD": "not-a-secret",
        }
        result = subprocess.run(
            ["bash", str(RECONCILE), str(ROOT)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        result.mutations = mutations.read_text(encoding="utf-8").splitlines()  # type: ignore[attr-defined]
        result.state_path = state_path  # type: ignore[attr-defined]
        return result

    def test_migration_order_and_second_run_has_no_mutations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            first = self.run_reconcile(self.state(), temp)
            self.assertEqual(first.returncode, 0, first.stderr)
            expected = [
                "POST /api/v1/functions/create",
                "POST /api/v1/models/model/update",
                "POST /api/v1/configs/tool_servers",
                "DELETE /api/v1/functions/id/deep_research_status/delete",
                "DELETE /api/v1/skills/id/deep-research/delete",
            ]
            positions = [first.mutations.index(value) for value in expected]  # type: ignore[attr-defined]
            self.assertEqual(positions, sorted(positions))
            migrated = json.loads(first.state_path.read_text(encoding="utf-8"))  # type: ignore[attr-defined]
            self.assertEqual(
                migrated["tool_servers"]["TOOL_SERVER_CONNECTIONS"],
                [{"info": {"id": "other"}}],
            )
            self.assertNotIn("deep_research_status", {item["id"] for item in migrated["functions"]})
            self.assertEqual(migrated["skills"], [])
            self.assertEqual(len(migrated["folders"]), 4)
            second = self.run_reconcile(migrated, temp)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.mutations, [])  # type: ignore[attr-defined]

    def test_every_known_collision_fails_before_mutation(self) -> None:
        cases = {}
        pipe = self.state()
        pipe["functions"].append({
            "id": "deep_research_pipe", "name": "collision", "content": "x", "meta": {},
            "type": "pipe", "user_id": "other", "is_active": True, "is_global": False,
        })
        cases["pipe"] = pipe
        model = self.state()
        next(item for item in model["models"] if item["id"] == "sacloud.kimi-k2.7-deep-research")["user_id"] = "other"
        cases["model"] = model
        tool = self.state()
        tool["tool_servers"]["TOOL_SERVER_CONNECTIONS"][1]["info"]["provisioned_by"] = "other"
        cases["tool"] = tool
        legacy_filter = self.state()
        legacy_filter["functions"][0]["user_id"] = "other"
        cases["filter"] = legacy_filter
        skill = self.state()
        skill["skills"][0]["user_id"] = "other"
        cases["skill"] = skill
        duplicate = self.state()
        managed_pipe = copy.deepcopy(self.desired["pipe"]) | {
            "type": "pipe", "user_id": OWNER, "is_active": True, "is_global": False,
        }
        duplicate["functions"].extend([managed_pipe, copy.deepcopy(managed_pipe)])
        cases["duplicate"] = duplicate

        for name, state in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                result = self.run_reconcile(state, Path(directory))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.mutations, [])  # type: ignore[attr-defined]


if __name__ == "__main__":
    unittest.main()
