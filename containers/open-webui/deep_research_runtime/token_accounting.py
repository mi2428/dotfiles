"""Pinned Kimi K2.7 fresh-message counter and durable live calibration."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import inspect
import json
import os
import sqlite3
import time
import uuid
from functools import lru_cache
from pathlib import Path
from typing import cast
from urllib.parse import urlsplit

import tiktoken
from tiktoken.load import load_tiktoken_bpe

from sakura_kimi_model import (
    RESEARCH_MAX_REQUEST_BYTES,
    AttemptLease,
    complete_research,
    prepare_research_request,
)

REPOSITORY_REVISION = "74797c9c62378b951a1f6fcf5c4631024e9b8bef"
ASSET_HASHES = {
    "chat_template.jinja": "8d21200dff7e85beaf51c8b110952e039ffd0779f615d64d63293d74773360f9",
    "tiktoken.model": "b6c497a7469b33ced9c38afb1ad6e47f03f5e5dc05f15930799210ec050c5103",
    "tokenizer_config.json": "6dfafeacca3d44748fc4a2fcc6725be5ea616ecc5b95f5a8b4277077c06e7d9f",
}
ASSET_FINGERPRINT = hashlib.sha256(
    json.dumps(ASSET_HASHES, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
TEMPLATE_NAME = "kimi-k2.7-code-fresh-system-user-v1"
OUTPUT_RESERVE_TOKENS = 16_384
UNKNOWN_RISK_ACK = "possible duplicate execution or charge; no refund; no replay"
PATTERN = "|".join(
    [
        r"[\p{Han}]+",
        r"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]*[\p{Ll}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        r"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]+[\p{Ll}\p{Lm}\p{Lo}\p{M}&&[^\p{Han}]]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
        r"\p{N}{1,3}",
        r" ?[^\s\p{L}\p{N}]+[\r\n]*",
        r"\s*[\r\n]+",
        r"\s+(?!\S)",
        r"\s+",
    ]
)
KNOWN_SPECIAL_TOKENS = {
    163584: "[BOS]",
    163585: "[EOS]",
    163586: "<|im_end|>",
    163587: "<|im_user|>",
    163588: "<|im_assistant|>",
    163590: "<|start_header_id|>",
    163591: "<|end_header_id|>",
    163593: "[EOT]",
    163594: "<|im_system|>",
    163595: "<|tool_calls_section_begin|>",
    163596: "<|tool_calls_section_end|>",
    163597: "<|tool_call_begin|>",
    163598: "<|tool_call_argument_begin|>",
    163599: "<|tool_call_end|>",
    163601: "<|im_middle|>",
    163602: "<|media_begin|>",
    163603: "<|media_content|>",
    163604: "<|media_end|>",
    163605: "<|media_pad|>",
    163606: "<think>",
    163607: "</think>",
    163838: "[UNK]",
    163839: "[PAD]",
}
SHORT_CASES = (
    ("english", "Answer with OK only.", "Confirm the accounting fixture."),
    ("japanese", "OKだけを返してください。", "計数校正を確認してください。"),
    ("mixed", "Return OK only / OKのみ。", "ASCII 123、漢字、emoji🙂 boundary."),
)


def canonical_hash(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def default_asset_dir() -> Path:
    return Path(__file__).with_name("token_data")


def verify_assets(asset_dir: Path) -> None:
    for name, expected in ASSET_HASHES.items():
        try:
            actual = hashlib.sha256((asset_dir / name).read_bytes()).hexdigest()
        except OSError as exc:
            raise RuntimeError(f"token accounting asset unavailable: {name}") from exc
        if actual != expected:
            raise RuntimeError(f"token accounting asset hash mismatch: {name}")


@lru_cache(maxsize=2)
def _encoding(asset_dir_value: str) -> tiktoken.Encoding:
    asset_dir = Path(asset_dir_value)
    verify_assets(asset_dir)
    ranks = load_tiktoken_bpe(str(asset_dir / "tiktoken.model"))
    first_special = len(ranks)
    if first_special != 163584:
        raise RuntimeError("token accounting vocabulary size mismatch")
    special = {
        f"<|reserved_token_{token_id}|>": token_id
        for token_id in range(first_special, first_special + 256)
    }
    for token_id, token in KNOWN_SPECIAL_TOKENS.items():
        special.pop(f"<|reserved_token_{token_id}|>")
        special[token] = token_id
    return tiktoken.Encoding(
        name=TEMPLATE_NAME,
        pat_str=PATTERN,
        mergeable_ranks=ranks,
        special_tokens=special,
    )


def render_fresh_prompt(system: str, user: str) -> str:
    if type(system) is not str or type(user) is not str:
        raise ValueError("fresh prompt content must be strings")
    return (
        f"<|im_system|>system<|im_middle|>{system}<|im_end|>"
        f"<|im_user|>user<|im_middle|>{user}<|im_end|>"
        "<|im_assistant|>assistant<|im_middle|><think>"
    )


def count_fresh_prompt_tokens(system: str, user: str, asset_dir: Path | None = None) -> int:
    directory = (asset_dir or default_asset_dir()).resolve()
    return len(
        _encoding(str(directory)).encode(render_fresh_prompt(system, user), allowed_special="all")
    )


def counter_implementation_fingerprint() -> str:
    source = "\n".join(
        inspect.getsource(function)
        for function in (_encoding, render_fresh_prompt, count_fresh_prompt_tokens)
    )
    return canonical_hash(
        {
            "known_special_tokens": KNOWN_SPECIAL_TOKENS,
            "pattern": PATTERN,
            "source": source,
            "tiktoken": tiktoken.__version__,
        }
    )


def gateway_fingerprint(base_url: str) -> str:
    parts = urlsplit(base_url)
    if (
        parts.scheme not in {"http", "https"}
        or not parts.hostname
        or parts.path.rstrip("/") != "/v1"
        or parts.username is not None
        or parts.password is not None
        or parts.query
        or parts.fragment
    ):
        raise ValueError("gateway URL must be an absolute /v1 URL")
    default_port = 443 if parts.scheme == "https" else 80
    serving = f"{parts.scheme}://{parts.hostname.casefold()}:{parts.port or default_port}/v1"
    return hashlib.sha256(serving.encode()).hexdigest()


def boundary_case(model: str) -> tuple[str, str, str]:
    system = "Return exactly OK. This is the bounded tokenizer calibration request."
    chunk = "境界-boundary-0123456789🙂 "
    low, high = 0, 4096
    while True:
        try:
            prepare_research_request(model, system, chunk * high)
        except ValueError:
            break
        low, high = high, high * 2
    while low + 1 < high:
        middle = (low + high) // 2
        try:
            prepare_research_request(model, system, chunk * middle)
            low = middle
        except ValueError:
            high = middle
    user = chunk * low
    body = prepare_research_request(model, system, user)
    if len(body) < RESEARCH_MAX_REQUEST_BYTES - 128:
        raise RuntimeError("calibration boundary fixture is not near the request limit")
    return "boundary-64k", system, user


def calibration_cases(model: str) -> tuple[tuple[str, str, str], ...]:
    return (*SHORT_CASES, boundary_case(model))


@lru_cache(maxsize=8)
def _expected_profile(model: str, base_url: str, asset_dir_value: str) -> dict[str, object]:
    asset_dir = Path(asset_dir_value)
    cases = calibration_cases(model)
    local_counts = {
        name: count_fresh_prompt_tokens(system, user, asset_dir) for name, system, user in cases
    }
    case_hashes = {
        name: hashlib.sha256(prepare_research_request(model, system, user)).hexdigest()
        for name, system, user in cases
    }
    identity = {
        "asset_fingerprint": ASSET_FINGERPRINT,
        "counter_fingerprint": counter_implementation_fingerprint(),
        "gateway_fingerprint": gateway_fingerprint(base_url),
        "model_alias": model,
        "output_reserve_tokens": OUTPUT_RESERVE_TOKENS,
        "repository_revision": REPOSITORY_REVISION,
        "request_byte_ceiling": RESEARCH_MAX_REQUEST_BYTES,
        "template_name": TEMPLATE_NAME,
        "verified_input_ceiling_tokens": local_counts["boundary-64k"],
    }
    return {
        **identity,
        "profile_fingerprint": canonical_hash(identity),
        "case_hashes": case_hashes,
        "cases_hash": canonical_hash(case_hashes),
        "local_counts": local_counts,
    }


def expected_profile(model: str, base_url: str, asset_dir: Path | None = None) -> dict[str, object]:
    directory = (asset_dir or default_asset_dir()).resolve()
    verify_assets(directory)
    return _expected_profile(model, base_url, str(directory))


def create_profile_tables(db: sqlite3.Connection) -> None:
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS token_accounting_profiles (
            profile_fingerprint TEXT PRIMARY KEY,
            model_alias TEXT NOT NULL,
            gateway_fingerprint TEXT NOT NULL,
            repository_revision TEXT NOT NULL,
            asset_fingerprint TEXT NOT NULL,
            counter_fingerprint TEXT NOT NULL,
            template_name TEXT NOT NULL,
            request_byte_ceiling INTEGER NOT NULL,
            verified_input_ceiling_tokens INTEGER NOT NULL,
            output_reserve_tokens INTEGER NOT NULL,
            cases_hash TEXT NOT NULL,
            local_counts_json TEXT NOT NULL,
            observed_counts_json TEXT NOT NULL,
            operator_id TEXT NOT NULL,
            verified_at_ms INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS token_calibration_attempts (
            attempt_id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            case_name TEXT NOT NULL,
            state TEXT NOT NULL,
            profile_fingerprint TEXT NOT NULL,
            model_alias TEXT NOT NULL,
            gateway_fingerprint TEXT NOT NULL,
            request_hash TEXT NOT NULL,
            input_tokens_estimated INTEGER NOT NULL,
            output_tokens_reserved INTEGER NOT NULL,
            observed_prompt_tokens INTEGER,
            resolution_action_id TEXT UNIQUE,
            resolution_operator_id TEXT,
            resolution_risk_ack TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            UNIQUE(run_id, case_name)
        );
        """
    )


