function cd --wraps cd
    set -l max_dir_hist 25

    if status is-command-substitution
        builtin cd $argv
        return $status
    end

    set -l previous $PWD

    if test "$argv[1]" = -
        if test "$__fish_cd_direction" = next
            nextd
        else
            prevd
        end
        set -l cd_status $status
        test $cd_status -eq 0
        and __dotfiles_list_dir
        return $cd_status
    end

    builtin cd $argv
    set -l cd_status $status

    if test $cd_status -eq 0 -a "$PWD" != "$previous"
        set -q dirprev
        or set -l dirprev
        set -q dirprev[$max_dir_hist]
        and set -e dirprev[1]

        set -U -q dirprev
        and set -U -a dirprev $previous
        or set -g -a dirprev $previous

        set -U -q dirnext
        and set -U -e dirnext
        or set -e dirnext

        set -U -q __fish_cd_direction
        and set -U __fish_cd_direction prev
        or set -g __fish_cd_direction prev
    end

    test $cd_status -eq 0
    and __dotfiles_list_dir
    return $cd_status
end

function mcd
    test (count $argv) -gt 0
    or begin
        echo 'mcd: missing directory operand' >&2
        return 1
    end

    mkdir -p -- $argv[1]
    and cd "$argv[1]"
end

function yy
    command -sq yazi
    or begin
        echo 'yy: yazi is not installed' >&2
        return 1
    end

    set -l cwd_file (mktemp -t yazi-cwd.XXXXXX)
    or return 1

    yazi $argv --cwd-file="$cwd_file"
    set -l yazi_status $status

    if test -s "$cwd_file"
        set -l new_dir (string trim -- (cat "$cwd_file"))
        if test -n "$new_dir" -a "$new_dir" != "$PWD"
            builtin cd -- "$new_dir"
        end
    end

    rm -f -- "$cwd_file"
    return $yazi_status
end

# Some interactive commands resolve a missing argument in fzf from an external
# Fish process.  Let that process report the reproducible command, then add it
# to this shell's in-memory history once the command has completed successfully.
function __dotfiles_run_with_resolved_history --argument-names executable
    set -e argv[1]

    set -l resolved_history_file (mktemp -t dotfiles-history.XXXXXX)
    or return 1

    command env DOTFILES_RESOLVED_HISTORY_FILE="$resolved_history_file" "$executable" $argv
    set -l command_status $status

    if test $command_status -eq 0; and test -s "$resolved_history_file"
        set -l resolved_command (string collect <"$resolved_history_file" | string trim)
        if test -n "$resolved_command"
            builtin history append "$resolved_command"
            builtin history save
        end
    end

    command rm -f -- "$resolved_history_file"
    return $command_status
end

function work --wraps work --description 'Open a coding workspace'
    __dotfiles_run_with_resolved_history work $argv
end

function gh-review --wraps gh-review --description 'Open a GitHub review workspace'
    __dotfiles_run_with_resolved_history gh-review $argv
end

function __dotfiles_zz_filter_candidates --argument-names include_all
    # `fd --follow` reports paths reached through symlinks, so its basename
    # excludes alone do not reliably prune Nix profile trees.  Filter absolute
    # candidate paths as a final streaming step.
    set -l home_regex (string escape --style=regex -- "$HOME")
    set -l codex_cache_pattern (string join '' \
        '^' "$home_regex" \
        '/\\.codex/(\\.tmp|ambient-suggestions|archived_sessions|attachments|browser|cache|computer-use|log|node_repl|process_manager|sessions|shell_snapshots|sqlite|tmp|vendor_imports|plugins/(cache|\\.plugin-appserver|\\.remote-plugin-install-staging))(/|$)')
    set -l nix_profile_pattern (string join '' '^' "$home_regex" '/\\.nix-[^/]+(/|$)')

    if test "$include_all" = 1
        command rg --invert-match -- "$codex_cache_pattern"
    else
        command rg --invert-match -- "$codex_cache_pattern" |
            command rg --invert-match -- "$nix_profile_pattern"
    end
end

