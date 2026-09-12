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

def save():
    with open(state_path, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False)

def mutate():
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(f"{method} {path}\n")

def model_registry():
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
        rows.append(row)
    return {"data": rows}

status = 200
body = None
if path == "/api/v1/auths/signin":
    body = state["profile"] | {"id": state["owner"], "token": "fake-token"}
elif path == "/api/v1/models/export":
    body = state["models"]
elif path == "/api/v1/models/base":
    body = state["models"]
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
            self.assertNotIn("pipe", desired)
            self.assertNotIn("model", desired)

    def state(self) -> dict:
        desired = self.desired
        regular_models = copy.deepcopy(desired["model_import"]["models"])
        for regular_model in regular_models:
            regular_model["meta"].update(
                {"capabilities": None, "description": None, "knowledge": None}
            )
        models = [item | {"user_id": OWNER} for item in regular_models]
        icon = "data:image/webp;base64," + base64.b64encode(
            (ROOT / "assets/profile.webp").read_bytes()
        ).decode()
        folders = []
        for index, key in enumerate(("folder", "translation_folder", "movie_akinator_folder", "books_movies_subculture_folder")):
            folders.append(copy.deepcopy(desired[key]) | {"id": f"folder-{index}", "user_id": OWNER})
        return {
            "owner": OWNER,
            "models": models,
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

    def test_repairs_stale_models_and_second_run_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            first = self.run_reconcile(self.state(), temp)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(  # type: ignore[attr-defined]
                first.mutations, ["POST /api/v1/models/import"]
            )
            second = self.run_reconcile(
                json.loads(first.state_path.read_text(encoding="utf-8")), temp
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.mutations, [])  # type: ignore[attr-defined]


if __name__ == "__main__":
    unittest.main()
