#!/usr/bin/env python3
"""Report one progress line per interval for a watched omo pane.

The supervising agent runs this next to ``watch.py`` as a second background
service: each stdout line starts with ``REPORT`` so the omp notification regex
delivers it, and the agent turns it into a short chat summary.  That cadence is
the watchdog's reporting duty; ``watch.py`` only logs a heartbeat.

Facts only: herdr state/pid, footer context and effort, session JSONL growth,
running DAG wave, active item and age, goal state, Now/Next intent, and the
watcher's last log line.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from collections.abc import Sequence
from typing import Any

HOME = os.path.expanduser("~")
XDG_RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/omo-watch-{os.getuid()}"
RUNTIME = os.environ.get("OMO_WATCH_RUNTIME") or os.path.join(XDG_RUNTIME, "omo-watch")
HC_ENV = dict(os.environ)
HC_ENV.pop("HC_TERMINAL_ID", None)
CTX_RE = re.compile(r"(\d+K/1M)\s*\(([\d.]+%)\)")
EFFORT_RE = re.compile(r"effort\s+(\w+)")
DAG_RE = re.compile(r"(\d+)/(\d+)\s+done,\s*(\d+)\s+running")
ACTIVE_RE = re.compile(r"^\s*[▶⏵⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]\s+(\S+)\s*·")
AGE_RE = re.compile(r"·\s*((?:\d+m\s*)?\d+s)\s*$")
INTENT_RE = re.compile(r"^\s*(Now|Next)\s*:\s*(.+)$")
GOAL_RE = re.compile(r"(Pursuing goal[^·]*|Goal blocked[^·]*|goal continues in[^·]*)")


def hc(*args: str, timeout: float = 20) -> str:
    """Run herdr-core's CLI and return stdout on success."""
    try:
        proc = subprocess.run(
            ["hc", *args], capture_output=True, text=True, timeout=timeout, env=HC_ENV
        )
    except (subprocess.TimeoutExpired, OSError):
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def term(addr: str) -> dict[str, Any]:
    """Return the pane's herdr state, foreground pid, and project cwd."""
    try:
        raw = json.loads(hc("get", addr, "--json") or "{}")
    except json.JSONDecodeError:
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    status = raw.get("status")
    state = status if isinstance(status, str) else (status or {}).get("state") or "?"
    foreground = raw.get("foreground") or {}
    pid = foreground.get("pid")
    name = os.path.basename(foreground.get("name") or "")
    return {
        "state": str(state),
        "pid": f"{name}:{pid}" if pid else "-",
        "cwd": str(foreground.get("cwd") or raw.get("cwd") or ""),
    }


def session_dir(project: str) -> str:
    """Map a project directory to omo's per-project session directory."""
    slug = "--" + project.strip("/").replace("/", "-") + "--"
    return os.path.join(HOME, ".omo/agent/sessions", slug)


def session_size(project: str) -> int | None:
    """Return the newest session JSONL's size for the project."""
    directory = session_dir(project) if project else ""
    try:
        names = [name for name in os.listdir(directory) if name.endswith(".jsonl")]
    except OSError:
        return None
    if not names:
        return None
    path = max(
        (os.path.join(directory, name) for name in names), key=os.path.getmtime
    )
    try:
        return os.stat(path).st_size
    except OSError:
        return None


def parse_pane(text: str) -> dict[str, str]:
    """Extract the progress facts shown in a pane tail."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    facts: dict[str, str] = {}
    for line in reversed(lines):
        match = CTX_RE.search(line)
        if match:
            facts["ctx"] = f"{match.group(1)}({match.group(2)})"
            effort = EFFORT_RE.search(line)
            if effort:
                facts["effort"] = effort.group(1)
            break
    for line in reversed(lines):
        match = DAG_RE.search(line)
        if match:
            facts["dag"] = (
                f"{match.group(1)}/{match.group(2)} done,{match.group(3)} running"
            )
            break
    for line in reversed(lines):
        if not ACTIVE_RE.match(line):
            continue
        name = ACTIVE_RE.match(line).group(1)  # type: ignore[union-attr]
        age = AGE_RE.search(line)
        facts["active"] = f"{name} {age.group(1)}" if age else name
        break
    for line in reversed(lines):
        match = GOAL_RE.search(line)
        if match:
            facts["goal"] = match.group(1).strip()[:80]
            break
    for line in reversed(lines):
        match = INTENT_RE.match(line)
        if not match:
            continue
        facts.setdefault(f"intent_{match.group(1).lower()}", match.group(2)[:80])
        if "intent_now" in facts and "intent_next" in facts:
            break
    return facts


def render(
    addr: str,
    term_facts: dict[str, Any],
    facts: dict[str, str],
    growth: str,
    watch_line: str,
) -> str:
    """Build the single REPORT line delivered to the supervising agent."""
    bits = [f"REPORT {time.strftime('%H:%M:%S')}", f"pane={addr}"]
    bits.append(f"state={term_facts.get('state', '?')}")
    if term_facts.get("pid") not in (None, "-"):
        bits.append(f"pid={term_facts['pid']}")
    ctx = facts.get("ctx", "")
    if ctx:
        effort = facts.get("effort")
        bits.append(f"ctx={ctx}" + (f" effort={effort}" if effort else ""))
    if growth:
        bits.append(f"session={growth}")
    for key in ("dag", "active", "goal"):
        if facts.get(key):
            bits.append(f"{key}={facts[key]}")
    for key in ("intent_now", "intent_next"):
        if facts.get(key):
            bits.append(f"{key[7:]}={facts[key]}")
    bits.append(f"watch={watch_line}")
    return " | ".join(bits)[:700]


def last_watch_line(runtime: str) -> str:
    """Return the watcher's newest log line, trimmed for one-line output."""
    try:
        with open(os.path.join(runtime, "watch.log"), encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return "watch-log-missing"
    return lines[-1].split("] ", 1)[-1][:110] if lines else "watch-log-empty"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Parse command-line options."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--pane", required=True, metavar="ADDR", help="pane to report on")
    parser.add_argument(
        "--project",
        help="project dir for the session file (default: the pane's foreground cwd)",
    )
    parser.add_argument("--interval", type=float, default=600, help="seconds per report")
    parser.add_argument(
        "--runtime",
        default=RUNTIME,
        help="omo-watch state root, for the watcher's last log line",
    )
    parser.add_argument("--once", action="store_true", help="print one report and exit")
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    """Emit one REPORT line per interval until interrupted."""
    args = parse_args(argv)
    os.makedirs(args.runtime, mode=0o700, exist_ok=True)
    lock_path = os.path.join(args.runtime, "report.lock")
    with open(lock_path, "a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"another reporter holds {lock_path}", file=sys.stderr)
            return 1
        previous_size: int | None = None
        previous_time = time.time()
        while True:
            now = time.time()
            info = term(args.pane)
            project = args.project or info["cwd"]
            facts = parse_pane(hc("read", args.pane, "--lines", "80"))
            size = session_size(project)
            growth = ""
            if size is not None and previous_size is not None:
                growth = f"{size - previous_size:+d}B/{int(now - previous_time)}s"
            if size is not None:
                previous_size = size
            previous_time = now
            print(
                render(
                    args.pane,
                    info,
                    facts,
                    growth,
                    last_watch_line(args.runtime),
                ),
                flush=True,
            )
            if args.once:
                return 0
            time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
