#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
plugin_versions="$repo_root/home/files/config/opencode/plugin-versions.json"
slim_version=${1:-}

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'update-ai-stack: jq is required' >&2
    exit 1
fi

if [ -z "$slim_version" ]; then
    if ! command -v npm >/dev/null 2>&1; then
        printf '%s\n' 'update-ai-stack: npm is required when a plugin version is omitted' >&2
        exit 1
    fi
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

validate_version Slim "$slim_version"

verify_package_version() {
    package=$1
    version=$2
    if ! curl -fsSL "https://registry.npmjs.org/${package}/${version}" >/dev/null; then
        printf 'update-ai-stack: npm package does not publish %s@%s\n' "$package" "$version" >&2
        exit 1
    fi
}

verify_package_version oh-my-opencode-slim "$slim_version"

versions_temporary=$(mktemp "${plugin_versions}.XXXXXX")
jq --arg slim "$slim_version" \
    '.slim = $slim' \
    "$plugin_versions" > "$versions_temporary"
chmod --reference="$plugin_versions" "$versions_temporary" 2>/dev/null || chmod 0644 "$versions_temporary"
mv "$versions_temporary" "$plugin_versions"

printf 'Pinned oh-my-opencode-slim to %s.\n' "$slim_version"
