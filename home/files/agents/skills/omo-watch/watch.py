#!/usr/bin/env python3
"""Watch omo terminals hosted by herdr-core (hc) and recover stalled ones.

Discovery is dynamic: every poll reads ``hc ls``, follows live omo terminals
(optionally filtered by ``--name``/``--project``), keeps ``--pane`` as a
fallback address, and remembers an address whose omo crashed but whose shell is
still alive.

Recovery kills only the omo foreground process tree; the pane's shell remains.
It then starts omo with the previous thinking level and submits a mass-ulw
handoff prompt naming the predecessor's error and session file.

Runtime state: ``$XDG_RUNTIME_DIR/omo-watch`` (log, lock, handoffs, paused);
``OMO_WATCH_RUNTIME`` overrides it.  A dry run takes ``lock-dry``, a real run
takes ``lock``.  No systemd unit, no ``~/.local`` install.

Each target restarts in its own project directory with the thinking level from
its own footer, so one watcher supervises omos from different projects.  Pane
claims (``.../omo-watch/claims``) are shared across runtime roots, so a second
watcher skips panes the first one already owns instead of double-recovering.
"""

from __future__ import annotations

import argparse
import fcntl
import glob
import json
import os
import re
import shutil
import shlex
import signal
import subprocess
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, TypedDict, cast

HOME = os.path.expanduser("~")
# Resolve herdr-core's CLI from PATH so the skill is not tied to one host's
# install location; OMO_WATCH_HC pins it explicitly when needed.
HC = (
    os.environ.get("OMO_WATCH_HC")
    or shutil.which("hc")
    or os.path.join(HOME, ".local/bin/hc")
)
HC_ENV = dict(os.environ)
HC_ENV.pop("HC_TERMINAL_ID", None)  # no <hc from=...> tags on typed commands
XDG_RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/omo-watch-{os.getuid()}"
RUNTIME = os.environ.get("OMO_WATCH_RUNTIME") or os.path.join(XDG_RUNTIME, "omo-watch")
# Pane claims are shared across runtime roots: two watchers (any --pane filters)
# may never recover the same terminal.  Locks live in a fixed directory so a
# split runtime cannot split ownership.
CLAIMS = os.environ.get("OMO_WATCH_CLAIMS") or os.path.join(
    XDG_RUNTIME, "omo-watch", "claims"
)
SHELLS = {"fish", "bash", "zsh", "sh", "dash", "nu", "elvish", "ksh"}
FATAL_RE = re.compile(
    r"(System operation aborted|Summarization stream stalled|Compaction rejected|"
    r"no provider events for|provider\s+\S+\s+stalled|provider error|model call failed)",
    re.IGNORECASE,
)
CLK_TCK = os.sysconf("SC_CLK_TCK")
PROMPT_HEAD = (
    "mass ulw で作業を引き継いでください。前任者は以下のエラーで停止していました"
)
# The TUI footer shows ``effort <level>``; these are omo's --thinking levels.
EFFORT_RE = re.compile(r"effort\s+(off|minimal|low|medium|high|xhigh|max)\b")
# omo's goal loop parks in this state when it needs a human decision.
BLOCKED_RE = re.compile(r"Goal blocked:.*waiting_human")
# Context signals: what omo says it is doing, and when it expects a wake.
BACKSTOP_RE = re.compile(
    r"Stall backstop ready\s+(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(?::(\d{2}))?"
    r"\s*(?:GMT([+-]\d{1,2}))?"
)
WAKE_IN_RE = re.compile(r"goal continues in\s+([0-9][0-9ms\s.]{0,20})")
CACHE_WARM_RE = re.compile(r"Cache-warm wait|wake source on duty", re.IGNORECASE)
COMPACTING_RE = re.compile(
    r"Compacting context|Compaction (?:in progress|running)", re.IGNORECASE
)
BACKGROUND_RE = re.compile(
    r"(?:\bwave\s+\d+/\d+\b"
    r"|\b\d+/\d+\s+done,\s+\d+\s+running\b"
    r"|^[\s]*[▶⏵⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏].*\b(?:running|pending)\b"
    r"|\bmon_[A-Za-z0-9]+\b"
    r"|\bwatching\s+.*\b(?:CI|checks|PR)\b"
    r"|\bbackground\b.*\b(?:job|task|process|wave)s?\b.*\b(?:running|active|pending)\b)",
    re.IGNORECASE | re.MULTILINE,
)
ACHIEVED_RE = re.compile(r"Goal achieved", re.IGNORECASE)
INTENT_RE = re.compile(r"^[\s]*(Now|Next)[\s]*:[\s]*(.+)$")
THOUGHT_RE = re.compile(r"^[\s]*Thought[\s]*:")
DURATION_TOKEN_RE = re.compile(r"(\d+)\s*([ms])", re.IGNORECASE)


class Foreground(TypedDict, total=False):
    """Foreground process reported by ``hc get``."""

    argv: list[str]
    cwd: str
    name: str
    pid: int


class StatusInfo(TypedDict, total=False):
    """Structured herdr status (``app`` plus ``state``)."""

    app: str
    state: str


class TerminalInfo(TypedDict, total=False):
    """Subset of a herdr-core terminal record used by the watcher."""

    address: str
    agent: str
    cwd: str
    exit_code: int | None
    foreground: Foreground
    name: str
    state: str
    status: StatusInfo | str
    turn: int


@dataclass(frozen=True)
class SessionFile:
    """Session JSONL chosen as a target's progress signal."""

    path: str
    size: int
    mtime_ns: int


@dataclass
class Target:
    """Per-terminal timers, session claim, and recovery budget."""

    addr: str
    project: str
    name: str | None
    pid: int | None = None
    session: str | None = None
    last_progress: float = field(default_factory=time.time)
    cpu: tuple[float, int, int] | None = None
    fingerprint: tuple[int, int] | None = None
    absent_since: float | None = None
    boot_until: float = 0.0
    fatal_sig: str | None = None
    fatal_since: float | None = None
    frozen_since: float | None = None
    blocked_since: float | None = None
    recoveries: list[float] = field(default_factory=list[float])
    last_status: str | None = None
    thinking: str | None = None
    # flock held on this pane's claim file for this watcher's lifetime.
    claim_fd: int | None = None
    # Context gate: a fired timer may be deferred while the pane shows work.
    defer_until: float = 0.0
    defers: dict[str, int] = field(default_factory=dict[str, int])
    last_context: dict[str, Any] = field(default_factory=dict[str, Any])


