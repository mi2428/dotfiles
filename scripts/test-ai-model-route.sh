#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ai-model-route.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

cat >"$tmp/ollaya" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$tmp/curl" <<'EOF'
#!/bin/sh
case "$*" in
    *api/version*) printf '%s\n' '{"version":"test"}' ;;
    *)
        [ "${FAKE_FAIL:-0}" != 1 ] || exit 22
        printf '{"answers":{"tier":{"choice":"%s","confidence":%s},"clarity":{"choice":"%s","confidence":%s}}}\n' \
            "${FAKE_TIER:-SIMPLE}" "${FAKE_CONFIDENCE:-0.8}" "${FAKE_CLARITY:-CLEAR}" "${FAKE_CONTEXT_CONFIDENCE:-0.9}"
        ;;
esac
EOF
chmod +x "$tmp/ollaya" "$tmp/curl"

route="$repo_root/home/files/libexec/dotfiles/ai-model-route"
config="$repo_root/home/files/config/opencode/model-router.json"
mkdir -p "$tmp/.config/opencode-profiles/router/opencode"
ln -s "$config" "$tmp/.config/opencode-profiles/router/opencode/model-router.json"
simple_model=$(jq -r '.tiers.SIMPLE | .providerID + "/" + .modelID' "$config")
simple_variant=$(jq -r '.tiers.SIMPLE.variant' "$config")
reasoning_model=$(jq -r '.tiers.REASONING | .providerID + "/" + .modelID' "$config")
reasoning_variant=$(jq -r '.tiers.REASONING.variant' "$config")
fallback_model=$(jq -r '.fallback | .providerID + "/" + .modelID' "$config")
fallback_variant=$(jq -r '.fallback.variant' "$config")
jq -e '[.fallback, (.tiers[])] | all(.providerID and .modelID and .variant)' "$config" >/dev/null

simple=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_TIER=SIMPLE "$route" 'Fix a typo')
printf '%s\n' "$simple" | jq -e --arg model "$simple_model" --arg variant "$simple_variant" '.model == $model and .variant == $variant and .fallback == false' >/dev/null

default=$(env -u OPENCODE_ROUTER_CONFIG HOME="$tmp" PATH="$tmp:$PATH" FAKE_TIER=SIMPLE "$route" 'Fix a typo')
printf '%s\n' "$default" | jq -e --arg model "$simple_model" '.model == $model and .fallback == false' >/dev/null

reasoning=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_TIER=REASONING "$route" 'Prove the security property')
printf '%s\n' "$reasoning" | jq -e --arg model "$reasoning_model" --arg variant "$reasoning_variant" '.model == $model and .variant == $variant and .fallback == false' >/dev/null

uncertain=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_CONFIDENCE=0.1 "$route" 'Ambiguous task')
printf '%s\n' "$uncertain" | jq -e --arg model "$fallback_model" --arg variant "$fallback_variant" '.model == $model and .variant == $variant and .fallback == true and .reason == "low_confidence"' >/dev/null

contextual=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_CLARITY=CONTEXT_REQUIRED FAKE_CONTEXT_CONFIDENCE=0.9 "$route" 'Fix this')
printf '%s\n' "$contextual" | jq -e --arg model "$fallback_model" '.model == $model and .fallback == true and .reason == "context_missing"' >/dev/null

context_uncertain=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_CLARITY=CONTEXT_REQUIRED FAKE_CONFIDENCE=0.1 "$route" 'Unclear task')
printf '%s\n' "$context_uncertain" | jq -e --arg model "$fallback_model" '.model == $model and .fallback == true and .reason == "low_confidence"' >/dev/null

unclear=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_CLARITY=CONTEXT_REQUIRED FAKE_CONTEXT_CONFIDENCE=0.2 "$route" 'Fix a typo')
printf '%s\n' "$unclear" | jq -e --arg model "$simple_model" '.model == $model and .fallback == false' >/dev/null

invalid=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_CLARITY=INVALID "$route" 'Fix this')
printf '%s\n' "$invalid" | jq -e --arg model "$fallback_model" '.model == $model and .fallback == true and .reason == "invalid_context"' >/dev/null

explicit=$(env -u OPENCODE_ROUTER_CONFIG HOME="$tmp" PATH="$tmp:$PATH" FAKE_FAIL=1 "$route" 'これを ROUTER:MAX で検証して')
printf '%s\n' "$explicit" | jq -e --arg model "$reasoning_model" --arg variant "$reasoning_variant" \
    '.tier == "REASONING" and .model == $model and .variant == $variant and .confidence == null and .fallback == false and .reason == "explicit_router_max"' >/dev/null
for text in xhigh prerouter:max router:maximum; do
    not_explicit=$(env -u OPENCODE_ROUTER_CONFIG HOME="$tmp" PATH="$tmp:$PATH" "$route" "$text")
    printf '%s\n' "$not_explicit" | jq -e --arg model "$simple_model" '.model == $model and .fallback == false' >/dev/null
done

unavailable=$(PATH="$tmp:$PATH" OPENCODE_ROUTER_CONFIG="$config" FAKE_FAIL=1 "$route" 'Any task')
printf '%s\n' "$unavailable" | jq -e --arg model "$fallback_model" --arg variant "$fallback_variant" '.model == $model and .variant == $variant and .fallback == true and .reason == "classifier_unavailable"' >/dev/null

printf '%s\n' 'ai-model-route tests passed.'
