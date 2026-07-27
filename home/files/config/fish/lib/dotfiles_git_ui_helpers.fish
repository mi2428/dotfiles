set -g __dotfiles_git_ui_helper_dir (path dirname (status filename))
set -g __dotfiles_git_ui_formatter_py "$__dotfiles_git_ui_helper_dir/dotfiles_git_fzf_format.py"

function __dotfiles_git_ui_slugify --argument-names text
    printf '%s' "$text" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs '[:alnum:]' '-' \
        | sed 's/^-//; s/-$//' \
        | cut -c1-36
end

function __dotfiles_git_ui_stable_id --argument-names text
    if command -q sha256sum
        set -l fields (printf '%s' "$text" | command sha256sum | string split ' ')
        test -n "$fields[1]"; or return 1
        string sub -l 12 -- "$fields[1]"
        return
    end

    if command -q shasum
        set -l fields (printf '%s' "$text" | command shasum -a 256 | string split ' ')
        test -n "$fields[1]"; or return 1
        string sub -l 12 -- "$fields[1]"
        return
    end

    set -l fields (printf '%s' "$text" | command cksum | string split ' ')
    test -n "$fields[1]"; or return 1
    printf '%08x\n' "$fields[1]"
end

function __dotfiles_git_ui_current_terminal_size
    set -l width ''
    set -l height ''

    if set -q TMUX
        if set -q TMUX_PANE
            set width (tmux display-message -p -t "$TMUX_PANE" '#{client_width}' 2>/dev/null)
            set height (tmux display-message -p -t "$TMUX_PANE" '#{client_height}' 2>/dev/null)
        else
            set width (tmux display-message -p '#{client_width}' 2>/dev/null)
            set height (tmux display-message -p '#{client_height}' 2>/dev/null)
        end
    end

    if test -z "$width" -o -z "$height"
        set -l tty_size (stty size 2>/dev/null | string split ' ')
        if test (count $tty_size) -ge 2
            test -n "$height"; or set height "$tty_size[1]"
            test -n "$width"; or set width "$tty_size[2]"
        end
    end

    if test -z "$width"; and set -q COLUMNS
        set width "$COLUMNS"
    end
    if test -z "$height"; and set -q LINES
        set height "$LINES"
    end

    if test -z "$width"
        set width (tput cols 2>/dev/null)
    end
    if test -z "$height"
        set height (tput lines 2>/dev/null)
    end

    test -n "$width"; or set width 160
    test -n "$height"; or set height 48

    printf '%s\n%s\n' "$width" "$height"
end

function __dotfiles_git_ui_render_pr_preview --argument-names pr_ref glow_style_path
    command -q gh; or return 127
    command -q jq; or return 127

    set -l width 100
    if set -q FZF_PREVIEW_COLUMNS
        set width "$FZF_PREVIEW_COLUMNS"
    end

    set -l markdown (
        gh pr view "$pr_ref" --json number,title,url,author,baseRefName,headRefName,body,reviews,comments \
        | jq -r '
            def clip($n): .[0:$n];
            def body_or_default:
                if (.body // "") == "" then "_No description._" else .body end;
            def review_section:
                (.reviews | clip(4)) as $reviews
                | if ($reviews | length) == 0 then
                    "## Reviews\n\n_No reviews yet._"
                  else
                    "## Reviews\n\n"
                    + ($reviews | map("### \(.author.login) [\(.state)]\n\n" + ((.body // "") | if . == "" then "_No body._" else . end)) | join("\n\n"))
                  end;
            def comment_section:
                (.comments | clip(4)) as $comments
                | if ($comments | length) == 0 then
                    "## Comments\n\n_No issue comments._"
                  else
                    "## Comments\n\n"
                    + ($comments | map("### \(.author.login)\n\n" + ((.body // "") | if . == "" then "_No body._" else . end)) | join("\n\n"))
                  end;
            "# PR #\(.number): \(.title)\n\n"
            + "- URL: \(.url)\n"
            + "- Author: \(.author.login)\n"
            + "- Base: `\(.baseRefName)`\n"
            + "- Head: `\(.headRefName)`\n\n"
            + "## Description\n\n"
            + body_or_default
            + "\n\n"
            + review_section
            + "\n\n"
            + comment_section
        ' \
        | string collect
    )

    if command -q glow
        printf '%s\n' "$markdown" | glow -s "$glow_style_path" -w "$width" -
    else
        printf '%s\n' "$markdown"
    end
end

function __dotfiles_git_ui_delta_lazygit
    command -q delta; or begin
        printf 'dotfiles-git-ui: missing required command: delta\n' >&2
        return 127
    end

    set -l delta_bin (command -s delta)
    set -l less_bin less
    if command -q less
        set less_bin (command -s less)
    end

    set -l paging never
    set -l added_label (printf '\033[1;38;2;166;227;161mA\033[0m')
    set -l copied_label (printf '\033[1;38;2;148;226;213mC\033[0m')
    set -l modified_label (printf '\033[1;38;2;249;226;175mM\033[0m')
    set -l removed_label (printf '\033[1;38;2;243;139;168mD\033[0m')
    set -l renamed_label (printf '\033[1;38;2;137;180;250mR\033[0m')
    set -l delta_args \
        --features=catppuccin-mocha \
        --dark \
        "--file-added-label=$added_label" \
        "--file-copied-label=$copied_label" \
        "--file-modified-label=$modified_label" \
        "--file-removed-label=$removed_label" \
        "--file-renamed-label=$renamed_label" \
        --line-numbers \
        --side-by-side

    if isatty stdout
        set paging always
        set -a delta_args --pager "$less_bin -Rc"
    end

    if not set -q TMUX
        set -a delta_args --hyperlinks '--hyperlinks-file-link-format=lazygit-edit://{path}:{line}'
    end

    command "$delta_bin" --paging="$paging" $delta_args
end

function __dotfiles_git_ui_format_fzf_rows --argument-names mode list_width home
    command -q python3; or begin
        printf 'dotfiles-git-ui: missing required command: python3\n' >&2
        return 127
    end

    command python3 "$__dotfiles_git_ui_formatter_py" "$mode" "$list_width" "$home"
end
