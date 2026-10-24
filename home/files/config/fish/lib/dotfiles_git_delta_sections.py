"""Render added files full-width while retaining side-by-side modified diffs."""

import subprocess
import sys


def render_section(
    lines: list[bytes], delta: list[str], *, added: bool, unified: bool
) -> None:
    """Render one file diff without an empty old-file gutter for additions."""
    if not lines:
        return

    if added and unified:
        layout = ["--line-numbers-left-format="]
    elif added:
        layout = [
            "--line-numbers-left-format=│{np:^4}│",
            "--line-numbers-right-format=",
        ]
    elif unified:
        layout = []
    else:
        layout = ["--side-by-side"]

    subprocess.run(
        [*delta, *layout], input=b"".join(lines), stdout=sys.stdout.buffer, check=True
    )


def main() -> None:
    """Split Git's patch stream by file and render each section with delta."""
    arguments = sys.argv[1:]
    unified = bool(arguments) and arguments[0] == "--unified"
    delta = arguments[1:] if unified else arguments
    if not delta:
        raise SystemExit(
            "usage: dotfiles_git_delta_sections.py [--unified] DELTA [ARGS...]"
        )

    section: list[bytes] = []
    added = False

    for line in sys.stdin.buffer:
        if line.startswith(b"diff --git "):
            render_section(section, delta, added=added, unified=unified)
            section = []
            added = False
        if line.startswith(b"new file mode "):
            added = True
        section.append(line)
    render_section(section, delta, added=added, unified=unified)


if __name__ == "__main__":
    main()
