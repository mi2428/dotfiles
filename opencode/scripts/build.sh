#!/usr/bin/env bash
set -euo pipefail

root=$(git -C "$(dirname "${BASH_SOURCE[0]}")/../.." rev-parse --show-toplevel)
upstream="$root/opencode/opencode"
patch="$root/opencode/patches/router.patch"
pinned=$(git -C "$root" rev-parse HEAD:opencode/opencode)
actual=$(git -C "$upstream" rev-parse HEAD)
if [[ "$actual" != "$pinned" || -n "$(git -C "$upstream" status --porcelain)" ]]; then
  printf 'OpenCode submodule must be clean and at %s\n' "$pinned" >&2
  exit 1
fi

temp=$(mktemp -d "${TMPDIR:-/tmp}/opencode-router.XXXXXX")
worktree="$temp/source"
cleanup() {
  if [[ -d "$worktree" ]]; then
    git -C "$upstream" worktree remove --force "$worktree"
  fi
  rmdir "$temp"
}
trap cleanup EXIT

git -C "$upstream" worktree add --detach "$worktree" "$pinned"
git -C "$worktree" apply --check "$patch"
git -C "$worktree" apply "$patch"
bun install --cwd "$worktree" --frozen-lockfile
bun test --cwd "$worktree/packages/tui" test/cli/tui/router-model.test.ts
bun run --cwd "$worktree/packages/tui" typecheck

version=$(jq -er '.version' "$worktree/packages/opencode/package.json")
OPENCODE_VERSION="$version" bun run --cwd "$worktree/packages/opencode" script/build.ts --single --skip-install
binary="$worktree/packages/opencode/dist/opencode-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)/bin/opencode"
destination="$HOME/.local/share/dotfiles/opencode-smart-router/bin/opencode"
install -d "$(dirname "$destination")"
install -m 0755 "$binary" "$destination.new"
mv -f "$destination.new" "$destination"
printf 'Installed OpenCode %s (%s) to %s\n' "$version" "$pinned" "$destination"
