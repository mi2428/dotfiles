"""Refresh the cached Git state consumed by the Starship prompt.

The synchronous prompt path lives in ``git-metrics.sh`` and never starts
Python or Git. This process runs detached, consolidates repository state into
one ``git status`` invocation, and atomically publishes a small JSON snapshot.

The original collector launched six Git processes even for a clean repository:
three rev-parse calls for the root, Git directory, and HEAD; one tracked-only
status; one untracked scan; and one stash probe. HEAD and the index signature
were stored but never used for invalidation. A dirty repository added a seventh
numstat process. The current collector obtains tracked state, untracked state,
stash count, and ahead/behind counts from one porcelain-v2 status call. It runs
the numstat diff only when status reports working-tree or index changes.

The cache is deliberately a transport format, not the source of truth. Writes
use a same-directory temporary file followed by an atomic replace, so the Bash
reader observes either the previous complete snapshot or the next complete
snapshot, never partially written JSON. Git failures produce a short-lived
negative entry and the Bash-side TTL schedules another demand-driven attempt.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from collections.abc import Iterable
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class GitSnapshot:
    """Small payload rendered by the prompt's Bash hot path."""

    updated_at: int
    inside_work_tree: bool
    status_symbols: str
    added: int
    deleted: int

    @classmethod
    def outside_work_tree(cls) -> GitSnapshot:
        """Return a negative cache entry for a directory outside Git."""
        return cls(
            updated_at=int(time.time()),
            inside_work_tree=False,
            status_symbols="",
            added=0,
            deleted=0,
        )

    @classmethod
    def from_repo(cls, cwd: Path) -> GitSnapshot:
        """Collect a fresh snapshot for the repository containing ``cwd``."""
        result = subprocess.run(
            [
                "git",
                "--no-optional-locks",
                "status",
                "--porcelain=v2",
                "--branch",
                "--show-stash",
                "--ignore-submodules=dirty",
                "--untracked-files=normal",
            ],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return cls.outside_work_tree()

        flags = parse_status_lines(result.stdout.splitlines())
        added, deleted = diff_totals(cwd) if flags.has_changes else (0, 0)
        return cls(
            updated_at=int(time.time()),
            inside_work_tree=True,
            status_symbols=flags.symbols(),
            added=added,
            deleted=deleted,
        )

    def write(self, cache_file: Path) -> None:
        """Publish this snapshot atomically."""
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        temporary_file = cache_file.with_name(f".{cache_file.name}.{os.getpid()}.tmp")
        try:
            with temporary_file.open("w", encoding="utf-8") as handle:
                json.dump(
                    asdict(self),
                    handle,
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
            temporary_file.replace(cache_file)
        finally:
            temporary_file.unlink(missing_ok=True)


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
        """Render symbols in the existing prompt order."""
        parts: list[str] = []
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


def parse_status_lines(lines: Iterable[str]) -> StatusFlags:
    """Parse the prompt-relevant subset of Git porcelain v2."""
    flags = StatusFlags()
    for line in lines:
        if line.startswith("# branch.ab "):
            parts = line.split()
            if len(parts) >= 4:
                flags.ahead = int(parts[2].removeprefix("+"))
                flags.behind = int(parts[3].removeprefix("-"))
            continue

        if line.startswith("# stash "):
            _, _, stash_count = line.partition("# stash ")
            flags.stashed = stash_count.isdigit() and int(stash_count) > 0
            continue

        if line.startswith("? "):
            flags.has_changes = True
            flags.dirty = True
            continue

        if line.startswith("u "):
            flags.has_changes = True
            flags.dirty = True
            continue

        if not line.startswith(("1 ", "2 ")):
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


def diff_totals(cwd: Path) -> tuple[int, int]:
    """Aggregate ``git diff --numstat HEAD --`` into added/deleted totals."""
    result = subprocess.run(
        ["git", "--no-optional-locks", "diff", "--numstat", "HEAD", "--"],
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    added = 0
    deleted = 0
    for line in result.stdout.splitlines():
        parts = line.split("\t", 2)
        if len(parts) < 2:
            continue
        add_count, delete_count = parts[0], parts[1]
        if add_count.isdigit():
            added += int(add_count)
        if delete_count.isdigit():
            deleted += int(delete_count)
    return added, deleted


def refresh_locked(cwd: Path, cache_file: Path, lock_file: Path) -> int:
    """Refresh a cache whose lock file was acquired by the Bash caller."""
    try:
        GitSnapshot.from_repo(cwd).write(cache_file)
        return 0
    finally:
        lock_file.unlink(missing_ok=True)


def main(argv: list[str]) -> int:
    """Run the internal detached-refresh entrypoint."""
    if len(argv) != 5 or argv[1] != "--refresh-locked":
        return 2
    return refresh_locked(Path(argv[2]), Path(argv[3]), Path(argv[4]))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