def _validated_profile_row(
    db: sqlite3.Connection, model: str, base_url: str, asset_dir: Path | None = None
) -> tuple[sqlite3.Row, dict[str, object]] | None:
    expected = expected_profile(model, base_url, asset_dir)
    row = db.execute(
        "SELECT * FROM token_accounting_profiles WHERE profile_fingerprint = ?",
        (expected["profile_fingerprint"],),
    ).fetchone()
    if row is None:
        return None
    try:
        local = json.loads(str(row["local_counts_json"]))
        observed = json.loads(str(row["observed_counts_json"]))
    except (TypeError, ValueError):
        return None
    scalar_fields = (
        "model_alias",
        "gateway_fingerprint",
        "repository_revision",
        "asset_fingerprint",
        "counter_fingerprint",
        "template_name",
        "request_byte_ceiling",
        "verified_input_ceiling_tokens",
        "output_reserve_tokens",
        "cases_hash",
    )
    if (
        any(row[field] != expected[field] for field in scalar_fields)
        or local != expected["local_counts"]
        or observed != local
        or canonical_hash(expected["case_hashes"]) != row["cases_hash"]
    ):
        return None
    return row, expected


def profile_is_verified(
    db: sqlite3.Connection, model: str, base_url: str, asset_dir: Path | None = None
) -> bool:
    try:
        return _validated_profile_row(db, model, base_url, asset_dir) is not None
    except (OSError, RuntimeError, ValueError):
        return False