function zz
    command -sq fzf
    or begin
        echo 'zz: fzf is not installed' >&2
        return 1
    end

    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l preview "command python3 '$fzf_rows' preview-directory {1}"

    argparse a/all h/help -- $argv
    or return 1

    if set -q _flag_help
        printf '%s\n' 'Usage: zz [-a] [DIR|~] [QUERY...]'
        return 0
    end

    set -l root "$HOME"
    if test (count $argv) -gt 0
        set root "$argv[1]"
        set -e argv[1]
    end

    test -d "$root"
    or begin
        printf 'zz: directory not found: %s\n' "$root" >&2
        return 1
    end

    set root (path resolve "$root")
    set -l query (string join ' ' -- $argv)
    # The candidate source streams.  With --select-1, fzf would accept the
    # first directory before fd has produced the remaining candidates.
    set -l fzf_opts \
        --height=70% \
        --scheme=path \
        --preview="$preview" \
        --preview-window='down,30%,sharp'
    set -l dst
    # Keep candidate lists useful even with `-a`: VCS metadata, dependencies,
    # caches, build products, and credential stores are never useful targets.
    set -l excludes \
        .git \
        .svn \
        .hg \
        .jj \
        .direnv \
        .devenv \
        .cache \
        .local \
        .mypy_cache \
        .npm \
        .pytest_cache \
        .ruff_cache \
        .terraform \
        .venv \
        .bundle \
        .cargo \
        .gem \
        .rustup \
        .ssh \
        .gnupg \
        .aws \
        .kube \
        __pycache__ \
        node_modules \
        vendor \
        dist \
        build \
        target

    if not set -q _flag_all
        # `-a` adds environment and generated directories, but intentionally
        # does not include the permanently noisy candidates above.
        set -a excludes \
            .config \
            .Trash \
            .nix-* \
            .nix-profile \
            .android \
            .gradle \
            .ollama \
            .terraform.d \
            .idea \
            .vs \
            .vscode \
            .vscode-test \
            .cursor \
            .ipynb_checkpoints \
            .next \
            .nuxt \
            .svelte-kit \
            .turbo \
            .vite \
            .parcel-cache \
            .pnpm-store \
            .yarn \
            coverage \
            .nyc_output \
            .tox \
            .nox \
            .pyre \
            .pytype \
            Library \
            tmp
    end

    if command -sq fd
        set -l fd_args \
            --absolute-path \
            --type d \
            --hidden \
            --follow

        for exclude in $excludes
            set -a fd_args --exclude "$exclude"
        end

        set -a fd_args . "$root"
        set dst (begin
            printf '%s\n' "$root"
            if set -q _flag_all
                fd $fd_args | __dotfiles_zz_filter_candidates 1
            else
                fd $fd_args | __dotfiles_zz_filter_candidates 0
            end
        end |
            command python3 "$fzf_rows" directory |
            command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 $fzf_opts --query "$query" |
            command python3 "$fzf_rows" decode)
    else
        set -l find_args "$root" "("

        for idx in (seq (count $excludes))
            test $idx -gt 1
            and set -a find_args -o
            set -a find_args -name "$excludes[$idx]"
        end

        set -a find_args ")" -prune -o -type d -print
        set dst (begin
            printf '%s\n' "$root"
            if set -q _flag_all
                command find $find_args 2>/dev/null | __dotfiles_zz_filter_candidates 1
            else
                command find $find_args 2>/dev/null | __dotfiles_zz_filter_candidates 0
            end
        end |
            command python3 "$fzf_rows" directory |
            command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 $fzf_opts --query "$query" |
            command python3 "$fzf_rows" decode)
    end

    test -n "$dst"; or return 1
    builtin cd -- "$dst[1]"
    and __dotfiles_list_dir
end

function pd
    if test (count $argv) -eq 1
        pushd "$argv[1]" >/dev/null
    else
        popd >/dev/null
    end
    and __dotfiles_list_dir
end

function bk
    argparse e/extension= f/force h/help t/time -- $argv
    or return 1

    if set -q _flag_help
        printf '%s\n' 'Usage: bk [-f] [-t] [-e EXTENSION] PATH...'
        return 0
    end

    test (count $argv) -gt 0
    or begin
        echo 'bk: no files provided' >&2
        return 1
    end

    set -l extension bk
    set -q _flag_extension; and set extension $_flag_extension[1]

    set -l cpopt -a -i
    set -q _flag_force; and set cpopt -a -f

    if set -q _flag_time
        set -l d (date '+%Y-%m-%dT%H:%M:%S')
        mkdir -p -- "$d"
        cp $cpopt -- $argv "$d"
        return $status
    end

    for f in $argv
        cp $cpopt -- "$f" "$f.$extension"
    end
