#!/usr/bin/env python3
"""Offline regression check for the upstream font installation wrapper."""

import os
import subprocess
import tempfile
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory)
        tools = scratch / "bin"
        tools.mkdir()
        stubs = {
            "uname": 'printf "%s\\n" "$TEST_OS"',
            "uv": "exit 0",
            "fc-cache": 'printf "fc-cache %s\\n" "$*" >> "$FONT_TEST_LOG"',
            "git": """
case "$1" in
  clone) for last do :; done; mkdir -p "$last" ;;
  -C) case "$3" in
    rev-parse) printf '%s\\n' "${GIT_REVISION:-622be738651660cf1851c619c92bd813d97c6dbd}" ;;
    status)
      if [ "${GIT_STATUS_FAIL:-0}" = 1 ]; then exit 2; fi
      if [ "${GIT_DIRTY:-0}" = 1 ]; then printf ' M Makefile\\n'; fi ;;
  esac ;;
esac
""",
            "make": """
printf 'make %s\\n' "$*" >> "$FONT_TEST_LOG"
case "$*" in *' check') if [ "${FAIL_BUILD:-0}" = 1 ]; then exit 1; fi ;; esac
""",
        }
        for name, content in stubs.items():
            tool = tools / name
            tool.write_text("#!/bin/sh\nset -eu\n" + content + "\n")
            tool.chmod(0o755)
        log = scratch / "font.log"
        env = dict(
            os.environ,
            PATH=f"{tools}:{os.environ['PATH']}",
            HOME=str(scratch / "home"),
            XDG_CACHE_HOME=str(scratch / "cache"),
            XDG_DATA_HOME=str(scratch / "data"),
            FONT_TEST_LOG=str(log),
        )
        for platform in ("Linux", "Darwin"):
            log.write_text("")
            subprocess.run(
                ["bash", str(root / "scripts/install-summer-ghost.sh")],
                env=dict(env, TEST_OS=platform),
                check=True,
                stdout=subprocess.DEVNULL,
            )
            expected = scratch / (
                "data/fonts/SummerGhost"
                if platform == "Linux"
                else "home/Library/Fonts/SummerGhost"
            )
            lines = log.read_text().splitlines()
            assert lines[0].endswith(" check")
            assert f" install FONTDIR={expected}" in lines[1]
            assert any(line.startswith("fc-cache ") for line in lines) == (
                platform == "Linux"
            )
        for flag in ("FAIL_BUILD", "GIT_DIRTY", "GIT_REVISION", "GIT_STATUS_FAIL"):
            log.write_text("")
            result = subprocess.run(
                ["bash", str(root / "scripts/install-summer-ghost.sh")],
                env=dict(env, TEST_OS="Linux", **{flag: "1"}),
                capture_output=True,
                check=False,
            )
            assert result.returncode != 0
            assert " install " not in log.read_text()
    print("Summer Ghost installation: ok")


if __name__ == "__main__":
    main()
