function cd --wraps cd
    set -l max_dir_hist 25

    if status is-command-substitution
        builtin cd -- $argv
        return $status
    end

    set -l previous $PWD

    if test "$argv" = "-"
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

    builtin cd -- $argv
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
    mkdir -p -- $argv[1]
    and cd $argv[1]
end

function pd
    if test (count $argv) -eq 1
        pushd $argv[1]
    else
        popd
    end
    and __dotfiles_list_dir
end

function bk
    argparse e/extension= f/force h/help t/time -- $argv
    or return 1

    if set -q _flag_help
        command -sq bk; and command bk
        return 0
    end

    set -l extension bk
    set -q _flag_extension; and set extension $_flag_extension[1]

    set -l cpopt -a -i
    set -q _flag_force; and set cpopt -a -f

    if set -q _flag_time
        set -l d (date '+%Y-%m-%dT%H:%M:%S')
        mkdir -p $d
        cp $cpopt $argv $d
        return $status
    end

    for f in $argv
        cp $cpopt $f "$f.$extension"
    end
end

function goto
    set -l keyword /
    if test (count $argv) -gt 0
        set keyword $argv[1]
    end

    test -f $PATH_BOOKMARK; or touch $PATH_BOOKMARK

    set -l matched
    if test -n "$keyword"
        set matched (grep -E -- "$keyword" $PATH_BOOKMARK 2>/dev/null)
    end

    set -l dst
    if test (count $matched) -eq 1
        set dst $matched[1]
    else if command -sq fzf
        if test (count $matched) -gt 0
            set dst (printf '%s\n' $matched | fzf -e --tac --no-sort --preview 'tree -L 3 -C {} | head -200')
        else
            set dst (cat $PATH_BOOKMARK | fzf -e --tac --no-sort --preview 'tree -L 3 -C {} | head -200')
        end
    end

    test -n "$dst"; or return 1

    __dotfiles_remove_path_bookmark "$dst"
    echo "$dst" >>$PATH_BOOKMARK
    builtin cd -- "$dst"
end

function get
    mv -i $argv .
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
    set -l target $argv[1]
    if contains -- $argv[1] -h -v
        set layout $argv[1]
        set target $argv[2]
    end
    test -n "$target"; or return 1

    switch $layout
        case -h
            tmux split-window -h -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 $target"
            tmux split-window -h "sudo grc --colour=auto mtr -6 -b -i 0.1 $target"
        case '*'
            tmux split-window -v -p 66 "sudo grc --colour=auto mtr -4 -b -i 0.1 $target"
            tmux split-window -v "sudo grc --colour=auto mtr -6 -b -i 0.1 $target"
    end
end

function dk
    set -l sub $argv[1]
    set -e argv[1]

    switch $sub
        case art rt
            docker start $argv
        case op
            docker stop $argv
        case im
            docker images $argv
        case bd
            docker build $argv
        case ex
            docker exec $argv
        case kl
            docker kill $argv
        case lg
            docker logs $argv
        case pl
            if test (count $argv) -eq 0
                for image in (docker images --format '{{.Repository}}:{{.Tag}}' --filter 'dangling=false' | grep -v '<none>' | fzf --multi)
                    docker pull $image
                end
            else if test "$argv[1]" = ubuntu
                docker pull ghcr.io/mi2428/ubuntu:latest
            else
                docker pull $argv
            end
        case cc
            docker commit $argv
        case vl
            docker volume $argv
        case rmi
            if test (count $argv) -eq 0
                set -l images (docker images --format '{{.Repository}}:{{.Tag}}' --filter 'dangling=false' | grep -v '<none>' | fzf --multi)
                test -n "$images"; and docker rmi $images
            else
                docker rmi $argv
            end
        case '*'
            docker $sub $argv
    end
end

function dcx
    set -l name $argv[1]
    set -e argv[1]
    if test (count $argv) -eq 0
        set argv /bin/bash
    end
    docker compose exec $name $argv
end