end

function get
    mv -i -- $argv .
end

function showopt
    echo 'showopt is zsh-specific and is not supported in fish.' >&2
    return 1
end

function p
    if command -sq clockping
        if test (count $argv) -eq 0
            clockping icmp --out.colored 1.1.1.1
        else
            clockping icmp --out.colored $argv
        end
    else if test (count $argv) -eq 0
        ping 1.1.1.1
    else
        ping $argv
    end
end

function pp
    if command -sq clockping
        if test (count $argv) -eq 0
            clockping icmp --out.colored 2001:4860:4860::8888
        else
            clockping icmp --out.colored $argv
        end
    else if test (count $argv) -eq 0
        ping6 2001:4860:4860::8888
    else
        ping6 $argv
    end
end

function ppp
    if command -sq clockping
        clockping icmp --out.colored -c 4 -i 0.25 8.8.8.8 2001:4860:4860::8888
        echo
        clockping http --out.colored -c 4 -i 0.25 ipv4.google.com ipv6.google.com
    else
        ping -c 4 -i 0.25 8.8.8.8
        echo
        ping6 -c 4 -i 0.25 2001:4860:4860::8888
    end
end

function m
    if test (count $argv) -eq 0
        mtr -4 -b -i 0.1 8.8.8.8
    else
        mtr -4 -b -i 0.1 $argv
    end
end

function mm
    if test (count $argv) -eq 0
        mtr -6 -b -i 0.1 2001:4860:4860::8888
    else
        mtr -6 -b -i 0.1 $argv
    end
end

function mmm
    set -l layout -v
    set -l target 8.8.8.8
    if contains -- $argv[1] -h -v
        set layout $argv[1]
        set target $argv[2]
    else if test (count $argv) -gt 0
        set target $argv[1]
    end
    test -n "$target"; or return 1

    switch $layout
        case -h
            tmux split-window -h -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 "(string escape -- "$target")
            tmux split-window -h "sudo grc --colour=auto mtr -6 -b -i 0.1 "(string escape -- "$target")
        case '*'
            tmux split-window -v -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 "(string escape -- "$target")
            tmux split-window -v "sudo grc --colour=auto mtr -6 -b -i 0.1 "(string escape -- "$target")
    end
end

function dcx
    set -l name $argv[1]
    set -e argv[1]
    if test (count $argv) -eq 0
        set argv /bin/bash
    end
    docker compose exec "$name" $argv
end

function dot
    if test (count $argv) -eq 0
        cd "$HOME/dotfiles"
        return 0
    end

    set -l sub $argv[1]
    set -e argv[1]
    set -l repo "$HOME/dotfiles"

    switch $sub
        case cc commit
            set -l message (string join ' ' -- $argv)
            command git -C "$repo" add . >/dev/null 2>&1
            and command git -C "$repo" commit -m "$message"
        case k keep
            command git -C "$repo" add . >/dev/null 2>&1
            and command git -C "$repo" commit -m "keep: "(date)
        case d diff
            command git -C "$repo" diff-index --quiet HEAD
            or command git -C "$repo" diff
        case lg log
            if command -sq lazygit
                command lazygit --path "$repo"
            else
                command tig -C "$repo"
            end
        case pl pull
            command git -C "$repo" pull
        case ps push
            command git -C "$repo" push
        case s sync
            command git -C "$repo" pull
            and command git -C "$repo" push
        case sw switch
            command task -d "$repo" hm.switch
        case gc
            command task -d "$repo" hm.gc
        case upgrade
            if test (uname) = Darwin
                command task -d "$repo" brew.sync
                or return
            end
            command task -d "$repo" hm.update
        case rollback
            if command git -C "$repo" diff --quiet -- .
                echo 'dot rollback: no unstaged changes to discard.'
            else
                read -l -P 'dot rollback: discard unstaged changes in tracked files under ~/dotfiles? [y/N] ' confirm
                if string match -rqi '^(y|yes)$' -- $confirm
                    command git -C "$repo" restore --worktree -- .
                else
                    echo 'dot rollback: aborted.'
                end
            end
        case '*'
            echo 'usage: dot [options...]'
            echo " (empty)               move to $HOME/dotfiles"
            echo ' cc, commit [message]  alias of `git add . && git commit -m` command'
            echo ' k,  keep              alias of `git keep .` command'
            echo ' d,  diff              alias of `git diff` command'
            echo ' lg, log               alias of `tig` command'
            echo ' pl, pull              alias of `git pull` command'
            echo ' ps, push              alias of `git push` command'
            echo ' s,  sync              run pull and then push'
            echo ' sw, switch            run `task hm.switch` in ~/dotfiles'
            echo '     gc                run `task hm.gc` in ~/dotfiles'
            echo '     upgrade           run package upgrade'
            echo '     rollback          discard unstaged tracked-file changes after confirmation'
            echo ' h,  help              this help text'
    end