@dataclass(frozen=True)
class DiscoveredTerminal:
    """Current view of one live terminal that the watcher may manage."""

    info: TerminalInfo
    foreground: Foreground
    omo_running: bool
    project: str
    name: str | None


# (terminal address, target state, trigger mode, evidence for the handoff)
Action = tuple[str, Target, str, dict[str, Any]]
# /proc/<pid>/stat subset: parent pid, state, utime+stime ticks.
ProcRecord = tuple[int, str, int]


def now_iso() -> str:
    """Return the current local time as an ISO-8601 string with an offset."""
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def log(msg: str) -> None:
    """Append a timestamped line to the runtime log and stderr."""
    line = f"[{now_iso()}] {msg}"
    try:
        with open(os.path.join(RUNTIME, "watch.log"), "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass
    print(line, file=sys.stderr, flush=True)


def hc(args: Sequence[str], timeout: float = 30) -> subprocess.CompletedProcess[str]:
    """Run herdr-core's CLI with a timeout and without leaking terminal tags."""
    return subprocess.run(
        [HC, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=HC_ENV,
        check=False,
    )


def hc_json(args: Sequence[str]) -> object | None:
    """Run ``hc ... --json`` and return the decoded payload when it succeeds."""
    try:
        proc = hc([*args, "--json"])
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def get_term(addr: str) -> TerminalInfo | None:
    """Fetch one terminal record by address."""
    raw = hc_json(["get", addr])
    if not isinstance(raw, dict):
        return None
    return cast(TerminalInfo, raw)


def ls_terms() -> list[TerminalInfo]:
    """List every live herdr-core terminal visible to ``hc``."""
    raw = hc_json(["ls"])
    if not isinstance(raw, dict):
        return []
    payload = cast(dict[str, Any], raw)
    rows = payload.get("terminals")
    if not isinstance(rows, list):
        return []
    return [
        cast(TerminalInfo, row)
        for row in cast(list[object], rows)
        if isinstance(row, dict)
    ]


def pane_text(addr: str, lines: int = 120) -> str:
    """Capture the tail of a pane, or an empty string when it is unreadable."""
    try:
        proc = hc(["read", addr, "--lines", str(lines)], timeout=20)
    except (subprocess.TimeoutExpired, OSError):
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def status_state(info: TerminalInfo | None) -> str | None:
    """Return herdr's state string for a terminal status."""
    if not info:
        return None
    status = info.get("status")
    if isinstance(status, dict):
        return status.get("state")
    if isinstance(status, str):
        return status
    return None


def status_app(info: TerminalInfo | None) -> str | None:
    """Return the app herdr attributes the status to (``omo``, ``omp``, ...)."""
    if not info:
        return None
    status = info.get("status")
    if isinstance(status, dict):
        return status.get("app")
    return None


def omo_terminal(row: TerminalInfo) -> bool:
    """Report whether an ``hc ls`` row is attributed to omo.

    herdr-core reports the app on ``status.app``, not on an ``agent`` field; the
    old ``agent`` spelling is still accepted so a rename cannot blind discovery.
    """
    return (status_app(row) or row.get("agent")) == "omo"


def is_omo(foreground: Foreground) -> bool:
    """Report whether a foreground process belongs to the omo bundle."""
    blob = " ".join(foreground.get("argv") or [])
    return ("/omo-ai/" in blob or "omo-ai@" in blob) and (
        "senpi/dist/bundle/cli.js" in blob or "omo-ai/plugin" in blob
    )


def proc_table() -> dict[int, ProcRecord]:
    """Snapshot ``/proc`` into parent/state/CPU-tick records."""
    table: dict[int, ProcRecord] = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat", "rb") as handle:
                data = handle.read().decode("utf-8", "replace")
        except OSError:
            continue
        # The command name is parenthesized and may contain spaces, so split
        # after its last closing parenthesis instead of on every space.
        right_paren = data.rfind(")")
        if right_paren < 0:
            continue
        fields = data[right_paren + 2 :].split()
        if len(fields) < 15:
            continue
        try:
            table[pid] = (int(fields[1]), fields[0], int(fields[11]) + int(fields[12]))
        except (ValueError, IndexError):
            continue
    return table


def tree_of(root: int, table: dict[int, ProcRecord] | None = None) -> list[int]:
    """Return ``root`` and all of its descendants in ``/proc``."""
    table = table or proc_table()
    children: dict[int, list[int]] = {}
    for pid, record in table.items():
        children.setdefault(record[0], []).append(pid)
    out: list[int] = []
    stack = [root]
    while stack:
        pid = stack.pop()
        if pid in out or pid <= 1:
            continue
        out.append(pid)
        stack.extend(children.get(pid, []))
    return out


def cpu_split(root: int) -> tuple[int, int, list[int]]:
    """Return root ticks, descendant ticks, and the process list."""
    table = proc_table()
    pids = tree_of(root, table)
    root_ticks = other_ticks = 0
    for pid in pids:
        record = table.get(pid)
        if not record:
            continue
        if pid == root:
            root_ticks += record[2]
        else:
            other_ticks += record[2]
    return root_ticks, other_ticks, pids


def session_dir(project: str) -> str:
    """Map a project directory to omo's per-project session directory."""
    slug = "--" + project.strip("/").replace("/", "-") + "--"
    return os.path.join(HOME, ".omo/agent/sessions", slug)


def newest_session(project: str, exclude: set[str] | None = None) -> SessionFile | None:
    """Pick the newest session file, preferring one no sibling target claims."""
    rows: list[tuple[int, int, str]] = []
    for path in glob.glob(os.path.join(session_dir(project), "*.jsonl")):
        try:
            stat = os.stat(path)
        except OSError:
            continue
        rows.append((stat.st_mtime_ns, stat.st_size, path))
    if not rows:
        return None
    rows.sort(reverse=True)
    # Same-project panes must not share one session's growth as their own
    # progress signal, so fall back to the newest claimed file only when every
    # candidate is already taken.
    mtime_ns, size, path = next(
        (row for row in rows if not exclude or row[2] not in exclude), rows[0]
    )
    return SessionFile(path=path, size=size, mtime_ns=mtime_ns)


def claimed_sessions(states: dict[str, Target], addr: str) -> set[str]:
    """Return session files already owned by other live targets."""
    return {
        state.session
        for other, state in states.items()
        if other != addr and state.session
    }


def last_event(path: str | None) -> str:
    """Summarize the newest parseable event in a session JSONL file."""
    if not path:
        return "(no session file)"
    try:
        stat = os.stat(path)
        with open(path, "rb") as handle:
            handle.seek(max(0, stat.st_size - 131072))
            lines = handle.read().splitlines()
    except OSError:
        return "(unreadable session file)"
    for raw in reversed(lines):
        try:
            decoded = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(decoded, dict):
            continue
        event = cast(dict[str, Any], decoded)
        message_value = event.get("message")
        message: dict[str, Any] = (
            cast(dict[str, Any], message_value)
            if isinstance(message_value, dict)
            else {}
        )
        bits: list[str] = [str(event.get("type") or "?")]
        role = message.get("role")
        if role:
            bits.append(str(role))
        content = message.get("content")
        if isinstance(content, list):
            for part in cast(list[object], content):
                if not isinstance(part, dict):
                    continue
                part_info = cast(dict[str, Any], part)
                if part_info.get("type") == "toolCall":
                    tool = part_info.get("name") or part_info.get("toolName")
                    bits.append(f"tool={tool}")
                    break
        timestamp = event.get("timestamp")
        if timestamp:
            bits.append(f"@{timestamp}")
        return " ".join(bits)
    return "(no parseable event)"


def parse_ts(line: str) -> float | None:
    """Parse the first RFC 3339 timestamp in a log line."""
    match = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)", line)
    if not match:
        return None
    try:
        return datetime.fromisoformat(match.group(1).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def recent_errors(session: str | None) -> list[str]:
    """Collect the last two provider/compaction errors from omo's logs."""
    session_id = None
    if session:
        match = re.search(r"_([0-9a-f-]{36})\.jsonl$", os.path.basename(session))
        if match:
            session_id = match.group(1)
    cutoff = time.time() - 6 * 3600
    errors: list[str] = []
    for name in ("session.log", "OmO-debug.log", "compaction.log"):
        path = os.path.join(HOME, ".omo/agent/logs", name)
        try:
            stat = os.stat(path)
            with open(path, "rb") as handle:
                handle.seek(max(0, stat.st_size - 262144))
                lines = handle.read().decode("utf-8", "replace").splitlines()
        except OSError:
            continue
        for line in lines:
            lowered = line.lower()
            if not any(
                key in lowered
                for key in (
                    '"level":"error"',
                    '"error":',
                    "stalled",
                    "aborted",
                    "compaction rejected",
                    "panic",
                )
            ):
                continue
            if session_id and '"sessionid"' in lowered and session_id not in line:
                continue
            timestamp = parse_ts(line)
            if timestamp is not None and timestamp < cutoff:
                continue
            line = line.strip()
            if line and line not in errors:
                errors.append(line)
    return errors[-2:]


def pane_fatal(text: str) -> list[str]:
    """Return up to three fatal provider/compaction lines near the prompt."""
    lines = [line for line in text.splitlines() if line.strip()]
    return [line.strip() for line in lines[-15:] if FATAL_RE.search(line)][-3:]


def pane_blocked(text: str) -> str | None:
    """Return the footer line when omo's goal loop waits on a human decision."""
    for line in reversed(text.splitlines()):
        if BLOCKED_RE.search(line):
            return line.strip()[-300:]
    return None


def parse_duration(text: str) -> float | None:
    """Return seconds for tokens such as ``4m 30s`` or a truncated ``1m 2``."""
    total = 0.0
    found = False
    for amount, unit in DURATION_TOKEN_RE.findall(text):
        found = True
        total += int(amount) * (60 if unit.lower() == "m" else 1)
    return total if found else None


def parse_backstop(line: str) -> float | None:
    """Parse omo's ``Stall backstop ready <date> <time> GMT+9`` footer."""
    match = BACKSTOP_RE.search(line)
    if not match:
        return None
    date, hour_minute, seconds, offset = match.groups()
    try:
        stamp = datetime.strptime(f"{date} {hour_minute}", "%Y-%m-%d %H:%M")
        if seconds:
            stamp = stamp.replace(second=int(seconds))
        if offset:
            tz = timezone(timedelta(hours=int(offset)))
        else:
            tz = datetime.now().astimezone().tzinfo
        return stamp.replace(tzinfo=tz).timestamp()
    except ValueError:
        return None


def pane_context(text: str, now: float) -> dict[str, Any]:
    """Extract what omo says it is doing and when it expects to wake up."""
    lines = [line.rstrip() for line in text.splitlines()]
    tail = lines[-80:]
    active: list[str] = []
    wake_epoch: float | None = None
    wake_reason: str | None = None
    for line in tail:
        stripped = line.strip()
        if not stripped:
            continue
        if wake_epoch is None:
            parsed = parse_backstop(stripped)
            if parsed is not None and parsed > now:
                wake_epoch = parsed
                wake_reason = stripped[:200]
        if wake_epoch is None:
            match = WAKE_IN_RE.search(stripped)
            if match:
                seconds = parse_duration(match.group(1))
                if seconds:
                    wake_epoch = now + seconds
                    wake_reason = stripped[:200]
        if (
            CACHE_WARM_RE.search(stripped)
            or COMPACTING_RE.search(stripped)
            or BACKGROUND_RE.search(stripped)
        ) and stripped not in active:
            active.append(stripped[:200])
    intent: dict[str, str] = {}
    for line in tail:
        match = INTENT_RE.match(line)
        if match:
            intent[match.group(1).lower()] = match.group(2).strip()[:300]
    thought: str | None = None
    for index in range(len(lines) - 1, -1, -1):
        if not THOUGHT_RE.match(lines[index]):
            continue
        chunk: list[str] = []
        for follow in lines[index + 1 : index + 5]:
            if (
                not follow.strip()
                or INTENT_RE.match(follow)
                or THOUGHT_RE.match(follow)
            ):
                break
            chunk.append(follow.strip())
        thought = " ".join(chunk)[:400] or None
        break
    footer = "\n".join([line for line in lines if line.strip()][-8:])
    return {
        "wake_at": (
            datetime.fromtimestamp(wake_epoch, timezone.utc)
            .astimezone()
            .isoformat(timespec="seconds")
            if wake_epoch
            else None
        ),
        "wake_epoch": wake_epoch,
        "wake_reason": wake_reason,
        "active": active[:4],
        "goal_achieved": bool(ACHIEVED_RE.search(footer)),
        "intent": intent or None,
        "thought": thought,
    }


def session_age(target: Target, now: float) -> float | None:
    """Seconds since the session JSONL was last written, if it exists."""
    if not target.session:
        return None
    try:
        return max(0.0, now - os.stat(target.session).st_mtime)
    except OSError:
        return None


def infer_context(
    args: argparse.Namespace,
    target: Target,
    mode: str,
    ctx: dict[str, Any],
    now: float,
) -> tuple[str, float, str]:
    """Decide whether a fired timer should wait for context or recover now."""
    if ctx.get("goal_achieved"):
        return (
            "wait",
            now + args.context_max_wait,
            "goal achieved; leaving the finished session alone",
        )
    defers = target.defers.get(mode, 0)
    if defers >= args.context_max_defers:
        return (
            "recover",
            0.0,
            f"context deferrals exhausted ({defers}/{args.context_max_defers})",
        )
    wake_epoch = ctx.get("wake_epoch")
    if isinstance(wake_epoch, (int, float)) and wake_epoch > now:
        until = min(wake_epoch + 60.0, now + args.context_max_wait)
        return "wait", until, f"scheduled wake: {ctx.get('wake_reason')}"
    active = cast(list[str], ctx.get("active") or [])
    if active:
        return (
            "wait",
            now + args.context_grace,
            "pane shows active work: " + " | ".join(item[:120] for item in active[:2]),
        )
    if now - target.last_progress < args.context_grace:
        return (
            "wait",
            now + args.context_grace,
            f"CPU/session progress {int(now - target.last_progress)}s ago",
        )
    age = session_age(target, now)
    if age is not None and age < args.context_grace:
        return "wait", now + args.context_grace, f"session written {int(age)}s ago"
    return (
        "recover",
        0.0,
        "no scheduled wake, active work, or recent progress in the pane",
    )


def gate_action(
    args: argparse.Namespace,
    target: Target,
    mode: str,
    evidence: dict[str, Any],
    text: str,
    now: float,
) -> dict[str, Any] | None:
    """Defer a fired timer when the pane context says work is still coming."""
    if now < target.defer_until:
        return None
    ctx = pane_context(text, now)
    decision, until, reason = infer_context(args, target, mode, ctx, now)
    if decision == "wait":
        if not ctx.get("goal_achieved"):
            target.defers[mode] = target.defers.get(mode, 0) + 1
        target.defer_until = max(now + 1.0, until)
        target.last_context = ctx
        hint = cast(dict[str, str], ctx.get("intent") or {})
        focus = "; ".join(
            f"{key}={value[:100]}" for key, value in hint.items() if value
        )
        log(
            f"DEFER {target.addr} {mode}: {reason}"
            + (f" | {focus}" if focus else "")
            + f"; recheck in {int(target.defer_until - now)}s"
        )
        return None
    target.defer_until = 0.0
    gated = dict(evidence)
    gated["context"] = ctx
    gated["context_verdict"] = reason
    return gated


def launch_cwd(launch: str) -> str | None:
    """Return the directory a launch command cd's into, if it names one."""
    try:
        tokens = shlex.split(launch)
    except ValueError:
        return None
    for index, token in enumerate(tokens[:-1]):
        if token == "cd":
            return os.path.expanduser(tokens[index + 1])
    return None


def thinking_level(pane: str, target: Target) -> str | None:
    """Return the footer's ``effort`` level, else the last level seen."""
    effort = EFFORT_RE.search(pane)
    return effort.group(1) if effort else target.thinking


def launch_command(
    args: argparse.Namespace, addr: str, target: Target, pane: str
) -> str:
    """Return the restart command for one target.

    A plain ``--launch`` and the ``omo`` default are per-target: the command
    cd's into the target's project and inherits the footer thinking level, so
    one watcher can restart panes from different projects.  A custom
    ``--launch`` only applies to panes the caller named with ``--pane`` (or
    ``--name``); dynamically discovered panes keep their own project.
    ``--launch-pane ADDR=CMD`` overrides one address explicitly.
    """
    override = args.launch_pane.get(addr)
    if override:
        return override
    named = addr in args.pane or (
        args.name is not None and target.name == args.name
    )
    custom = (args.launch or "").strip()
    if custom and custom != "omo" and named:
        return custom
    level = thinking_level(pane, target)
    command = "omo" if level is None else f"omo --thinking {level}"
    if target.project:
        return f"cd {shlex.quote(target.project)} && {command}"
    return command


def fallback_error(mode: str, evidence: dict[str, Any]) -> str:
    """Describe a trigger in prose when no log error line is available."""
    if mode == "omo-absent":
        return (
            f"omo プロセスが消失しました (state={evidence.get('state')}, "
            f"exit_code={evidence.get('exit_code')}, "
            f"foreground={evidence.get('foreground')})"
        )
    if mode == "no-progress":
        return (
            f"{evidence.get('stalled_seconds')}秒間 進捗（CPU/セッション/ログ）が"
            f"変化しませんでした "
            f"(status=working, turn={evidence.get('turn')}, "
            f"root_cpu={evidence.get('root_cpu_pct')}%, "
            f"children_cpu={evidence.get('children_cpu_pct')}%)"
        )
    if mode == "frozen-working":
        return (
            f"TUI が 'Working' 表示のまま {evidence.get('frozen_seconds')}秒 "
            f"応答していません (herdr status={evidence.get('state')})"
        )
    if mode == "blocked-at-prompt":
        return (
            f"ゴール継続が人間待ちのまま {evidence.get('blocked_seconds')}秒 "
            f"停止しています (herdr status={evidence.get('state')}, "
            f"footer={evidence.get('blocked')})"
        )
    return f"{mode}: {json.dumps(evidence, ensure_ascii=False)}"


def send_text(addr: str, text: str, timeout: float = 90) -> bool:
    """Type text into a pane and report whether ``hc`` accepted it."""
    try:
        proc = hc(["send", addr, text], timeout=timeout)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return proc.returncode == 0


def kill_tree(root: int) -> list[int]:
    """Terminate ``root``'s process tree, escalating to SIGKILL after 8s."""
    table = proc_table()
    pids = [pid for pid in tree_of(root, table) if pid != os.getpid()]
    ordered = [root] + [pid for pid in pids if pid != root]
    for pid in ordered:
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 8
    while time.time() < deadline and any(
        os.path.exists(f"/proc/{pid}") for pid in pids
    ):
        time.sleep(0.2)
    for pid in [pid for pid in pids if os.path.exists(f"/proc/{pid}")]:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
    return pids


def wait_shell(addr: str, old_pid: int | None, timeout: float = 25) -> bool:
    """Wait until the pane's foreground process is a different shell."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        foreground = (get_term(addr) or {}).get("foreground") or {}
        name = os.path.basename(foreground.get("name") or "")
        if name in SHELLS and foreground.get("pid") != old_pid:
            return True
        time.sleep(0.5)
    return False


def wait_omo(addr: str, timeout: float, settle: float = 4.0) -> bool:
    """Wait for the restarted omo TUI to render and settle."""
    deadline = time.time() + timeout
    started = None
    while time.time() < deadline:
        foreground = (get_term(addr) or {}).get("foreground") or {}
        if is_omo(foreground):
            started = started or time.time()
            text = pane_text(addr, 60)
            if any(key in text for key in ("OmO", "effort ", "esc to interrupt")):
                if time.time() - started >= settle:
                    return True
            elif time.time() - started >= 40:
                return True
        time.sleep(1)
    return False


def turn_started(addr: str, timeout: float = 75) -> bool:
    """Wait until the submitted handoff prompt starts an omo turn."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        text = pane_text(addr, 40)
        if "mass ulw" in text:
            for row in ls_terms():
                if row.get("address") == addr and status_state(row) == "working":
                    return True
            if "Working (" in text:
                return True
        time.sleep(2)
    return False


def write_handoff(
    path: str, addr: str, mode: str, evidence: dict[str, Any], pane: str, prompt: str
) -> None:
    """Persist the trigger evidence, handoff prompt, and pane tail."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            f"# omo-watch handoff ({now_iso()})\n\n- terminal: `{addr}`\n"
            f"- trigger: `{mode}`\n"
        )
        for key, value in evidence.items():
            if isinstance(value, (dict, list)):
                value = json.dumps(value, ensure_ascii=False, indent=2)
            handle.write(f"- {key}: {value}\n")
        handle.write("\n## Handoff prompt\n\n```\n" + prompt + "\n```\n")
        handle.write("\n## Pane tail\n\n```\n" + pane[-8000:] + "\n```\n")


def build_prompt(
    addr: str,
    target: Target,
    mode: str,
    evidence: dict[str, Any],
    errors: list[str],
    handoff: str,
) -> str:
    """Build the mass-ulw handoff prompt submitted to the restarted omo."""
    error_text = "\n".join(errors)
    return (
        f"{PROMPT_HEAD}\n"
        f"{error_text}\n"
        f"- 検出: {mode} ({json.dumps(evidence, ensure_ascii=False)[:600]})\n"
        f"- 端末/旧PID: {addr} / {evidence.get('old_pid')}\n"
        f"- 旧セッション: {target.session or '(none)'}\n"
        f"- 最後のイベント: {last_event(target.session)}\n"
        f"- 文脈判定: {evidence.get('context_verdict', '(none)')}\n"
        f"- ペイン文脈: {json.dumps(evidence.get('context', {}), ensure_ascii=False)[:500]}\n"
        f"- 作業ディレクトリ: {target.project}\n"
        f"- 詳細ログ: {handoff}\n\n"
        "未完了タスクを特定し、mass ultrawork (mass-ulw) の依存グラフで、"
        "テスト/ビルド/実検証まで含めて続行してください。"
        "旧セッションが巨大な場合は直近の todo・git status/diff・検証ログだけを読み、"
        "必要な箇所に絞ること。"
    )


def discover(
    args: argparse.Namespace, known: dict[str, Target]
) -> dict[str, DiscoveredTerminal]:
    """Combine live omo rows, ``--pane`` fallbacks, and remembered addresses."""
    found: dict[str, DiscoveredTerminal] = {}
    for row in ls_terms():
        address = row.get("address")
        if not address or row.get("state") != "live" or not omo_terminal(row):
            continue
        if args.name and row.get("name") != args.name:
            continue
        info = get_term(address)
        if info is None:
            continue
        foreground = info.get("foreground") or {}
        project = foreground.get("cwd") or info.get("cwd") or ""
        if args.project and project != args.project:
            continue
        found[address] = DiscoveredTerminal(
            info=info,
            foreground=foreground,
            omo_running=True,
            project=project,
            name=row.get("name"),
        )
    for address in args.pane:
        if address in found:
            continue
        info = get_term(address)
        if not info or info.get("state") != "live":
            continue
        foreground = info.get("foreground") or {}
        project = foreground.get("cwd") or info.get("cwd") or args.project or ""
        if args.project and project != args.project:
            continue
        found[address] = DiscoveredTerminal(
            info=info,
            foreground=foreground,
            omo_running=is_omo(foreground),
            project=project,
            name=known[address].name if address in known else None,
        )
    for address, target in known.items():
        if address in found:
            continue
        info = get_term(address)
        if not info or info.get("state") != "live":
            continue
        foreground = info.get("foreground") or {}
        project = foreground.get("cwd") or target.project
        if args.project and project != args.project:
            continue
        found[address] = DiscoveredTerminal(
            info=info,
            foreground=foreground,
            omo_running=is_omo(foreground),
            project=project,
            name=target.name,
        )
    return found


def claim_target(addr: str) -> tuple[int | None, int | None, str | None]:
    """Claim ``addr`` for this watcher.

    Returns ``(fd, holder_pid, error)``: an owned fd on success, the foreign
    pid when another live watcher holds the pane, or an error string when the
    claim directory is unusable (the caller then watches the pane unclaimed).
    The flock dies with the process, so a crashed watcher never leaves a pane
    stuck.
    """
    try:
        os.makedirs(CLAIMS, mode=0o700, exist_ok=True)
        path = os.path.join(CLAIMS, f"{addr}.claim")
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as exc:
        return None, None, str(exc)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        holder: int | None = None
        try:
            raw = os.pread(fd, 32, 0).strip()
            holder = int(raw) if raw else None
        except (OSError, ValueError):
            pass
        os.close(fd)
        return None, holder, None
    try:
        os.ftruncate(fd, 0)
        os.write(fd, f"{os.getpid()}\n".encode())
    except OSError:
        pass
    return fd, None, None


def release_claim(target: Target) -> None:
    """Release this watcher's claim on ``target``'s pane."""
    fd = target.claim_fd
    target.claim_fd = None
    if fd is None:
        return
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass


def ensure_target(
    args: argparse.Namespace,
    states: dict[str, Target],
    address: str,
    discovered: DiscoveredTerminal,
) -> Target | None:
    """Return the tracked target, claiming its pane for this watcher first."""
    target = states.get(address)
    if target is not None:
        return target
    fd: int | None = None
    if not args.dry_run:
        fd, holder, error = claim_target(address)
        if fd is None and holder is not None:
            log(f"{address}: watched by another omo-watch (pid {holder}); skipping")
            return None
        if fd is None:
            log(f"{address}: claim unavailable ({error}); watching unclaimed")
    target = Target(address, discovered.project, discovered.name, claim_fd=fd)
    states[address] = target
    log(
        f"{address}: watching (project={discovered.project}, "
        f"name={discovered.name})"
    )
    return target


def fingerprint(target: Target) -> tuple[int, int]:
    """Return the session file's size/mtime pair used to detect progress."""
    if not target.session:
        return (0, 0)
    try:
        stat = os.stat(target.session)
    except OSError:
        return (0, 0)
    return (stat.st_size, stat.st_mtime_ns)


def cpu_activity(target: Target, pid: int) -> tuple[float, float, list[int]]:
    """Return root and descendant CPU percentages since the previous sample."""
    root_ticks, other_ticks, pids = cpu_split(pid)
    now = time.time()
    if target.cpu is None:
        target.cpu = (now, root_ticks, other_ticks)
        return 0.0, 0.0, pids
    previous_time, previous_root, previous_other = target.cpu
    elapsed = max(0.5, now - previous_time)
    root_pct = max(0, root_ticks - previous_root) / CLK_TCK / elapsed * 100
    other_pct = max(0, other_ticks - previous_other) / CLK_TCK / elapsed * 100
    target.cpu = (now, root_ticks, other_ticks)
    return root_pct, other_pct, pids


def evaluate(
    args: argparse.Namespace, states: dict[str, Target], now: float
) -> list[Action]:
    """Poll every target once and return the recoveries it requires."""
    seen = discover(args, states)
    for address in list(states):
        if address in seen:
            continue
        info = get_term(address)
        if info is None:
            # hc timed out or the core restarted: keep this target's session,
            # recovery budget, and thinking level instead of forgetting them.
            continue
        if info.get("state") != "live":
            log(f"{address}: target gone; dropping")
            release_claim(states.pop(address))
    actions: list[Action] = []
    for address, discovered in seen.items():
        target = ensure_target(args, states, address, discovered)
        if target is None:
            continue
        foreground = discovered.foreground
        if discovered.omo_running:
            target.absent_since = None
            pid = foreground.get("pid")
            if not pid:
                target.last_status = "omo (no pid)"
                continue
            if pid != target.pid:
                target.pid = pid
                session = newest_session(
                    discovered.project, claimed_sessions(states, address)
                )
                target.session = session.path if session else None
                target.last_progress = now
                # Never shorten a window set by a just-finished recovery.
                target.boot_until = max(target.boot_until, now + args.absent_grace)
                target.cpu = None
                target.fingerprint = None
                target.fatal_sig = None
                target.fatal_since = None
                target.frozen_since = None
                target.blocked_since = None
                target.defer_until = 0.0
                target.defers.clear()
                log(f"{address}: omo pid {pid} session={target.session}")
            current_fingerprint = fingerprint(target)
            changed = current_fingerprint != target.fingerprint
            target.fingerprint = current_fingerprint
            root_pct, other_pct, pids = cpu_activity(target, pid)
            if changed or root_pct >= args.busy_pct or other_pct >= 0.5:
                target.last_progress = now
                target.defer_until = 0.0
                target.defers.clear()
            previous_state = target.last_status
            state = status_state(discovered.info)
            target.last_status = state
            if state == "working" and previous_state != "working":
                # A new or resumed turn must not inherit a stale idle timer.
                target.last_progress = now
                target.fatal_sig = None
                target.fatal_since = None
                target.frozen_since = None
                target.blocked_since = None
                target.defer_until = 0.0
                target.defers.clear()
            text = pane_text(address, 120)
            effort = EFFORT_RE.search(text)
            if effort:
                target.thinking = effort.group(1)
            if now < target.boot_until:
                continue
            if state == "working":
                target.fatal_sig = None
                target.fatal_since = None
                target.frozen_since = None
                target.blocked_since = None
                if now - target.last_progress >= args.stall:
                    evidence = {
                        "stalled_seconds": int(now - target.last_progress),
                        "turn": next(
                            (
                                row.get("turn")
                                for row in ls_terms()
                                if row.get("address") == address
                            ),
                            None,
                        ),
                        "root_cpu_pct": round(root_pct, 2),
                        "children_cpu_pct": round(other_pct, 2),
                        "processes": pids,
                        "last_event": last_event(target.session),
                        "pane_status": pane_status(text),
                    }
                    gated = gate_action(
                        args, target, "no-progress", evidence, text, now
                    )
                    if gated is not None:
                        actions.append((address, target, "no-progress", gated))
                continue
            if re.search(r"Working \(\d+s", text):
                target.frozen_since = target.frozen_since or now
                if now - target.frozen_since >= args.frozen_grace:
                    evidence = {
                        "frozen_seconds": int(now - target.frozen_since),
                        "state": state,
                        "last_event": last_event(target.session),
                        "pane_status": pane_status(text),
                    }
                    gated = gate_action(
                        args, target, "frozen-working", evidence, text, now
                    )
                    if gated is not None:
                        actions.append((address, target, "frozen-working", gated))
                continue
            target.frozen_since = None
            blocked = pane_blocked(text)
            if blocked:
                target.blocked_since = target.blocked_since or now
                if now - target.blocked_since >= args.blocked_grace:
                    evidence = {
                        "blocked_seconds": int(now - target.blocked_since),
                        "state": state,
                        "blocked": blocked,
                        "last_event": last_event(target.session),
                        "pane_status": pane_status(text),
                    }
                    gated = gate_action(
                        args, target, "blocked-at-prompt", evidence, text, now
                    )
                    if gated is not None:
                        actions.append(
                            (address, target, "blocked-at-prompt", gated)
                        )
                continue
            target.blocked_since = None
            fatal = pane_fatal(text)
            if fatal:
                signature = " | ".join(fatal)
                if signature != target.fatal_sig:
                    target.fatal_sig, target.fatal_since = signature, now
                if now - (target.fatal_since or now) >= args.fatal_grace:
                    evidence = {
                        "fatal": fatal,
                        "last_event": last_event(target.session),
                        "pane_status": pane_status(text),
                    }
                    gated = gate_action(
                        args, target, "fatal-at-prompt", evidence, text, now
                    )
                    if gated is not None:
                        actions.append(
                            (address, target, "fatal-at-prompt", gated)
                        )
            else:
                target.fatal_sig = None
                target.fatal_since = None
        else:
            target.pid = None
            target.blocked_since = None
            foreground_name = os.path.basename(foreground.get("name") or "")
            if foreground_name in SHELLS or not foreground.get("pid"):
                if target.absent_since is None:
                    target.absent_since = now
                    foreground_cwd = foreground.get("cwd")
                    if foreground_cwd:
                        target.project = foreground_cwd
                target.last_status = "absent"
                if (
                    now - target.absent_since >= args.absent_grace
                    and now >= target.boot_until
                ):
                    if not target.session:
                        session = newest_session(target.project)
                        target.session = session.path if session else None
                    actions.append(
                        (
                            address,
                            target,
                            "omo-absent",
                            {
                                "state": discovered.info.get("state"),
                                "exit_code": discovered.info.get("exit_code"),
                                "foreground": foreground_name or "(none)",
                                "turn": next(
                                    (
                                        row.get("turn")
                                        for row in ls_terms()
                                        if row.get("address") == address
                                    ),
                                    None,
                                ),
                            },
                        )
                    )
            else:
                target.absent_since = None
                target.last_status = foreground_name
    return actions


def pane_status(text: str) -> str:
    """Return the last few visible pane lines for trigger evidence."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return " / ".join(lines[-3:])[-600:]


def recover(
    args: argparse.Namespace,
    addr: str,
    target: Target,
    mode: str,
    evidence: dict[str, Any],
) -> None:
    """Restart omo in ``addr`` and submit the mass-ulw handoff prompt."""
    now = time.time()
    target.recoveries = [stamp for stamp in target.recoveries if now - stamp < 3600]
    if len(target.recoveries) >= args.max_recoveries:
        hold = 3600 - (now - target.recoveries[0]) if target.recoveries else 600
        target.boot_until = max(target.boot_until, now + max(60.0, hold))
        log(f"{addr}: recovery budget exhausted ({args.max_recoveries}/h); backing off")
        return
    target.recoveries.append(now)
    info = get_term(addr) or {}
    foreground = info.get("foreground") or {}
    old_pid = foreground.get("pid") if is_omo(foreground) else None
    evidence["old_pid"] = old_pid
    pane = pane_text(addr, 160)
    errors = recent_errors(target.session)
    if not errors:
        errors = pane_fatal(pane)
    if not errors:
        errors = [fallback_error(mode, evidence)]
    launch = launch_command(args, addr, target, pane)
    expected_cwd = launch_cwd(launch) or target.project
    if mode == "omo-absent":
        current = get_term(addr) or {}
        current_fg = current.get("foreground") or {}
        if is_omo(current_fg):
            log(
                f"{addr}: omo is already back (pid {current_fg.get('pid')}, "
                f"cwd={current_fg.get('cwd')}); skipping absent recovery"
            )
            target.absent_since = None
            target.boot_until = now + 120
            return
    if expected_cwd and not os.path.isdir(expected_cwd):
        log(f"{addr}: launch cwd {expected_cwd} does not exist; recovery aborted")
        target.boot_until = now + 300
        return
    handoff = os.path.join(
        RUNTIME,
        "handoffs",
        f"handoff-{datetime.now(timezone.utc).astimezone().strftime('%Y%m%d-%H%M%S-%f')}.md",
    )
    prompt = build_prompt(
        addr, target, mode, evidence, [error[:900] for error in errors], handoff
    )
    write_handoff(handoff, addr, mode, evidence, pane, prompt)

    if args.dry_run:
        log(
            f"DRY-RUN {addr}: would recover ({mode}); "
            f"handoff={handoff}; launch={launch}"
        )
        return
    log(
        f"RECOVER {addr}: {mode}; old_pid={old_pid}; launch={launch}; handoff={handoff}"
    )
    if old_pid:
        log(f"{addr}: terminated omo tree {kill_tree(old_pid)}")
    if not wait_shell(addr, old_pid):
        log(f"{addr}: pane did not return to a shell; recovery aborted")
        target.boot_until = now + 60
        return
    if not send_text(addr, launch):
        try:
            hc(["keys", addr, "ctrl+c"], timeout=10)
        except (subprocess.TimeoutExpired, OSError):
            pass
        time.sleep(0.5)
        if not send_text(addr, launch):
            log(f"{addr}: failed to launch {launch!r}")
            target.boot_until = now + 60
            return
    log(f"{addr}: launched `{launch}`")
    if not wait_omo(addr, args.ready_timeout):
        log(f"{addr}: omo did not become ready")
        target.boot_until = now + 120
        return
    info = get_term(addr) or {}
    actual_fg = info.get("foreground") or {}
    actual_cwd = actual_fg.get("cwd") or ""
    if (
        expected_cwd
        and actual_cwd
        and os.path.realpath(actual_cwd) != os.path.realpath(expected_cwd)
    ):
        log(
            f"{addr}: omo started in {actual_cwd}, expected {expected_cwd}; "
            "handoff aborted"
        )
        target.boot_until = now + 120
        return
    log(f"{addr}: submitting handoff prompt")
    if not send_text(addr, prompt, timeout=120):
        try:
            hc(["keys", addr, "enter"], timeout=10)
        except (subprocess.TimeoutExpired, OSError):
            pass
    if not turn_started(addr):
        try:
            hc(["keys", addr, "enter"], timeout=10)
        except (subprocess.TimeoutExpired, OSError):
            pass
        if not turn_started(addr, 60):
            log(f"{addr}: handoff prompt did not start a turn")
            target.boot_until = now + 300
            return
    log(f"{addr}: RECOVER done; handoff turn started")
    target.last_progress = time.time()
    target.boot_until = time.time() + 120
    target.pid = None
    target.session = None
    target.cpu = None
    target.fingerprint = None
    target.fatal_sig = None
    target.fatal_since = None
    target.frozen_since = None
    target.blocked_since = None
    target.defer_until = 0.0
    target.defers.clear()


def select(
    args: argparse.Namespace, targets: dict[str, DiscoveredTerminal]
) -> dict[str, DiscoveredTerminal]:
    """Return the addresses the caller named; a forced recovery must not fan out."""
    panes = set(args.pane)
    return {
        address: discovered
        for address, discovered in targets.items()
        if (not panes or address in panes)
        and (not args.name or discovered.name == args.name)
    }


def run(args: argparse.Namespace) -> int:
    """Run the watch loop (or a single forced recovery) until interrupted."""
    try:
        os.makedirs(RUNTIME, mode=0o700, exist_ok=True)
        if os.stat(RUNTIME).st_uid != os.getuid():
            print(f"{RUNTIME} is not owned by uid {os.getuid()}", file=sys.stderr)
            return 1
        os.chmod(RUNTIME, 0o700)
    except OSError as exc:
        print(f"cannot use runtime dir {RUNTIME}: {exc}", file=sys.stderr)
        return 1
    lock_path = os.path.join(RUNTIME, "lock-dry" if args.dry_run else "lock")
    with open(lock_path, "a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"another omo-watch holds {lock_path}", file=sys.stderr)
            return 1
        lock.seek(0)
        lock.truncate()
        lock.write(f"{os.getpid()}\n")
        lock.flush()
        log(
            f"watchdog start: pane={args.pane or '-'} name={args.name or '-'} "
            f"project={args.project or '-'} poll={args.poll} stall={args.stall} "
            f"context={args.context_grace}s/{args.context_max_defers} "
            f"dry_run={args.dry_run}"
        )
        states: dict[str, Target] = {}
        if args.force:
            if not args.pane and not args.name:
                log("--force requires --pane or --name; refusing to recover every omo")
                return 1
            targets = select(args, discover(args, states))
            log(f"--force selected: {', '.join(sorted(targets)) or '(none)'}")
            if not targets:
                log("--force: no matching target")
            for address, discovered in targets.items():
                target = ensure_target(args, states, address, discovered)
                if target is None:
                    continue
                if not target.session:
                    session = newest_session(
                        target.project, claimed_sessions(states, address)
                    )
                    target.session = session.path if session else None
                recover(args, address, target, "forced", {"reason": "--force"})
            if args.once:
                return 0
        last_beat = time.time()
        paused = False
        while True:
            if os.path.exists(os.path.join(RUNTIME, "paused")):
                paused = True
                if time.time() - last_beat >= 300:
                    last_beat = time.time()
                    log("paused (remove paused file to resume)")
                time.sleep(args.poll)
                continue
            if paused:
                paused = False
                resume_at = time.time()
                for target in states.values():
                    target.last_progress = resume_at
                    target.absent_since = None
                    target.fatal_sig = None
                    target.fatal_since = None
                    target.frozen_since = None
                    target.blocked_since = None
                    target.defer_until = 0.0
                    target.defers.clear()
                    target.cpu = None
                    target.boot_until = max(
                        target.boot_until, resume_at + args.absent_grace
                    )
                log(f"resumed: {len(states)} target(s) re-armed")
            try:
                actions = evaluate(args, states, time.time())
            except Exception as exc:  # noqa: BLE001 - one bad target must not stop the watch
                log(f"evaluate error: {exc!r}")
                actions = []
            for address, target, mode, evidence in actions:
                log(
                    f"TRIGGER {address} {mode}: "
                    f"{json.dumps(evidence, ensure_ascii=False)[:500]}"
                )
                try:
                    recover(args, address, target, mode, evidence)
                except Exception as exc:  # noqa: BLE001 - keep watching other targets
                    log(f"recover error ({address}): {exc!r}")
            if time.time() - last_beat >= 600:
                last_beat = time.time()
                summary = (
                    ", ".join(
                        f"{address}:{target.last_status or '?'}"
                        for address, target in states.items()
                    )
                    or "none"
                )
                log(f"heartbeat: {summary}")
            if args.once:
                return 0
            time.sleep(args.poll)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Parse command-line options."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument(
        "--pane",
        action="append",
        default=[],
        metavar="ADDR",
        help="fallback pane address to keep alive",
    )
    parser.add_argument("--name", help="only omo terminals with this hc name")
    parser.add_argument(
        "--project", help="only targets whose foreground cwd is this project"
    )
    parser.add_argument("--poll", type=float, default=15)
    parser.add_argument(
        "--stall", type=float, default=900, help="working turn with no progress"
    )
    parser.add_argument("--absent-grace", type=float, default=30)
    parser.add_argument("--fatal-grace", type=float, default=300)
    parser.add_argument("--frozen-grace", type=float, default=600)
    parser.add_argument("--blocked-grace", type=float, default=600)
    parser.add_argument(
        "--context-grace",
        type=float,
        default=180,
        help="extra wait when the pane shows active work or a scheduled wake",
    )
    parser.add_argument(
        "--context-max-wait", type=float, default=1800, help="cap for one deferral"
    )
    parser.add_argument(
        "--context-max-defers",
        type=int,
        default=3,
        help="context deferrals allowed per trigger before recovering",
    )
    parser.add_argument("--busy-pct", type=float, default=2.0)
    parser.add_argument("--max-recoveries", type=int, default=3)
    parser.add_argument("--ready-timeout", type=float, default=120)
    parser.add_argument("--launch", default="omo", help=(
        "restart command for the panes named by --pane/--name; other panes "
        "restart with `cd <project> && omo --thinking <footer level>`"
    ))
    parser.add_argument(
        "--launch-pane",
        action="append",
        default=[],
        metavar="ADDR=CMD",
        help="restart command for one pane address (repeatable)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recover only the --pane/--name targets now",
    )
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    overrides: dict[str, str] = {}
    for pair in args.launch_pane:
        addr, sep, command = pair.partition("=")
        if not sep or not addr.strip() or not command.strip():
            parser.error(f"--launch-pane expects ADDR=CMD, got {pair!r}")
        overrides[addr.strip()] = command.strip()
    args.launch_pane = overrides
    return args


def main(argv: Sequence[str]) -> int:
    """Entry point."""
    return run(parse_args(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
