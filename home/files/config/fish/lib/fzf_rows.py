#!/usr/bin/env python3
"""Build colourized fzf rows without changing the value returned by fzf.

The first whitespace-delimited field is a base64-encoded value.  fzf displays
only fields 2.. and accepts field 1, so ANSI escapes are never part of the
value consumed by callers.  This also avoids using ANSI bytes in any width or
alignment calculation.
"""

from __future__ import annotations

import base64
import os
import re
import shutil
import stat
import subprocess
import sys
import time


def catppuccin_rgb(name: str, fallback: bytes) -> bytes:
    """Read the active Fish flavour, falling back to Catppuccin Mocha."""
    rgb = os.environ.get(f"CTP_{name}_RGB")
    if rgb:
        return rgb.encode()
    hex_color = os.environ.get(f"CTP_{name}", "")
    if re.fullmatch(r"#[0-9a-fA-F]{6}", hex_color):
        return ";".join(
            str(int(hex_color[index : index + 2], 16)) for index in (1, 3, 5)
        ).encode()
    return fallback


LAVENDER = catppuccin_rgb("LAVENDER", b"180;190;254")
BLUE = catppuccin_rgb("BLUE", b"137;180;250")
GREEN = catppuccin_rgb("GREEN", b"166;227;161")
MAUVE = catppuccin_rgb("MAUVE", b"203;166;247")
PEACH = catppuccin_rgb("PEACH", b"250;179;135")
RED = catppuccin_rgb("RED", b"243;139;168")
YELLOW = catppuccin_rgb("YELLOW", b"249;226;175")
OVERLAY = catppuccin_rgb("OVERLAY0", b"147;153;178")
RESET = b"\x1b[0m"
HISTORY_PREFIX = re.compile(rb"^([^\n]*? \xe2\x94\x82 )")


def color(text: bytes, rgb: bytes, *, bold: bool = False) -> bytes:
    weight = b"1;" if bold else b""
    return b"\x1b[" + weight + b"38;2;" + rgb + b"m" + text + RESET


def bullet() -> bytes:
    return color("●".encode(), LAVENDER, bold=True) + b"  "


def emit(raw: bytes, display: bytes, terminator: bytes = b"\n") -> None:
    encoded = base64.b64encode(raw)
    sys.stdout.buffer.write(encoded + b" " + display + terminator)
    sys.stdout.buffer.flush()


def simple_display(raw: bytes) -> bytes:
    return bullet() + raw


def image_display(raw: bytes) -> bytes:
    repository, separator, tag = raw.rpartition(b":")
    if not separator or not repository or not tag:
        return simple_display(raw)
    return (
        bullet()
        + color(repository, LAVENDER, bold=True)
        + color(separator, OVERLAY)
        + color(tag, PEACH)
    )


def process_display(raw: bytes) -> bytes:
    fields = raw.split(None, 7)
    if len(fields) < 2:
        return simple_display(raw)
    leading = color(fields[0], BLUE) + b"  " + color(fields[1], LAVENDER, bold=True)
    if len(fields) == 2:
        return bullet() + leading
    return bullet() + leading + b"  " + b" ".join(fields[2:])


def relative_time(timestamp: float) -> bytes:
    """Use a compact, eza-like age for a directory's last modification."""
    seconds = max(0, int(time.time() - timestamp))
    units = (
        (365 * 24 * 60 * 60, "year"),
        (30 * 24 * 60 * 60, "month"),
        (24 * 60 * 60, "day"),
        (60 * 60, "hour"),
        (60, "min"),
    )
    for unit_seconds, label in units:
        if seconds >= unit_seconds:
            value = seconds // unit_seconds
            suffix = "" if value == 1 else "s"
            return f"{value} {label}{suffix}".encode()
    return b"now"