end

function addr
    set -l addrtxt "$HOME/io/addr/addr.txt"
    set -l repo (dirname "$addrtxt")
    set -l keyword $argv[1]

    if not test -f "$addrtxt"
        echo "missing: $addrtxt"
        return 1
    end

    if test -z "$keyword"
        bat "$addrtxt"
    else if test "$keyword" = --edit
        command git -C "$repo" pull 2>/dev/null; or true
        set -l editor_cmd (__dotfiles_command_words "$EDITOR" vi)
        $editor_cmd "$addrtxt"
        command git -C "$repo" add "$addrtxt" 2>/dev/null
        and command git -C "$repo" commit -m "keep: "(date) 2>/dev/null
        and command git -C "$repo" push 2>/dev/null
        or true
    else
        set -l data (grep -vE '^(#|$)' "$addrtxt" | grep -i -- "$keyword")
        if test -n "$data"
            echo 'IP address              Hostname                    Notes'
            printf '%s\n' $data
        else
            echo "nothing matched: $keyword"
        end
    end
end

function what
    set -l filepath $argv[1]
    switch (file -b -- "$filepath")
        case 'PEM certificate'
            openssl x509 -in "$filepath" -noout -text
    end
end

function man
    set -l man_path (string join : $HOME/bin $PATH)
    env \
        LESS_TERMCAP_mb=(printf '\e[1;38;2;%sm' $CTP_PEACH_RGB) \
        LESS_TERMCAP_md=(printf '\e[1;38;2;%sm' $CTP_PEACH_RGB) \
        LESS_TERMCAP_me=(printf '\e[0m') \
        LESS_TERMCAP_se=(printf '\e[0m') \
        LESS_TERMCAP_so=(printf '\e[38;2;%s;48;2;%sm' $CTP_TEXT_RGB $CTP_SURFACE0_RGB) \
        LESS_TERMCAP_ue=(printf '\e[0m') \
        LESS_TERMCAP_us=(printf '\e[4;38;2;%sm' $CTP_BLUE_RGB) \
        PAGER=/usr/bin/less \
        _NROFF_U=1 \
        PATH=$man_path \
        /usr/bin/man $argv
end

function tgz
    env COPYFILE_DISABLE=1 tar zcvf "$argv[1]" --exclude=.DS_Store $argv[2..-1]
end

function ipapi
    if test (count $argv) -gt 0
        curl -s "http://ip-api.com/json/$argv[1]" | jq .
    else
        curl -s http://ip-api.com/json | jq .
    end
end

function ghc
    set -l repo $argv[1]
    if test (count $argv) -eq 2
        set repo $argv[1]/$argv[2]
    end
    git clone --recursive "git@github.com:$repo"
end

function sshsocks
    ssh -C -D "$argv[2]" -f -N "$argv[1]"
end

