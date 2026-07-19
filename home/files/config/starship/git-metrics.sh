#!/usr/bin/env bash
# shellcheck shell=bash

# Synchronous prompt-path invariants:
#
# * A fresh-cache render uses Bash built-ins only: no Git, Python, jq, hashing,
#   stat, or date process is allowed here.
# * Cache entries are keyed by the working-directory path rather than the
#   repository root. This intentionally trades small duplicate snapshots for
#   avoiding a synchronous `git rev-parse` or external hash on every prompt.
# * A stale snapshot is rendered immediately; one detached refresh is then
#   started under an atomic lock. The newly collected state appears on the next
#   prompt instead of delaying the current one.
# * Negative snapshots apply the same policy outside Git repositories, which is
#   why Starship's custom-module `when` can remain the boolean true.
#
# The one-second TTL is intentionally aggressive. Timestamps have whole-second
# precision, so the effective fresh interval is zero to one second rather than
# exactly one second. Refresh remains demand-driven: an idle shell does no work.
# This favors quick +N/-N feedback after file changes while retaining a fast
# cached render between refreshes.

__starship_git_metrics_main() {
    [[ ${1-} == summary ]] || return 0

    local cache_home=${XDG_CACHE_HOME:-"$HOME/.cache"}
    local cache_dir="${cache_home}/starship/git-metrics-v2/by-cwd${PWD}"
    local cache_file="${cache_dir}/snapshot.json"
    local lock_file="${cache_dir}/refresh.lock"
    local helper_path=${BASH_SOURCE[0]}
    local helper_dir=${helper_path%/*}
    local payload=
    local updated_at=0
    local now
    local needs_refresh=1
    local added=0
    local deleted=0
    local status_symbols=
    local -r cache_ttl_seconds=1

    if [[ $helper_path != */* ]]; then
        helper_dir=.
    fi

    printf -v now '%(%s)T' -1

    if [[ -r $cache_file ]]; then
        payload=$(<"$cache_file")

        if [[ $payload =~ \"updated_at\":([0-9]+) ]]; then
            updated_at=${BASH_REMATCH[1]}
            if ((now - updated_at < cache_ttl_seconds)); then
                needs_refresh=0
            fi
        fi

        if [[ $payload =~ \"inside_work_tree\":true ]]; then
            [[ $payload =~ \"added\":([0-9]+) ]] && added=${BASH_REMATCH[1]}
            [[ $payload =~ \"deleted\":([0-9]+) ]] && deleted=${BASH_REMATCH[1]}
            [[ $payload =~ \"status_symbols\":\"([^\"]*)\" ]] && status_symbols=${BASH_REMATCH[1]}
        fi
    fi

    if ((needs_refresh)); then
        __starship_git_metrics_spawn_refresh "$cache_dir" "$cache_file" "$lock_file" "$helper_dir/git-metrics.py" "$now"
    fi

    if ((added > 0)); then
        printf '\033[1;38;2;%sm +%s\033[0m' "${CTP_GREEN_RGB:-166;227;161}" "$added"
    fi
    if ((deleted > 0)); then
        printf '\033[1;38;2;%sm -%s\033[0m' "${CTP_RED_RGB:-243;139;168}" "$deleted"
    fi
    if [[ -n $status_symbols ]]; then
        printf '\033[1;38;2;%sm %s\033[0m' "${CTP_PEACH_RGB:-250;179;135}" "$status_symbols"
    fi
}

__starship_git_metrics_spawn_refresh() {
    local cache_dir=$1
    local cache_file=$2
    local lock_file=$3
    local refresh_helper=$4
    local now=$5
    local lock_started_at=0
    local -r lock_stale_seconds=30

    if [[ -r $lock_file ]]; then
        IFS= read -r lock_started_at <"$lock_file" || true
        if [[ $lock_started_at =~ ^[0-9]+$ ]] && ((now - lock_started_at >= lock_stale_seconds)); then
            command rm -f -- "$lock_file"
        fi
    fi

    if [[ ! -d $cache_dir ]]; then
        command mkdir -p -- "$cache_dir" || return 0
    fi

    # noclobber turns the redirection into an atomic create-if-absent lock. It
    # avoids another mkdir process on the latency-sensitive stale-prompt path.
    if ! (set -o noclobber; printf '%s\n' "$now" >"$lock_file") 2>/dev/null; then
        return 0
    fi

    command python3 "$refresh_helper" --refresh-locked "$PWD" "$cache_file" "$lock_file" \
        </dev/null >/dev/null 2>&1 &
}

__starship_git_metrics_main "$@"