def verified_input_ceiling(
    db: sqlite3.Connection, model: str, base_url: str, asset_dir: Path | None = None
) -> tuple[str, int] | None:
    validated = _validated_profile_row(db, model, base_url, asset_dir)
    if validated is None:
        return None
    row, _expected = validated
    return str(row["profile_fingerprint"]), int(row["verified_input_ceiling_tokens"])


def record_verified_profile(
    db: sqlite3.Connection,
    model: str,
    base_url: str,
    observed_counts: dict[str, int],
    operator_id: str,
    asset_dir: Path | None = None,
) -> None:
    expected = expected_profile(model, base_url, asset_dir)
    if observed_counts != expected["local_counts"]:
        raise ValueError("observed counts do not match the pinned counter")
    db.execute(
        "INSERT OR REPLACE INTO token_accounting_profiles "
        "(profile_fingerprint, model_alias, gateway_fingerprint, repository_revision, "
        "asset_fingerprint, counter_fingerprint, template_name, request_byte_ceiling, "
        "verified_input_ceiling_tokens, output_reserve_tokens, cases_hash, local_counts_json, "
        "observed_counts_json, operator_id, verified_at_ms) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            expected["profile_fingerprint"],
            model,
            expected["gateway_fingerprint"],
            REPOSITORY_REVISION,
            ASSET_FINGERPRINT,
            expected["counter_fingerprint"],
            TEMPLATE_NAME,
            RESEARCH_MAX_REQUEST_BYTES,
            expected["verified_input_ceiling_tokens"],
            OUTPUT_RESERVE_TOKENS,
            expected["cases_hash"],
            json.dumps(expected["local_counts"], sort_keys=True, separators=(",", ":")),
            json.dumps(observed_counts, sort_keys=True, separators=(",", ":")),
            operator_id,
            time.time_ns() // 1_000_000,
        ),
    )


