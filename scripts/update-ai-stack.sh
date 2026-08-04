#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
omo_version=${1:-}
slim_version=${2:-}

if [ -z "$omo_version" ] || [ -z "$slim_version" ]; then
    if ! command -v npm >/dev/null 2>&1; then
        printf '%s\n' 'update-ai-stack: npm is required when a plugin version is omitted' >&2
        exit 1
    fi
fi

if [ -z "$omo_version" ]; then
    omo_version=$(npm view oh-my-openagent version)
fi
if [ -z "$slim_version" ]; then
    slim_version=$(npm view oh-my-opencode-slim version)
fi

validate_version() {
    label=$1
    version=$2
    if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)*$'; then
        printf 'update-ai-stack: invalid %s version: %s\n' "$label" "$version" >&2
        exit 1
    fi
}

validate_version OmO "$omo_version"
validate_version Slim "$slim_version"

verify_package_version() {
    package=$1
    version=$2
    if ! curl -fsSL "https://registry.npmjs.org/${package}/${version}" >/dev/null; then
        printf 'update-ai-stack: npm package does not publish %s@%s\n' "$package" "$version" >&2
        exit 1
    fi
}

verify_package_version oh-my-openagent "$omo_version"
verify_package_version oh-my-opencode-slim "$slim_version"

schema_url="https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/v${omo_version}/assets/omo.schema.json"
if ! curl -fsSL "$schema_url" >/dev/null; then
    printf 'update-ai-stack: schema does not exist for OmO v%s\n' "$omo_version" >&2
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
    "$repo_root/home/files/config/opencode/profiles/omo/opencode.jsonc" \
    "s/oh-my-openagent(@[0-9A-Za-z.+-]+)?/oh-my-openagent@${omo_version}/g"
replace_to_file \
    "$repo_root/home/files/config/opencode/profiles/omo/tui.json" \
    "s/oh-my-openagent(@[0-9A-Za-z.+-]+)?/oh-my-openagent@${omo_version}/g"
replace_to_file \
    "$repo_root/home/files/omo/omo.jsonc" \
    "s#https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/[^\"]+/assets/omo.schema.json#${schema_url}#g"
replace_to_file \
    "$repo_root/home/files/config/opencode/profiles/slim/opencode.jsonc" \
    "s/oh-my-opencode-slim(@[0-9A-Za-z.+-]+)?/oh-my-opencode-slim@${slim_version}/g"
replace_to_file \
    "$repo_root/home/files/config/opencode/profiles/slim/tui.json" \
    "s/oh-my-opencode-slim(@[0-9A-Za-z.+-]+)?/oh-my-opencode-slim@${slim_version}/g"

printf 'Pinned oh-my-openagent to %s and oh-my-opencode-slim to %s.\n' "$omo_version" "$slim_version"
