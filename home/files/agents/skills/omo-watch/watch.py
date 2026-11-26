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
"""

from __future__ import annotations

import argparse
import fcntl
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timezone
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
RUNTIME = os.environ.get("OMO_WATCH_RUNTIME") or os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/omo-watch-{os.getuid()}", "omo-watch"
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
            del states[address]
    actions: list[Action] = []
    for address, discovered in seen.items():
        target = states.get(address)
        if target is None:
            target = Target(address, discovered.project, discovered.name)
            states[address] = target
            log(
                f"{address}: watching (project={discovered.project}, "
                f"name={discovered.name})"
            )
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
                log(f"{address}: omo pid {pid} session={target.session}")
            current_fingerprint = fingerprint(target)
            changed = current_fingerprint != target.fingerprint
            target.fingerprint = current_fingerprint
            root_pct, other_pct, pids = cpu_activity(target, pid)
            if changed or root_pct >= args.busy_pct or other_pct >= 0.5:
                target.last_progress = now
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
                    actions.append(
                        (
                            address,
                            target,
                            "no-progress",
                            {
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
                            },
                        )
                    )
                continue
            if re.search(r"Working \(\d+s", text):
                target.frozen_since = target.frozen_since or now
                if now - target.frozen_since >= args.frozen_grace:
                    actions.append(
                        (
                            address,
                            target,
                            "frozen-working",
                            {
                                "frozen_seconds": int(now - target.frozen_since),
                                "state": state,
                                "last_event": last_event(target.session),
                                "pane_status": pane_status(text),
                            },
                        )
                    )
                continue
            target.frozen_since = None
            blocked = pane_blocked(text)
            if blocked:
                target.blocked_since = target.blocked_since or now
                if now - target.blocked_since >= args.blocked_grace:
                    actions.append(
                        (
                            address,
                            target,
                            "blocked-at-prompt",
                            {
                                "blocked_seconds": int(now - target.blocked_since),
                                "state": state,
                                "blocked": blocked,
                                "last_event": last_event(target.session),
                                "pane_status": pane_status(text),
                            },
                        )
                    )
                continue
            target.blocked_since = None
            fatal = pane_fatal(text)
            if fatal:
                signature = " | ".join(fatal)
                if signature != target.fatal_sig:
                    target.fatal_sig, target.fatal_since = signature, now
                if now - (target.fatal_since or now) >= args.fatal_grace:
                    actions.append(
                        (
                            address,
                            target,
                            "fatal-at-prompt",
                            {
                                "fatal": fatal,
                                "last_event": last_event(target.session),
                                "pane_status": pane_status(text),
                            },
                        )
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
    launch = args.launch
    if launch.strip() == "omo":
        effort = EFFORT_RE.search(pane)
        level = effort.group(1) if effort else target.thinking
        if level:
            launch = f"omo --thinking {level}"
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
                target = states.get(address) or Target(
                    address, discovered.project, discovered.name
                )
                states[address] = target
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
    parser.add_argument("--busy-pct", type=float, default=2.0)
    parser.add_argument("--max-recoveries", type=int, default=3)
    parser.add_argument("--ready-timeout", type=float, default=120)
    parser.add_argument("--launch", default="omo", help="command used to start omo")
    parser.add_argument(
        "--force",
        action="store_true",
        help="recover only the --pane/--name targets now",
    )
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    """Entry point."""
    return run(parse_args(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
