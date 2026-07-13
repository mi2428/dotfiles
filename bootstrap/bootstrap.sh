#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v make >/dev/null 2>&1; then
	printf '%s\n' 'bootstrap: make is required' >&2
	exit 1
fi

printf '%s\n' 'bootstrap: Home Manager and chezmoi are the steady-state owners.'
printf '%s\n' 'bootstrap: running the emergency links only.'
make --directory="$repo_root" emergency