async def calibrate(
    *,
    db_path: str,
    base_url: str,
    api_key: str,
    model: str,
    operator_id: str,
    timeout_seconds: int,
    asset_dir: Path,
) -> None:
    expected = expected_profile(model, base_url, asset_dir)
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    try:
        create_profile_tables(db)
        now = time.time_ns() // 1_000_000
        db.execute(
            "UPDATE token_calibration_attempts SET state = 'unknown', updated_at_ms = ? "
            "WHERE state = 'dispatched'",
            (now,),
        )
        db.commit()
        if db.execute(
            "SELECT 1 FROM token_calibration_attempts WHERE state = 'unknown' LIMIT 1"
        ).fetchone():
            raise RuntimeError("unknown calibration attempt requires explicit operator resolution")
        run_id = uuid.uuid4().hex
        observed: dict[str, int] = {}
        expected_local_counts = cast(dict[str, int], expected["local_counts"])
        for name, system, user in calibration_cases(model):
            body = prepare_research_request(model, system, user)
            attempt_id = f"calibration-{uuid.uuid4().hex}"
            input_tokens = expected_local_counts[name]
            now = time.time_ns() // 1_000_000
            db.execute(
                "INSERT INTO token_calibration_attempts "
                "(attempt_id, run_id, case_name, state, profile_fingerprint, model_alias, "
                "gateway_fingerprint, request_hash, input_tokens_estimated, "
                "output_tokens_reserved, created_at_ms, updated_at_ms) "
                "VALUES (?, ?, ?, 'dispatched', ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    attempt_id,
                    run_id,
                    name,
                    expected["profile_fingerprint"],
                    model,
                    expected["gateway_fingerprint"],
                    hashlib.sha256(body).hexdigest(),
                    input_tokens,
                    OUTPUT_RESERVE_TOKENS,
                    now,
                    now,
                ),
            )
            db.commit()
            anchor = time.time_ns() // 1_000_000
            completion = await complete_research(
                base_url,
                api_key,
                body,
                AttemptLease(
                    attempt_id=attempt_id,
                    deadline_monotonic=asyncio.get_running_loop().time() + timeout_seconds,
                    expires_at_unix_ms=anchor + timeout_seconds * 1000,
                ),
            )
            outcome = completion.outcome
            observed_prompt = outcome.prompt_tokens
            state = outcome.state
            if state == "succeeded" and (
                observed_prompt is None or observed_prompt != input_tokens
            ):
                state = "known_failed"
            db.execute(
                "UPDATE token_calibration_attempts SET state = ?, observed_prompt_tokens = ?, "
                "updated_at_ms = ? WHERE attempt_id = ? AND state = 'dispatched'",
                (state, observed_prompt, time.time_ns() // 1_000_000, attempt_id),
            )
            db.commit()
            if state == "unknown":
                raise RuntimeError("calibration outcome is unknown; blind replay is blocked")
            if state != "succeeded" or observed_prompt is None:
                raise RuntimeError("calibration did not return matching safe usage")
            observed[name] = observed_prompt
        record_verified_profile(db, model, base_url, observed, operator_id, asset_dir)
        db.commit()
    finally:
        db.close()


def abandon_calibration_attempt(
    db_path: str, attempt_id: str, action_id: str, operator_id: str, risk_ack: str
) -> None:
    if risk_ack != UNKNOWN_RISK_ACK:
        raise ValueError("explicit risk acknowledgement is required")
    db = sqlite3.connect(db_path)
    try:
        create_profile_tables(db)
        now = time.time_ns() // 1_000_000
        db.execute("BEGIN IMMEDIATE")
        db.execute(
            "UPDATE token_calibration_attempts SET state = 'unknown', updated_at_ms = ? "
            "WHERE state = 'dispatched'",
            (now,),
        )
        row = db.execute(
            "SELECT state, resolution_action_id, resolution_operator_id, resolution_risk_ack "
            "FROM token_calibration_attempts WHERE attempt_id = ?",
            (attempt_id,),
        ).fetchone()
        if row is None:
            raise ValueError("calibration attempt not found")
        exact = tuple(row) == ("abandoned_unresolved", action_id, operator_id, risk_ack)
        if exact:
            db.commit()
            return
        if row[0] != "unknown":
            raise ValueError("calibration attempt is not unknown")
        db.execute(
            "UPDATE token_calibration_attempts SET state = 'abandoned_unresolved', "
            "resolution_action_id = ?, resolution_operator_id = ?, resolution_risk_ack = ?, "
            "updated_at_ms = ? WHERE attempt_id = ? AND state = 'unknown'",
            (action_id, operator_id, risk_ack, now, attempt_id),
        )
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage pinned Kimi token calibration")
    commands = parser.add_subparsers(dest="command", required=True)
    calibration = commands.add_parser("calibrate")
    calibration.add_argument("--base-url", default=os.getenv("DEEP_RESEARCH_LLM_BASE_URL", ""))
    calibration.add_argument("--database", default=os.getenv("DEEP_RESEARCH_DB_PATH", ""))
    calibration.add_argument("--model", default=os.getenv("DEEP_RESEARCH_MODEL", ""))
    calibration.add_argument("--operator-id", default=os.getenv("DEEP_RESEARCH_OPERATOR_ID", ""))
    calibration.add_argument("--api-key-env", default="SAKURA_RESEARCH_API_KEY")
    calibration.add_argument("--asset-dir", type=Path, default=default_asset_dir())
    calibration.add_argument("--timeout", type=int, default=240)
    abandon = commands.add_parser("abandon")
    abandon.add_argument("--database", default=os.getenv("DEEP_RESEARCH_DB_PATH", ""))
    abandon.add_argument("--attempt-id", required=True)
    abandon.add_argument("--action-id", required=True)
    abandon.add_argument("--operator-id", default=os.getenv("DEEP_RESEARCH_OPERATOR_ID", ""))
    abandon.add_argument("--risk-ack", required=True)
    args = parser.parse_args()
    if args.command == "abandon":
        if not all(
            (args.database, args.operator_id, os.getenv("DEEP_RESEARCH_OPERATOR_API_KEY", ""))
        ):
            parser.error("database, operator ID, and operator key env are required")
        abandon_calibration_attempt(
            args.database, args.attempt_id, args.action_id, args.operator_id, args.risk_ack
        )
        print(json.dumps({"attempt_id": args.attempt_id, "state": "abandoned_unresolved"}))
        return 0
    api_key = os.getenv(args.api_key_env, "")
    if not all((args.base_url, args.database, args.model, args.operator_id, api_key)):
        parser.error("base URL, database, model, operator ID, and API key env are required")
    if not 1 <= args.timeout <= 240:
        parser.error("timeout must be between 1 and 240 seconds")
    asyncio.run(
        calibrate(
            db_path=args.database,
            base_url=args.base_url,
            api_key=api_key,
            model=args.model,
            operator_id=args.operator_id,
            timeout_seconds=args.timeout,
            asset_dir=args.asset_dir,
        )
    )
    expected = expected_profile(args.model, args.base_url, args.asset_dir)
    print(json.dumps({"profile_fingerprint": expected["profile_fingerprint"], "verified": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
