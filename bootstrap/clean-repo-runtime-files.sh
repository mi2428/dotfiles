#!/bin/sh
set -eu

repo_root=$(
    CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd
)
config_root=$repo_root/home/files/config

if [ ! -d "$config_root" ]; then
    exit 0
fi

find "$config_root" \
    \( -type s -o -type p -o -type b -o -type c \) \
    -print |
while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf 'dotfiles: removing unsupported runtime file %s\n' "$path" >&2
    rm -f -- "$path"
done
