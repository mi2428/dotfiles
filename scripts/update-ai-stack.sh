#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
version=${1:-}

if [ -z "$version" ]; then
    if ! command -v npm >/dev/null 2>&1; then
        printf '%s\n' 'update-ai-stack: npm is required when OMO_VERSION is omitted' >&2
        exit 1
    fi
    version=$(npm view oh-my-openagent version)
fi

case "$version" in
    *[!0-9A-Za-z.+-]*|'')
        printf 'update-ai-stack: invalid OmO version: %s\n' "$version" >&2
        exit 1
        ;;
esac

schema_url="https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/v${version}/assets/omo.schema.json"
if ! curl -fsSL "$schema_url" >/dev/null; then
    printf 'update-ai-stack: schema does not exist for v%s\n' "$version" >&2
    exit 1
fi

replace_to_file() {
    source_file=$1
    expression=$2
    temporary_file=$(mktemp "${source_file}.XXXXXX")
    sed -E "$expression" "$source_file" > "$temporary_file"
    chmod --reference="$source_file" "$temporary_file" 2>/dev/null || chmod 0644 "$temporary_file"
    mv "$temporary_file" "$source_file"
}

replace_to_file \
    "$repo_root/home/files/config/opencode/opencode.jsonc" \
    "s/oh-my-openagent(@[0-9A-Za-z.+-]+)?/oh-my-openagent@${version}/g"
replace_to_file \
    "$repo_root/home/files/config/opencode/tui.json" \
    "s/oh-my-openagent(@[0-9A-Za-z.+-]+)?/oh-my-openagent@${version}/g"
replace_to_file \
    "$repo_root/home/files/omo/omo.jsonc" \
    "s#https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/[^\"]+/assets/omo.schema.json#${schema_url}#g"

printf 'Pinned oh-my-openagent and its schema to %s.\n' "$version"
