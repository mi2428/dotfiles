#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1] / "home/files/config/fish/conf.d/21_functions.fish"
fish = shutil.which("fish")
assert fish, "fish is required"
ipv6 = "2001:4860:4860::8888"
checks = 0

with tempfile.TemporaryDirectory(prefix="ping-shortcuts-") as scratch:
    bin_dir = Path(scratch)
    (bin_dir / "uname").write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_OS"\n')
    (bin_dir / "ping").write_text(
        '#!/bin/sh\nprintf "%s" "${0##*/}"\n'
        'printf "|%s" "$@"\nprintf "\\n"\nexit "$TEST_PING_STATUS"\n'
    )
    for name in ("uname", "ping"):
        (bin_dir / name).chmod(0o755)
    (bin_dir / "ping6").symlink_to("ping")

    for system in ("Linux", "Darwin"):
        for clockping in (False, True):
            optional = bin_dir / "clockping"
            optional.unlink(missing_ok=True)
            if clockping:
                optional.symlink_to("ping")
            env = dict(os.environ, PATH=str(bin_dir), TEST_OS=system, TEST_PING_STATUS="0")
            prefix = "clockping|icmp|--out.colored" if clockping else (
                "ping6" if system == "Darwin" else "ping|-6"
            )
            sweep = [
                f"clockping|icmp|--out.colored|-c|4|-i|0.25|8.8.8.8|{ipv6}",
                "",
                "clockping|http|--out.colored|-c|4|-i|0.25|ipv4.google.com|ipv6.google.com",
            ] if clockping else [
                "ping|-c|4|-i|0.25|8.8.8.8", "", f"{prefix}|-c|4|-i|0.25|{ipv6}",
            ]
            cases = [
                ("pp", [], [f"{prefix}|{ipv6}"]),
                ("pp", ["-c", "1", "::1"], [f"{prefix}|-c|1|::1"]),
                ("pp", ["-I", "an interface", "::1"], [f"{prefix}|-I|an interface|::1"]),
                ("ppp", [], sweep),
            ]
            for name, args, expected in cases:
                result = subprocess.run(
                    [fish, "--no-config", "-c", 'source "$argv[1]"; $argv[2..]',
                     "--", str(source), name, *args],
                    env=env, capture_output=True, text=True, timeout=5,
                )
                assert result.returncode == 0, result.stderr
                assert result.stdout.splitlines() == expected, (system, clockping, name, result.stdout, expected)
                checks += 1
            env["TEST_PING_STATUS"] = "7"
            for name in ("pp", "ppp"):
                result = subprocess.run(
                    [fish, "--no-config", "-c", 'source "$argv[1]"; $argv[2..]',
                     "--", str(source), name],
                    env=env, capture_output=True, text=True, timeout=5,
                )
                assert result.returncode == 7, (system, clockping, name, result.returncode, result.stderr)
                checks += 1

print(f"ping shortcut tests: {checks} checks passed")