function xx
    set -l archive $argv[1]
    test -n "$archive"; or return 1

    switch $archive
        case '*.tar.gz' '*.tgz'
            tar xzvf "$archive"
        case '*.tar.xz'
            tar Jxvf "$archive"
        case '*.zip'
            unzip "$archive"
        case '*.rar'
            unar "$archive"
        case '*.lzh'
            lha e "$archive"
        case '*.tar.bz2' '*.tbz'
            tar xjvf "$archive"
        case '*.tar.Z'
            tar zxvf "$archive"
        case '*.gz'
            gzip -d "$archive"
        case '*.bz2'
            bzip2 -dc "$archive"
        case '*.Z'
            uncompress "$archive"
        case '*.tar'
            tar xvf "$archive"
        case '*.arj'
            unarj "$archive"
        case '*'
            echo "xx: unsupported archive: $archive" >&2
            return 1
    end
end

function dotenv
    set -l envfile $argv[1]
    if test -z "$envfile"; and test -f .env
        set envfile .env
    end
    test -f "$envfile"; or return 1
    __dotfiles_import_posix_exports "$envfile"
end

function io
    if test (count $argv) -eq 0
        cd "$HOME/io"
    end
end

function ::
    set -l session $argv[1]

    if test -z "$session"
        tmux
    else if contains -- $session (tmux ls -F '#{session_name}' 2>/dev/null)
        tmux attach -t "$session"
    else
        tmux $argv
    end
end

function :::
    herdr $argv
end

