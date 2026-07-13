#!/usr/bin/env python3
"""Emit cached Git diff metrics for the Starship prompt.

The prompt path must stay cheap. This helper therefore returns the last cached
snapshot immediately and refreshes the cache asynchronously when it is stale.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Optional


TTL_SECONDS = 2
LOCK_STALE_SECONDS = 30
CACHE_BASE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "starship" / "git-metrics"
VALID_FIELDS = frozenset({"added", "deleted", "status", "summary"})

GREEN_RGB = os.environ.get("CTP_GREEN_RGB", "166;227;161")
RED_RGB = os.environ.get("CTP_RED_RGB", "243;139;168")
PEACH_RGB = os.environ.get("CTP_PEACH_RGB", "250;179;135")


@dataclass(frozen=True)
class GitSnapshot:
    """Small cached payload rendered by the prompt."""

    updated_at: int
    head: str
    index_signature: str
    status_symbols: str
    added: int
    deleted: int

    @classmethod
    def from_repo(cls, cwd: Path) -> Optional["GitSnapshot"]:
        """Collect a fresh snapshot for the repository containing ``cwd``."""
        try:
            repo_root = Path(git_stdout(["rev-parse", "--show-toplevel"], cwd))
            git_dir = resolve_git_dir(repo_root)
        except subprocess.CalledProcessError:
            return None

        try:
            head = git_stdout(["rev-parse", "--verify", "HEAD"], repo_root)
        except subprocess.CalledProcessError:
            head = "none"

        status_lines = git_stdout(
            ["status", "--porcelain=v2", "--branch", "--ignore-submodules=dirty", "--untracked-files=no"],
            repo_root,
            check=False,
        ).splitlines()

        flags = parse_status_lines(status_lines)
        if git_stdout(
            ["ls-files", "--others", "--exclude-standard", "--directory", "--no-empty-directory"],
            repo_root,
            check=False,
        ):
            flags.dirty = True

        if git_succeeds(["rev-parse", "--verify", "--quiet", "refs/stash"], repo_root):
            flags.stashed = True

        added, deleted = diff_totals(repo_root) if flags.has_changes else (0, 0)
        return cls(
            updated_at=int(time.time()),
            head=head,
            index_signature=stat_signature(git_dir / "index"),
            status_symbols=flags.symbols(),
            added=added,
            deleted=deleted,
        )

    @classmethod
    def from_cache(cls, cache_file: Path) -> Optional["GitSnapshot"]:
        """Load a snapshot from a JSON cache file."""
        try:
            with cache_file.open() as handle:
                payload = json.load(handle)
            return cls(
                updated_at=int(payload.get("updated_at", 0)),
                head=str(payload.get("head", "none")),
                index_signature=str(payload.get("index_signature", "missing")),
                status_symbols=str(payload.get("status_symbols", "")),
                added=int(payload.get("added", 0)),
                deleted=int(payload.get("deleted", 0)),
            )
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            return None

    def write(self, cache_file: Path) -> None:
        """Persist the snapshot atomically."""
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        tmp_file = cache_file.with_suffix(f"{cache_file.suffix}.tmp.{os.getpid()}")
        with tmp_file.open("w") as handle:
            json.dump(asdict(self), handle, separators=(",", ":"))
        tmp_file.replace(cache_file)


@dataclass
class StatusFlags:
    """Mutable accumulator for porcelain-v2 status parsing."""

    has_changes: bool = False
    staged: bool = False
    dirty: bool = False
    renamed: bool = False
    deleted_files: bool = False
    stashed: bool = False
    ahead: int = 0
    behind: int = 0

    def symbols(self) -> str:
        """Render prompt symbols in the existing visual order."""
        parts = []
        if self.dirty:
            parts.append("*")
        if self.staged:
            parts.append("+")
        if self.renamed:
            parts.append("»")
        if self.deleted_files:
            parts.append("✘")
        if self.stashed:
            parts.append("≡")
        if self.ahead > 0 and self.behind > 0:
            parts.append("⇕")
        elif self.ahead > 0:
            parts.append("⇡")
        elif self.behind > 0:
            parts.append("⇣")
        return "".join(parts)


def stat_signature(path: Path) -> str:
    """Return a stable mtime:size signature for cache invalidation."""
    if not path.exists():
        return "missing"
    stat_result = path.stat()
    return f"{int(stat_result.st_mtime)}:{stat_result.st_size}"


def git_stdout(args: Iterable[str], cwd: Path, check: bool = True) -> str:
    """Run ``git`` and return stripped stdout."""
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=check,
    )
    return result.stdout.strip()


def git_succeeds(args: Iterable[str], cwd: Path) -> bool:
    """Return ``True`` when ``git`` exits successfully."""
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def resolve_git_dir(repo_root: Path) -> Path:
    """Resolve ``.git`` to an absolute path."""
    git_dir = Path(git_stdout(["rev-parse", "--git-dir"], repo_root))
    return git_dir if git_dir.is_absolute() else repo_root / git_dir


def parse_status_lines(lines: Iterable[str]) -> StatusFlags:
    """Parse porcelain-v2 output into prompt-relevant flags."""
    flags = StatusFlags()
    for line in lines:
        if line.startswith("# branch.ab "):
            parts = line.split()
            if len(parts) >= 4:
                flags.ahead = int(parts[2].lstrip("+"))
                flags.behind = int(parts[3].lstrip("-"))
            continue

        if line.startswith("u "):
            flags.has_changes = True
            flags.dirty = True
            continue

        if not (line.startswith("1 ") or line.startswith("2 ")):
            continue

        parts = line.split(maxsplit=2)
        if len(parts) < 2 or len(parts[1]) < 2:
            continue

        xy = parts[1]
        flags.has_changes = True

        staged_code, worktree_code = xy[0], xy[1]
        if staged_code != ".":
            flags.staged = True
            flags.renamed = flags.renamed or staged_code == "R"
            flags.deleted_files = flags.deleted_files or staged_code == "D"
        if worktree_code != ".":
            flags.dirty = True
            flags.renamed = flags.renamed or worktree_code == "R"
            flags.deleted_files = flags.deleted_files or worktree_code == "D"
        if "T" in xy:
            flags.dirty = True

    return flags


def diff_totals(repo_root: Path) -> tuple[int, int]:
    """Aggregate ``git diff --numstat HEAD --`` into added/deleted totals."""
    added = 0
    deleted = 0
    output = git_stdout(["diff", "--numstat", "HEAD", "--"], repo_root, check=False)
    for line in output.splitlines():
        parts = line.split("\t", 2)
        if len(parts) < 2:
            continue
        add_count, delete_count = parts[0], parts[1]
        if add_count.isdigit():
            added += int(add_count)
        if delete_count.isdigit():
            deleted += int(delete_count)
    return added, deleted


def emit_field(field: str, snapshot: Optional[GitSnapshot]) -> int:
    """Write the requested field to stdout."""
    if snapshot is None:
        return 0

    if field == "added":
        if snapshot.added > 0:
            sys.stdout.write(f" +{snapshot.added}")
        return 0

    if field == "deleted":
        if snapshot.deleted > 0:
            sys.stdout.write(f" -{snapshot.deleted}")
        return 0

    if field == "status":
        if snapshot.status_symbols:
            sys.stdout.write(f" {snapshot.status_symbols}")
        return 0

    # Keep each segment independent so absent fields do not leave stray spacing.
    if snapshot.added > 0:
        sys.stdout.write(f"\033[1;38;2;{GREEN_RGB}m +{snapshot.added}\033[0m")
    if snapshot.deleted > 0:
        sys.stdout.write(f"\033[1;38;2;{RED_RGB}m -{snapshot.deleted}\033[0m")
    if snapshot.status_symbols:
        sys.stdout.write(f"\033[1;38;2;{PEACH_RGB}m {snapshot.status_symbols}\033[0m")
    return 0


def refresh_cache(cwd: Path, cache_file: Path, lock_dir: Path) -> int:
    """Refresh the cache if the lock can be acquired."""
    try:
        lock_dir.mkdir()
    except FileExistsError:
        return 0

    try:
        snapshot = GitSnapshot.from_repo(cwd)
        if snapshot is None:
            cache_file.unlink(missing_ok=True)
            return 0
        snapshot.write(cache_file)
        return 0
    finally:
        shutil.rmtree(lock_dir, ignore_errors=True)


def spawn_refresh(cwd: Path, cache_file: Path, lock_dir: Path) -> None:
    """Fire-and-forget refresh to keep prompt latency low."""
    subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--refresh", str(cwd), str(cache_file), str(lock_dir)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )


def maybe_clear_stale_lock(lock_dir: Path, now: int) -> None:
    """Remove abandoned refresh locks."""
    try:
        lock_age = now - int(lock_dir.stat().st_mtime)
    except FileNotFoundError:
        return
    if lock_age >= LOCK_STALE_SECONDS:
        shutil.rmtree(lock_dir, ignore_errors=True)


def cache_paths_for(cwd: Path) -> tuple[Path, Path]:
    """Return cache and lock paths for a working tree."""
    cache_key = hashlib.sha1(str(cwd).encode()).hexdigest()
    return CACHE_BASE / f"{cache_key}.json", CACHE_BASE / f"{cache_key}.json.lock"


def main(argv: list[str]) -> int:
    """CLI entrypoint used by the shell wrapper and background refresh."""
    if len(argv) >= 5 and argv[1] == "--refresh":
        return refresh_cache(Path(argv[2]), Path(argv[3]), Path(argv[4]))

    if len(argv) < 2 or argv[1] not in VALID_FIELDS:
        return 0

    field = argv[1]
    cwd = Path.cwd()
    CACHE_BASE.mkdir(parents=True, exist_ok=True)
    cache_file, lock_dir = cache_paths_for(cwd)

    now = int(time.time())
    snapshot = GitSnapshot.from_cache(cache_file)
    needs_refresh = snapshot is None or now - snapshot.updated_at >= TTL_SECONDS

    maybe_clear_stale_lock(lock_dir, now)
    if needs_refresh and not lock_dir.exists():
        spawn_refresh(cwd, cache_file, lock_dir)

    return emit_field(field, snapshot)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