function dot
    if test (count $argv) -eq 0
        cd $HOME/dotfiles
        return 0
    end

    set -l sub $argv[1]
    set -e argv[1]

    switch $sub
        case cc commit
            set -l message (string join ' ' -- $argv)
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git add . >/dev/null 2>&1
                and git commit -m "$message"
            end
        case k keep
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git add . >/dev/null 2>&1
                and git commit -m "keep: "(date)
            end
        case d diff
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git diff-index --quiet HEAD
                or git diff
            end
        case lg log
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and tig
            end
        case pl pull
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git pull
            end
        case ps push
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git push
            end
        case s sync
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git pull
                and git push
            end
        case upgrade
            if test (uname) = Darwin
                brew upgrade
                and xargs cargo install --force <$HOME/dotfiles/init/pkgs/cargo.txt
                and xargs pip3 install --upgrade <$HOME/dotfiles/init/pkgs/python3-pip.txt
                and xargs -n 1 go install <$HOME/dotfiles/init/pkgs/go.txt
            end
        case rollback
            begin
                builtin cd $HOME/dotfiles 2>/dev/null
                and git checkout .
            end
        case actions
            if command -sq open
                open https://github.com/mi2428/dotfiles/actions https://github.com/mi2428/ubuntu/actions
            else
                echo 'open your browser and visit:'
                echo ' - https://github.com/mi2428/dotfiles/actions'
                echo ' - https://github.com/mi2428/ubuntu/actions'
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
            echo '     upgrade           run package upgrade'
            echo '     rollback          alias of `git checkout .` command'
            echo '     actions           open GitHub Actions'
            echo ' h,  help              this help text'
    end
end

function addr
    set -l addrtxt $HOME/io/addr/addr.txt
    set -l keyword $argv[1]

    if not test -f $addrtxt
        echo "missing: $addrtxt"
        return 1
    end

    pushd (dirname $addrtxt) >/dev/null 2>&1

    if test -z "$keyword"
        bat $addrtxt
    else if test "$keyword" = --edit
        git pull 2>/dev/null; or true
        $EDITOR $addrtxt
        git add $addrtxt 2>/dev/null
        and git commit -m "keep: "(date) 2>/dev/null
        and git push 2>/dev/null
        or true
    else
        set -l data (cat $addrtxt | grep -v '^#' | grep -v '^$' | grep -i -- "$keyword")
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
    switch (file -b -- $filepath)
        case 'PEM certificate'
            openssl x509 -in $filepath -noout -text
    end
end

function man
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
        PATH=$HOME/bin:$PATH \
        command man $argv
end

function tgz
    env COPYFILE_DISABLE=1 tar zcvf $argv[1] --exclude=.DS_Store $argv[2..-1]
end

function ipapi
    if test (count $argv) -gt 0
        curl -s http://ip-api.com/json/$argv[1] | jq .
    else
        curl -s http://ip-api.com/json | jq .
    end
end

function ghc
    set -l repo $argv[1]
    if test (count $argv) -eq 2
        set repo $argv[1]/$argv[2]
    end
    git clone --recursive git@github.com:$repo
end

function sshsocks
    ssh -C -D $argv[2] -f -N $argv[1]
end

function xx
    switch $argv[1]
        case '*.tar.gz' '*.tgz'
            tar xzvf $argv[1]
        case '*.tar.xz'
            tar Jxvf $argv[1]
        case '*.zip'
            unzip $argv[1]
        case '*.lzh'
            lha e $argv[1]
        case '*.tar.bz2' '*.tbz'
            tar xjvf $argv[1]
        case '*.tar.Z'
            tar zxvf $argv[1]
        case '*.gz'
            gzip -d $argv[1]
        case '*.bz2'
            bzip2 -dc $argv[1]
        case '*.Z'
            uncompress $argv[1]
        case '*.tar'
            tar xvf $argv[1]
        case '*.arj'
            unarj $argv[1]
    end
end

function dotenv
    set -l envfile $argv[1]
    if test -z "$envfile"; and test -f .env
        set envfile .env
    end
    test -f $envfile; or return 1
    __dotfiles_import_posix_exports $envfile
end

function io
    if test (count $argv) -eq 0
        cd $HOME/io
    end
end

function ::
    herdr $argv
end

function :::
    tmux $argv
end

