"""Initialize persistent local service credentials without exposing their values."""

from __future__ import annotations

import os
import re
import secrets
import shlex
import tempfile
from pathlib import Path

KEYS = (
    "DEEP_RESEARCH_RUNTIME_API_KEY",
    "DEEP_RESEARCH_OPERATOR_API_KEY",
    "SAKURA_RESEARCH_API_KEY",
)
FIELDS = (*KEYS, "DEEP_RESEARCH_OPERATOR_ID", "SAKURA_AI_ACCOUNT_IDS")
IDENTIFIER = re.compile(r"[A-Za-z0-9._:@-]{1,200}")


def initialize(path: Path, environment: dict[str, str]) -> None:
    if path.is_symlink():
        raise ValueError("managed environment must not be a symlink")
    values: dict[str, str] = {}
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                parts = shlex.split(line, comments=True)
            except ValueError:
                raise ValueError("invalid managed environment syntax") from None
            if not parts:
                continue
            if parts[0] == "export":
                parts = parts[1:]
            if len(parts) != 1 or "=" not in parts[0]:
                raise ValueError("invalid managed environment assignment")
            name, value = parts[0].split("=", 1)
            if name not in FIELDS or name in values or not value:
                raise ValueError("invalid managed environment field")
            values[name] = value

    tokens = [
        part.strip()
        for part in environment.get("SAKURA_AI_ACCOUNT_TOKENS", "").split(",")
        if part.strip()
    ]
    if not tokens or len(set(tokens)) != len(tokens):
        raise ValueError("account tokens must be configured and distinct")
    for name in KEYS:
        if name not in values:
            values[name] = environment.get(name) or secrets.token_urlsafe(48)
    values.setdefault(
        "DEEP_RESEARCH_OPERATOR_ID",
        environment.get("DEEP_RESEARCH_OPERATOR_ID") or "local-operator",
    )
    values.setdefault(
        "SAKURA_AI_ACCOUNT_IDS",
        environment.get("SAKURA_AI_ACCOUNT_IDS")
        or ",".join(f"account-{index + 1}" for index in range(len(tokens))),
    )
    ids = values["SAKURA_AI_ACCOUNT_IDS"].split(",")
    if (
        len(ids) != len(tokens)
        or len(set(ids)) != len(ids)
        or not all(IDENTIFIER.fullmatch(value) for value in ids)
    ):
        raise ValueError("stable account IDs no longer match configured accounts")
    if not IDENTIFIER.fullmatch(values["DEEP_RESEARCH_OPERATOR_ID"]):
        raise ValueError("invalid operator ID")
    if len({values[name] for name in KEYS}) != len(KEYS):
        raise ValueError("service credentials must be distinct")
    if any(
        "\n" in value or "\r" in value or "\x00" in value for value in values.values()
    ):
        raise ValueError("invalid managed environment value")

    content = "".join(f"{name}={shlex.quote(values[name])}\n" for name in FIELDS)
    if path.exists() and path.read_text() == content:
        path.chmod(0o600)
        return
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".research-env-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    import sys

    try:
        initialize(Path(sys.argv[1]), dict(os.environ))
    except (ValueError, OSError):
        raise SystemExit(
            "Deep Research local environment initialization failed; check configuration"
        ) from None