function __dotfiles_herdr_pane_label_for_pane --argument-names pane_id
    set -l process_info (herdr pane process-info --pane "$pane_id" 2>/dev/null)
    test $status -eq 0; or return 1

    set -l label (printf '%s\n' $process_info | jq -r '
        .result.process_info as $info
        | ($info.foreground_processes[0] // null) as $proc
        | if $proc == null then "" else ($proc.argv0 // $proc.name // ($proc.argv[0]? // "")) end
    ')

    set label (string split '/' -- $label | tail -n 1)
    set label (string replace -r '^-' '' -- (string trim -- $label))

    test -n "$label"; and printf '%s\n' "$label"
end

function __dotfiles_sync_herdr_pane_label --argument-names pane_id dry_run
    set -l pane_info (herdr pane get "$pane_id" 2>/dev/null)
    test $status -eq 0; or return 0

    set -l current_label (printf '%s\n' $pane_info | jq -r '.result.pane.label // ""')
    set -l next_label (__dotfiles_herdr_pane_label_for_pane "$pane_id")
    test -n "$next_label"; or return 0
    test "$current_label" = "$next_label"; and return 0

    if test "$dry_run" = 1
        printf '%s\t%s\t%s\n' "$pane_id" "$current_label" "$next_label"
        return 0
    end

    herdr pane rename "$pane_id" "$next_label" >/dev/null
end

function herdr-pane-labels
    argparse 'i/interval=' o/once d/dry-run h/help -- $argv
    or return 1

    if set -q _flag_help
        printf '%s\n' \
            'Usage: herdr-pane-labels [--once] [--dry-run] [--interval SECONDS]' \
            '' \
            'Rename Herdr panes to their current foreground process names.' \
            'This overwrites manual pane labels while it is running.'
        return 0
    end

    type -q jq
    or begin
        echo 'herdr-pane-labels: jq is required.' >&2
        return 1
    end

    set -l interval 2
    if set -q _flag_interval
        set interval $_flag_interval
    end

    while true
        set -l pane_list (herdr pane list 2>/dev/null)
        if test $status -ne 0
            sleep $interval
            continue
        end

        for pane_id in (printf '%s\n' $pane_list | jq -r '.result.panes[].pane_id')
            __dotfiles_sync_herdr_pane_label "$pane_id" (set -q _flag_dry_run; and echo 1; or echo 0)
        end

        set -q _flag_once; and break
        sleep $interval
    end
end

function __dotfiles_start_herdr_pane_labels
    status is-interactive; or return 0
    set -q HERDR_ENV; or return 0
    set -q HERDR_SOCKET_PATH; or return 0
    set -q DOTFILES_HERDR_PANE_LABEL_WATCHER; and return 0
    type -q jq; or return 0

    set -l cache_dir "$HOME/.cache/herdr-pane-labels"
    mkdir -p "$cache_dir"

    set -l lock_key (string replace -a '/' '_' -- $HERDR_SOCKET_PATH)
    set -l pidfile "$cache_dir/$lock_key.pid"

    if test -f "$pidfile"
        set -l existing_pid (string trim -- (cat "$pidfile" 2>/dev/null))
        if string match -qr '^[0-9]+$' -- $existing_pid
            if kill -0 "$existing_pid" 2>/dev/null
                return 0
            end
        end
        rm -f "$pidfile"
    end

    set -l source_file (path resolve (functions --details herdr-pane-labels))
    set -l command "source "(string escape -- $source_file)"; herdr-pane-labels"

    nohup env DOTFILES_HERDR_PANE_LABEL_WATCHER=1 fish -c "$command" >/dev/null 2>&1 &
    set -l watcher_pid $last_pid
    disown "$watcher_pid"
    printf '%s\n' "$watcher_pid" >"$pidfile"
end

__dotfiles_start_herdr_pane_labels

function gk
    set -l target $argv
    if test (count $target) -eq 0
        set target (dirname (git rev-parse --git-dir))
    end

    git add -- $target
    and git commit -m "keep: "(date)

    if test -n (git remote -v)
        git push
        or begin
            git pull
            and git push
        end
    end
end

function gadd
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l preview (string join '' -- 'set -l file (printf "%s\n" {1} | command python3 ' (string escape -- "$fzf_rows") ' decode); git diff --color -- "$file"')
    set -l files (command git status --porcelain=v1 -z |
        command python3 "$fzf_rows" git-status |
        command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 -m --preview="$preview" |
        command python3 "$fzf_rows" decode)
    if test (count $files) -gt 0
        git add -- $files
        echo "Completed: git add "(string join ' ' -- $files)
    end
end

function __dotfiles_fzf_default_command
    if set -q FZF_DEFAULT_COMMAND; and test -n "$FZF_DEFAULT_COMMAND"
        command sh -c "$FZF_DEFAULT_COMMAND"
    else if command -sq fd
        command fd --hidden --follow --exclude .git
    else
        command find . -type f
    end
end

function fe
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l files (__dotfiles_fzf_default_command |
        command python3 "$fzf_rows" path |
        command env NO_COLOR= SHELL="$fish_shell" fzf-tmux --ansi --with-nth=2.. --nth=2.. --accept-nth=1 --query="$argv[1]" --multi |
        command python3 "$fzf_rows" decode)
    if test -n "$files"
        set -l editor_cmd (__dotfiles_command_words "$EDITOR" vi)
        $editor_cmd $files
    end
end

function fkill
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l processes (ps -ef | sed 1d |
        command python3 "$fzf_rows" process |
        command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 -m |
        command python3 "$fzf_rows" decode)
    set -l pids
    for process in $processes
        set -l fields (string split --no-empty ' ' -- "$process")
        test (count $fields) -ge 2; and set -a pids $fields[2]
    end
    if test (count $pids) -gt 0
        command kill -$argv[1] $pids
    end
end

function dor
    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l image (docker images --format '{{.Repository}}:{{.Tag}}' --filter 'dangling=false' |
        command python3 "$fzf_rows" image |
        command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 |
        command python3 "$fzf_rows" decode)
    test -n "$image"; and docker run -it $argv "$image"
end

function ffind
    for key in $argv
        find . -name "*$key*" | grep --color=auto -- "$key"
    end
end

function tenki
    curl "http://wttr.in/$argv[1]"
end

function copy-aws-session
    mkdir -p "$HOME/.cache"
    set -l cache_path "$HOME/.cache/zsh__copy_aws_session.cache"
    printf '%s\n' \
        " export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
        " export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" \
        " export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
        " export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" >"$cache_path"
    chmod 600 "$cache_path" 2>/dev/null
    echo 'AWS session copied.'
end

function paste-aws-session
    set -l cache "$HOME/.cache/zsh__copy_aws_session.cache"
    set -l session (cat "$cache" 2>/dev/null)

    if not test -f "$cache"; or test -z "$session"
        echo 'Missing cached session.'
        return 1
    end

    if test "$argv[1]" = -e
        printf '%s' "$session" | pbcopy 2>/dev/null
        printf '%s' "$session"
    else
        printf '%s' "$session" | sed -e 's/ export //g' -e 's/=/\t/'
    end

    echo
    for line in (printf '%s\n' "$session")
        set line (string trim -- $line)
        set line (string replace -r '^export\s+' '' -- $line)
        set -l parts (string split -m 1 '=' -- $line)
        test (count $parts) -eq 2; or continue
        set -gx $parts[1] $parts[2]
    end
end

function clear-aws-session
    set -e AWS_ACCESS_KEY_ID
    set -e AWS_DEFAULT_REGION
    set -e AWS_SECRET_ACCESS_KEY
    set -e AWS_SESSION_TOKEN
    echo 'AWS session cleared.'
end

function resolve-vpg-ip
    set -l name $argv[1]
    set -l uuid_pattern '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    if string match -qr '^i-' -- $name
        aws ec2 describe-instances --filters "Name=instance-id,Values=$name" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress'
        return $status
    end

    if string match -qr '^VPG-Type-' -- $name
        aws ec2 describe-instances --filters "Name=tag:Name,Values=$name" | jq -r '.Reservations[].Instances[] | .Placement.AvailabilityZone + " " + .InstanceId + " " + .PrivateIpAddress'
        return $status
    end

    if string match -qr $uuid_pattern -- $name
        aws ec2 describe-instances --filters "Name=tag:Name,Values=VPG-Type-*-$name" | jq -r '.Reservations[].Instances[] | .Placement.AvailabilityZone + " " + .InstanceId + " " + .PrivateIpAddress'
    end
end

function colortest
    for c in (seq 0 255)
        printf '\e[38;5;%sm %3s' $c $c
        if test (math "$c % 16") -eq 15
            echo
        end
    end
end

function kcc
    set -l context (kubectl config current-context 2>/dev/null)
    or return $status

    set -l config_home "$HOME/.config"
    set -q XDG_CONFIG_HOME; and set config_home "$XDG_CONFIG_HOME"
    set -l fzf_rows "$config_home/fish/lib/fzf_rows.py"
    set -l fish_shell (command -s fish)
    set -l namespace (kubectl get namespaces -o custom-columns=':metadata.name' --no-headers 2>/dev/null |
        command python3 "$fzf_rows" simple |
        command env NO_COLOR= SHELL="$fish_shell" fzf --ansi --with-nth=2.. --nth=2.. --accept-nth=1 --prompt='namespace> ' |
        command python3 "$fzf_rows" decode)
    or return 0

    test -n "$namespace"; or return 0
    kubectl config set-context "$context" --namespace="$namespace"
end

function _severity_clear
    set -gx PROMPT_SEVERITY 0
end

function _severity_level1
    set -gx PROMPT_SEVERITY 1
end

function _severity_level2
    set -gx PROMPT_SEVERITY 2
end

function _severity_level3
    set -gx PROMPT_SEVERITY 3
end

function _severity_level4
    set -gx PROMPT_SEVERITY 4
end

function _toggle_ssh_prompt
    if not set -q HIDE_SSH_PROMPT
        set -gx HIDE_SSH_PROMPT 1
    else if test $HIDE_SSH_PROMPT -eq 0
        set -gx HIDE_SSH_PROMPT 1
    else
        set -gx HIDE_SSH_PROMPT 0
    end
end

function _sanitize_history
    set -l history_path "$HOME/.local/share/fish/fish_history"
    test -f "$history_path"; or return 0

    python3 -c 'import pathlib, sys
history_path = pathlib.Path(sys.argv[1])
lines = history_path.read_text(encoding="utf-8").splitlines()
entries = []
i = 0
while i < len(lines):
    if lines[i].startswith("- cmd: "):
        j = i + 1
        while j < len(lines) and not lines[j].startswith("- cmd: "):
            j += 1
        entries.append(lines[i:j])
        i = j
    else:
        entries.append([lines[i]])
        i += 1
filtered = []
changed = False
for entry in entries:
    if entry and entry[0].startswith("- cmd: "):
        cmd = entry[0][7:]
        try:
            cmd.encode("ascii")
        except UnicodeEncodeError:
            changed = True
            continue
    filtered.extend(entry)
if changed:
    tmp = history_path.with_suffix(history_path.suffix + ".tmp")
    tmp.write_text("".join(line + "\n" for line in filtered), encoding="utf-8")
    tmp.replace(history_path)
' "$history_path"
end
