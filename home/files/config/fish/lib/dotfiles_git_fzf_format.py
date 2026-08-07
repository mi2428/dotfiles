#!/usr/bin/env python3
import csv
import json
import re
import sys


def die(message: str) -> None:
    print(f"dotfiles_git_fzf_format: {message}", file=sys.stderr)
    raise SystemExit(2)


def ellipsize(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    return text[: width - 3] + "..."


def colorize(
    text: str,
    rgb: str,
    *,
    bold: bool = False,
    italic: bool = False,
    background: str | None = None,
) -> str:
    attrs = []
    if bold:
        attrs.append("1")
    if italic:
        attrs.append("3")
    attrs.append(f"38;2;{rgb}")
    if background:
        attrs.append(f"48;2;{background}")
    return f"\033[{';'.join(attrs)}m{text}\033[0m"


def compact_relative_age(text: str) -> str:
    parts = text.split()
    if len(parts) < 2:
        return text

    amount = parts[0]
    unit = parts[1].lower()
    unit_map = {
        "second": "s",
        "seconds": "s",
        "minute": "m",
        "minutes": "m",
        "hour": "h",
        "hours": "h",
        "day": "d",
        "days": "d",
        "week": "w",
        "weeks": "w",
        "month": "mo",
        "months": "mo",
        "year": "y",
        "years": "y",
    }

    if amount == "just":
        return "now"

    suffix = unit_map.get(unit)
    if suffix is None:
        return text

    return f"{amount}{suffix} ago"


def shorten_path(path: str, home: str, width: int) -> str:
    if not path:
        return "-"
    absolute = path.startswith("/")
    body = path
    prefix = ""
    if home and path.startswith(home):
        prefix = "~/"
        body = path[len(home) :].lstrip("/")
    elif absolute:
        prefix = "/"
        body = path.lstrip("/")

    parts = [part for part in body.split("/") if part]
    if not parts:
        return prefix.rstrip("/") or path

    basename = parts[-1]
    parents = [part[:1] for part in parts[:-1]]
    compressed = prefix + "/".join(parents + [basename])
    if len(compressed) <= width:
        return compressed

    tail = [basename]
    for parent in reversed(parents):
        candidate = prefix + ".../" + "/".join([parent] + tail)
        if len(candidate) > width:
            break
        tail.insert(0, parent)

    if len(tail) > 1:
        return prefix + ".../" + "/".join(tail)

    reserved = len(prefix) + 4
    tail_width = max(1, width - reserved)
    return prefix + ".../" + ellipsize(basename, tail_width)


def format_branches(list_width: int, home: str) -> None:
    rows = []
    reader = csv.reader(sys.stdin, delimiter="\t")
    for ref_short, ref_full, age, author, subject, worktree in reader:
        if ref_full.startswith("refs/heads/"):
            kind = "local"
            marker = "[L]"
        elif ref_full.startswith("refs/worktrees/"):
            kind = "worktree"
            marker = "[W]"
        else:
            kind = "remote"
            marker = "[R]"
        switch_target = (
            ref_short.split("/", 1)[1]
            if kind == "remote" and "/" in ref_short
            else ref_short
        )
        rows.append(
            {
                "ref_short": ref_short,
                "kind": kind,
                "marker": marker,
                "switch_target": switch_target,
                "age": compact_relative_age(age),
                "author": author,
                "subject": subject,
                "worktree": worktree,
            }
        )

    if not rows:
        raise SystemExit(0)

    branch_min = 12
    age_min = 8
    author_min = 8
    worktree_min = 3
    subject_min = 16
    fixed_width = 12

    branch_width = max(branch_min, max(len(row["ref_short"]) for row in rows))
    age_width = max(age_min, max(len(row["age"]) for row in rows))
    author_width = max(author_min, max(len(row["author"]) for row in rows))

    for row in rows:
        row["worktree_display"] = shorten_path(row["worktree"], home, list_width)

    worktree_width = max(
        worktree_min, max(len(row["worktree_display"]) for row in rows)
    )

    subject_width = (
        list_width
        - fixed_width
        - branch_width
        - age_width
        - author_width
        - worktree_width
    )
    if subject_width < subject_min:
        shortage = subject_min - subject_width
        reduce_worktree = min(shortage, max(0, worktree_width - worktree_min))
        worktree_width -= reduce_worktree
        shortage -= reduce_worktree

        reduce_author = min(shortage, max(0, author_width - author_min))
        author_width -= reduce_author
        shortage -= reduce_author

        reduce_branch = min(shortage, max(0, branch_width - branch_min))
        branch_width -= reduce_branch

        subject_width = (
            list_width
            - fixed_width
            - branch_width
            - age_width
            - author_width
            - worktree_width
        )

    if subject_width < subject_min:
        subject_width = subject_min

    lavender = "180;190;254"
    green = "166;227;161"
    blue = "137;180;250"
    overlay = "147;153;178"
    pink = "245;194;231"

    for row in rows:
        marker_rgb = green if row["kind"] != "remote" else blue
        branch_rgb = lavender if row["kind"] != "remote" else blue
        marker = colorize(f"{row['marker']:<3}", marker_rgb, bold=True)
        branch_display = colorize(
            f"{ellipsize(row['ref_short'], branch_width):<{branch_width}}",
            branch_rgb,
            bold=True,
        )
        age_display = colorize(f"{row['age']:<{age_width}}", overlay)
        author_display = colorize(
            f"{ellipsize(row['author'], author_width):<{author_width}}", pink
        )
        worktree_display = colorize(
            f"{shorten_path(row['worktree'], home, worktree_width):<{worktree_width}}",
            overlay,
        )
        subject_display = ellipsize(row["subject"], subject_width)
        display = (
            f"{marker} {branch_display}  {age_display}  "
            f"{author_display}  {worktree_display}  {subject_display}"
        )
        worktree_hidden = row["worktree"] or "-"
        print(
            "\t".join(
                [
                    row["ref_short"],
                    row["kind"],
                    row["switch_target"],
                    worktree_hidden,
                    display,
                ]
            )
        )


def format_prs(list_width: int) -> None:
    rows = []
    reader = csv.reader(sys.stdin, delimiter="\t")
    for (
        number,
        title,
        author,
        is_draft,
        state,
        head,
        base,
        updated,
        url,
        labels,
    ) in reader:
        try:
            parsed_labels = json.loads(labels)
        except json.JSONDecodeError:
            parsed_labels = []
        rows.append(
            {
                "number": f"#{number}",
                "title": title,
                "author": author,
                "is_draft": is_draft.lower() == "true",
                "state": state.lower(),
                "head": head,
                "base": base,
                "updated": updated,
                "url": url,
                "labels": parsed_labels,
            }
        )

    if not rows:
        raise SystemExit(0)

    del list_width  # fzf clips the Snacks-style flowing row at the split edge.

    text = "205;214;244"
    blue = "137;180;250"
    green = "40;167;69"
    red = "215;58;73"
    overlay = "127;132;156"
    peach = "250;179;135"
    gray = "106;115;125"
    dimmed_types = {"chore", "bot", "build", "ci", "style", "test"}
    conventional = re.compile(r"^(\S+?)(\([^)]*\))?(!?):\s*(.*)$")

    def format_title(title: str) -> str:
        match = conventional.match(title)
        if not match:
            return colorize(title, text)

        commit_type, scope, breaking, body = match.groups()
        dimmed = commit_type in dimmed_types
        type_rgb = red if breaking else (text if dimmed else blue)
        body_rgb = overlay if dimmed else text
        parts = [colorize(commit_type, type_rgb, bold=True)]
        if scope:
            parts.append(colorize(scope, text, italic=True))
        if breaking:
            parts.append(colorize("!", red, bold=True))
        parts.append(colorize(": ", overlay))
        parts.append(colorize(body, body_rgb))
        return "".join(parts)

    def label_badge(label: dict[str, object]) -> str:
        name = str(label.get("name") or "")
        raw_color = str(label.get("color") or "888888").lstrip("#")
        if not name or not re.fullmatch(r"[0-9a-fA-F]{6}", raw_color):
            return ""
        red_value = int(raw_color[0:2], 16)
        green_value = int(raw_color[2:4], 16)
        blue_value = int(raw_color[4:6], 16)
        luminance = (red_value * 299 + green_value * 587 + blue_value * 114) / 1000
        badge_fg = "17;17;27" if luminance >= 140 else "255;255;255"
        badge_bg = f"{red_value};{green_value};{blue_value}"
        return colorize(f" {name} ", badge_fg, background=badge_bg)

    for row in rows:
        if row["is_draft"]:
            icon = colorize(" ", gray)
        elif row["state"] == "merged":
            icon = colorize(" ", "111;66;193")
        elif row["state"] == "closed":
            icon = colorize(" ", red)
        else:
            icon = colorize(" ", green)

        number = colorize(f"{row['number']:<8}", overlay)
        title = format_title(row["title"])
        author = colorize("@" + row["author"], peach)
        badges = [label_badge(label) for label in row["labels"]]
        badges = [badge for badge in badges if badge]
        display = f"{icon}{number}{title} {author}"
        if badges:
            display += " " + " ".join(badges)
        # Keep the full head branch as a hidden field so callers can persist a
        # reproducible command after fzf returns.
        print("\t".join([row["number"], row["url"], display, row["head"]]))


def main() -> None:
    if len(sys.argv) < 3:
        die("usage: dotfiles_git_fzf_format.py <branches|prs> <list-width> [home]")

    mode = sys.argv[1]
    try:
        list_width = int(sys.argv[2])
    except ValueError as exc:
        raise SystemExit(
            f"dotfiles_git_fzf_format.py: invalid list width: {sys.argv[2]}"
        ) from exc

    home = sys.argv[3] if len(sys.argv) > 3 else ""

    if mode == "branches":
        format_branches(list_width, home)
        return

    if mode == "prs":
        format_prs(list_width)
        return

    die(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