function __dotfiles_herdr_pane_label_for_pane --argument-names pane_id
    set -l process_info (herdr pane process-info --pane $pane_id 2>/dev/null)
    test $status -eq 0; or return 1

    set -l label (printf '%s\n' $process_info | jq -r '
        .result.process_info as $info
        | ($info.foreground_processes[0] // null) as $proc
        | if $proc == null then "" else ($proc.argv0 // $proc.name // ($proc.argv[0]? // "")) end
    ')

    set label (string split '/' -- $label | tail -n 1)
    set label (string replace -r '^-' '' -- (string trim -- $label))

    test -n "$label"; and printf '%s\n' $label
end

function __dotfiles_sync_herdr_pane_label --argument-names pane_id dry_run
    set -l pane_info (herdr pane get $pane_id 2>/dev/null)
    test $status -eq 0; or return 0

    set -l current_label (printf '%s\n' $pane_info | jq -r '.result.pane.label // ""')
    set -l next_label (__dotfiles_herdr_pane_label_for_pane $pane_id)
    test -n "$next_label"; or return 0
    test "$current_label" = "$next_label"; and return 0

    if test "$dry_run" = 1
        printf '%s\t%s\t%s\n' $pane_id $current_label $next_label
        return 0
    end

    herdr pane rename $pane_id $next_label >/dev/null
end

function herdr-pane-labels
    argparse 'i/interval=' 'o/once' 'd/dry-run' 'h/help' -- $argv
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
            __dotfiles_sync_herdr_pane_label $pane_id (set -q _flag_dry_run; and echo 1; or echo 0)
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

    set -l cache_dir $HOME/.cache/herdr-pane-labels
    mkdir -p $cache_dir

    set -l lock_key (string replace -a '/' '_' -- $HERDR_SOCKET_PATH)
    set -l pidfile $cache_dir/$lock_key.pid

    if test -f $pidfile
        set -l existing_pid (string trim -- (cat $pidfile 2>/dev/null))
        if string match -qr '^[0-9]+$' -- $existing_pid
            if kill -0 $existing_pid 2>/dev/null
                return 0
            end
        end
        rm -f $pidfile
    end

    set -l source_file (path resolve (functions --details herdr-pane-labels))
    set -l command "source "(string escape -- $source_file)"; herdr-pane-labels"

    nohup env DOTFILES_HERDR_PANE_LABEL_WATCHER=1 fish -c "$command" >/dev/null 2>&1 &
    set -l watcher_pid $last_pid
    disown $watcher_pid
    printf '%s\n' $watcher_pid >$pidfile
end

__dotfiles_start_herdr_pane_labels

function gk
    set -l target $argv
    if test (count $target) -eq 0
        set target (dirname (git rev-parse --git-dir))
    end

    git add $target
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
    set -l selected (command git status -s | fzf -m --ansi --preview="echo {} | awk '{print \$2}' | xargs git diff --color" | awk '{print $2}')
    if test -n "$selected"
        git add $selected
        echo "Completed: git add $selected"
    end
end

function fe
    set -l files (fzf-tmux --query="$argv[1]" --multi --select-1 --exit-0)
    test -n "$files"; and $EDITOR $files
end

function fkill
    set -l pid (ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if test -n "$pid"
        echo $pid | xargs kill -$argv[1]
    end
end

function dor
    set -l image (docker images --format '{{.Repository}}:{{.Tag}}' --filter 'dangling=false' | fzf)
    test -n "$image"; and docker run -it $argv $image
end

function ffind
    for key in $argv
        find . -name "*$key*" | grep --color=auto -- "$key"
    end
end

function tenki
    curl http://wttr.in/$argv[1]
end

function copy-aws-session
    mkdir -p ~/.cache
    printf '%s\n' \
        " export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
        " export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" \
        " export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
        " export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" \
        >$HOME/.cache/zsh__copy_aws_session.cache
    echo 'AWS session copied.'
end

function paste-aws-session
    set -l cache $HOME/.cache/zsh__copy_aws_session.cache
    set -l session (cat $cache 2>/dev/null)

    if not test -f $cache; or test -z "$session"
        echo 'Missing cached session.'
        return 1
    end

    if test "$argv[1]" = -e
        printf '%s' $session | pbcopy 2>/dev/null
        printf '%s' $session
    else
        printf '%s' $session | sed -e 's/ export //g' -e 's/=/\t/'
    end

    echo
    for line in (printf '%s\n' $session)
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

    set -l namespace (kubectl get namespaces -o custom-columns=':metadata.name' --no-headers 2>/dev/null | fzf --prompt='namespace> ')
    or return 0

    test -n "$namespace"; or return 0
    kubectl config set-context $context --namespace=$namespace
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

function _toggle_path_bookmark
    if grep -Fxq -- $PWD $PATH_BOOKMARK 2>/dev/null
        __dotfiles_remove_path_bookmark $PWD
    else
        echo $PWD >>$PATH_BOOKMARK
    end
end

function _sanitize_history
    set -l history_path $HOME/.local/share/fish/fish_history
    test -f $history_path; or return 0

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
' $history_path
end