def zoxide_parts(raw: bytes) -> tuple[bytes, bytes]:
    """Split zoxide's score/path output without breaking paths with spaces."""
    score, separator, path = raw.partition(b"\t")
    if separator:
        return score.strip(), path
    parts = raw.split(None, 1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return b"", b""


def zoxide_display(raw: bytes) -> bytes:
    """Show score, permissions, modification time, and path for zoxide."""
    score, path = zoxide_parts(raw)
    if not score or not path:
        return simple_display(raw)

    try:
        metadata = os.stat(path)
        permissions = stat.filemode(metadata.st_mode).encode()
        updated = relative_time(metadata.st_mtime)
    except OSError:
        permissions = b"??????????"
        updated = b"unavailable"

    return b"  ".join(
        (
            color(score.rjust(6), MAUVE, bold=True),
            color(permissions, OVERLAY),
            color(updated.rjust(10), YELLOW),
            color(path, BLUE, bold=True),
        )
    )


def emit_zoxide(raw: bytes) -> None:
    """Emit an fzf row whose first whitespace field is the raw entry."""
    encoded = base64.b64encode(raw)
    sys.stdout.buffer.write(encoded + b" " + zoxide_display(raw) + b"\n")
    sys.stdout.buffer.flush()


def preview_zoxide(encoded: str) -> None:
    """Render the selected zoxide directory with the configured eza theme."""
    try:
        raw = base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        raise SystemExit("fzf_rows.py: invalid zoxide preview value") from exc

    _, path = zoxide_parts(raw)
    if not path:
        raise SystemExit("fzf_rows.py: invalid zoxide row")

    eza = shutil.which("eza")
    if eza is None:
        raise SystemExit("zi: eza is not installed")

    env = os.environ.copy()
    for name in ("NO_COLOR", "LS_COLORS", "EXA_COLORS", "EZA_COLORS"):
        env.pop(name, None)

    command = [
        eza,
        "--icons=always",
        "--group-directories-first",
        "--color=always",
        "--hyperlink=never",
    ]
    if columns := env.get("FZF_PREVIEW_COLUMNS"):
        command.extend(("--width", columns))
    command.append(os.fsdecode(path))
    raise SystemExit(subprocess.run(command, env=env, check=False).returncode)


def status_color(code: bytes) -> bytes:
    if code == b"??":
        return YELLOW
    if b"D" in code:
        return RED
    if b"A" in code:
        return GREEN
    if b"R" in code or b"C" in code:
        return BLUE
    if b"M" in code:
        return PEACH
    return LAVENDER


def emit_git_status(data: bytes) -> None:
    records = data.split(b"\0")
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue

        # porcelain v1 -z: XY<space>PATH<NUL>; renames/copies have one extra
        # source-path record.  The first path is the current path to stage.
        if len(record) < 3 or record[2:3] != b" ":
            emit(record, simple_display(record))
            continue

        code = record[:2]
        path = record[3:]
        if (b"R" in code or b"C" in code) and index < len(records):
            index += 1

        display = color(code, status_color(code), bold=True) + b"  " + path
        emit(path, display)


def emit_history_display(data: bytes) -> None:
    """Render NUL-delimited history directly.

    fzf 0.74 mishandles the first ESC sequence when --read0 is combined with
    --with-nth, so history deliberately does not use the encoded-field layout.
    There is no width calculation here, and fzf removes ANSI sequences from the
    accepted value before Fish removes the timestamp prefix.
    """
    for entry in data.split(b"\0"):
        if not entry:
            continue
        match = HISTORY_PREFIX.match(entry)
        if match is None:
            sys.stdout.buffer.write(entry + b"\0")
            continue
        prefix = match.group(1)
        sys.stdout.buffer.write(
            color(prefix, LAVENDER, bold=True) + entry[match.end() :] + b"\0"
        )


def emit_lines(mode: str) -> None:
    display_for = {
        "simple": simple_display,
        "path": simple_display,
        "image": image_display,
        "process": process_display,
    }.get(mode)
    if display_for is None:
        raise SystemExit(f"fzf_rows.py: unsupported encode mode: {mode}")

    # Keep path and process pickers streaming.  In particular, zz searches /
    # by default; reading stdin to EOF here would make fzf appear not to open
    # until fd had finished traversing the entire filesystem.
    for raw in sys.stdin.buffer:
        raw = raw.rstrip(b"\r\n")
        if raw:
            emit(raw, display_for(raw))


def decode(data: bytes, terminator: bytes) -> None:
    for record in data.split(terminator):
        if not record:
            continue
        encoded = record.split(None, 1)[0]
        try:
            raw = base64.b64decode(encoded, validate=True)
        except ValueError as exc:
            raise SystemExit("fzf_rows.py: invalid selected value") from exc
        sys.stdout.buffer.write(raw + terminator)


def decode_zoxide(data: bytes) -> None:
    for record in data.split(b"\n"):
        if not record:
            continue
        encoded = record.split(None, 1)[0]
        try:
            raw = base64.b64decode(encoded, validate=True)
        except ValueError as exc:
            raise SystemExit("fzf_rows.py: invalid selected zoxide value") from exc
        _, path = zoxide_parts(raw)
        if not path:
            raise SystemExit("fzf_rows.py: invalid zoxide row")
        sys.stdout.buffer.write(path + b"\n")


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "preview-zoxide":
        preview_zoxide(sys.argv[2])
        return

    if len(sys.argv) != 2:
        raise SystemExit(
            "usage: fzf_rows.py <simple|path|image|process|zoxide|git-status|history-display|decode|decode-zoxide>"
        )

    mode = sys.argv[1]

    if mode in {"simple", "path", "image", "process"}:
        emit_lines(mode)
        return

    if mode == "zoxide":
        for raw in sys.stdin.buffer:
            raw = raw.rstrip(b"\r\n")
            if raw:
                emit_zoxide(raw)
        return

    data = sys.stdin.buffer.read()
    if mode == "git-status":
        emit_git_status(data)
    elif mode == "history-display":
        emit_history_display(data)
    elif mode == "decode":
        decode(data, b"\n")
    elif mode == "decode-zoxide":
        decode_zoxide(data)
    else:
        raise SystemExit(f"fzf_rows.py: unsupported mode: {mode}")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # fzf may exit while a streaming source (fd, ps, etc.) is still
        # producing rows.  Do not leak a traceback to the terminal; replacing
        # stdout also prevents Python from raising again during final flush.
        try:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            os.close(devnull)
        except OSError:
            pass
        raise SystemExit(0)
