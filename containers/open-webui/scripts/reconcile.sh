#!/usr/bin/env bash
set -euo pipefail

config_dir="${1:?configuration directory is required}"
mode="${2:-reconcile}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manifest_file="$config_dir/config/kimi-k2.7-deep-research.json"
system_file="$config_dir/config/kimi-k2.7-deep-research-system.md"
geoguessor_system_file="$config_dir/config/geoguessor-system.md"
chat_personality_file="$config_dir/config/chat-personality.md"
skill_file="$config_dir/skills/deep-research/SKILL.md"
renderer_file="$script_dir/render-declarations.jq"
profile_file="$config_dir/assets/profile.webp"
sakura_icon_file="$config_dir/assets/sakura-ai-engine.png"
sakura_icon_low_file="$config_dir/assets/sakura-ai-engine-low.png"
sakura_icon_medium_file="$config_dir/assets/sakura-ai-engine-medium.png"
sakura_icon_high_file="$config_dir/assets/sakura-ai-engine-high.png"
sakura_icon_max_file="$config_dir/assets/sakura-ai-engine-max.png"

for file in \
  "$manifest_file" "$system_file" "$geoguessor_system_file" "$chat_personality_file" "$skill_file" "$renderer_file" \
  "$sakura_icon_file" "$sakura_icon_low_file" "$sakura_icon_medium_file" \
  "$sakura_icon_high_file" "$sakura_icon_max_file"; do
  [[ -r "$file" ]] || { printf 'Missing %s\n' "$file" >&2; exit 1; }
done

sakura_icons="$(jq -n \
  --arg default "data:image/png;base64,$(base64 <"$sakura_icon_file" | tr -d '\n')" \
  --arg low "data:image/png;base64,$(base64 <"$sakura_icon_low_file" | tr -d '\n')" \
  --arg medium "data:image/png;base64,$(base64 <"$sakura_icon_medium_file" | tr -d '\n')" \
  --arg high "data:image/png;base64,$(base64 <"$sakura_icon_high_file" | tr -d '\n')" \
  --arg max "data:image/png;base64,$(base64 <"$sakura_icon_max_file" | tr -d '\n')" \
  '{default: $default, low: $low, medium: $medium, high: $high, max: $max}')"

desired="$(jq -n \
  --slurpfile manifest "$manifest_file" \
  --argjson sakura_icons "$sakura_icons" \
  --rawfile system "$system_file" \
  --rawfile geoguessor_system "$geoguessor_system_file" \
  --rawfile chat_personality "$chat_personality_file" \
  --rawfile content "$skill_file" \
  -f "$renderer_file")"
model_import="$(jq -c '.model_import' <<<"$desired")"

if [[ "$mode" == --dry-run ]]; then
  jq -S . <<<"$desired"
  exit 0
elif [[ "$mode" != reconcile ]]; then
  printf 'Unknown mode: %s\n' "$mode" >&2
  exit 1
fi

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

base_url="${OPEN_WEBUI_INTERNAL_URL:-http://127.0.0.1:${PORT:-8080}}"
api_status=
api_body=

api_request() {
  local method="$1"
  local path="$2"
  local payload="${3-}"
  local raw
  local -a args=(
    --silent --show-error
    --connect-timeout 5 --max-time 60
    --request "$method"
    --header "Authorization: Bearer $token"
    --write-out $'\n%{http_code}'
  )

  if [[ -n "$payload" ]]; then
    args+=(--header 'Content-Type: application/json' --data-binary "$payload")
  fi

  raw="$(curl "${args[@]}" "$base_url$path")"
  api_status="${raw##*$'\n'}"
  api_body="${raw%$'\n'*}"
}

expect_success() {
  local operation="$1"
  local detail
  if [[ ! "$api_status" =~ ^2[0-9][0-9]$ ]]; then
    detail="$(jq -r '.detail // empty' <<<"$api_body" 2>/dev/null || true)"
    printf '%s failed with HTTP %s%s\n' "$operation" "$api_status" "${detail:+: $detail}" >&2
    exit 1
  fi
}

urlencode() {
  jq -rn --arg value "$1" '$value | @uri'
}

auth_response="$({
  jq -n \
    --arg email "$WEBUI_ADMIN_EMAIL" \
    --arg password "$WEBUI_ADMIN_PASSWORD" \
    '{email: $email, password: $password}' \
    | curl -fsS --connect-timeout 5 --max-time 60 "$base_url/api/v1/auths/signin" \
        -H 'Content-Type: application/json' \
        --data-binary @-
})"
token="$(jq -er '.token' <<<"$auth_response")"
owner_id="$(jq -er '.id' <<<"$auth_response")"

# Only the prompt is an enforced user override; static UI defaults stay in Compose.
api_request GET '/api/v1/users/user/settings?raw=true'
expect_success 'raw user settings GET'
user_settings="$(jq -c --argjson desired "$desired" \
  '.ui = ((.ui // {}) + $desired.user_settings.ui)' <<<"$api_body")"
if ! jq -e --argjson expected "$user_settings" '. == $expected' <<<"$api_body" >/dev/null; then
  api_request POST /api/v1/users/user/settings/update "$user_settings"
  expect_success 'user settings update'
fi
api_request GET /api/v1/users/user/settings
expect_success 'merged user settings GET'
jq -e --argjson desired "$desired" \
  '.ui.system == $desired.user_settings.ui.system and .ui.widescreenMode == true' \
  <<<"$api_body" >/dev/null

api_request POST /api/v1/models/import "$model_import"
expect_success 'model import'
jq -e '. == true' <<<"$api_body" >/dev/null

# Open WebUI exposes provider bases and custom variants through separate import views.
for endpoint in base export; do
  api_request GET "/api/v1/models/$endpoint"
  expect_success "model $endpoint GET for Sakura icons"
  sakura_icon_patch="$(
    jq -c --argjson icons "$sakura_icons" '
      def sakura_icon: $icons[(.params.reasoning_effort // "default")] // $icons.default;
      {models: [
      .[]
      | select(.id | startswith("sacloud."))
      | select(.meta.profile_image_url != sakura_icon)
      | .meta.profile_image_url = sakura_icon
    ]}' <<<"$api_body"
  )"
  if [[ "$(jq '.models | length' <<<"$sakura_icon_patch")" -gt 0 ]]; then
    api_request POST /api/v1/models/import "$sakura_icon_patch"
    expect_success "model $endpoint Sakura icon update"
    jq -e '. == true' <<<"$api_body" >/dev/null
  fi
done

grant_projection='[.[] | {principal_type, principal_id, permission}] | sort_by([.principal_type, .principal_id, .permission])'

model_projection() {
  jq -cS "
    {
      id,
      base_model_id,
      name,
      meta: (.meta | del(.chat_variables_schema)),
      params,
      access_grants: ((.access_grants // []) | $grant_projection),
      is_active
    }
  " <<<"$1"
}

skill_projection() {
  jq -cS "
    {
      id,
      name,
      description,
      content,
      meta,
      is_active,
      access_grants: ((.access_grants // []) | $grant_projection)
    }
  " <<<"$1"
}

folder_projection() {
  jq -cS '{
    name,
    provisioned_by: .meta.provisioned_by,
    icon: .meta.icon,
    system_prompt: .data.system_prompt,
    files: .data.files
  }' <<<"$1"
}

managed_marker="$(jq -r '.marker' <<<"$desired")"
desired_model="$(jq -c '.model' <<<"$desired")"
desired_skill="$(jq -c '.skill' <<<"$desired")"
desired_folder="$(jq -c '.folder' <<<"$desired")"
model_id="$(jq -r '.id' <<<"$desired_model")"
skill_id="$(jq -r '.id' <<<"$desired_skill")"
folder_name="$(jq -r '.name' <<<"$desired_folder")"
folder_marker="$(jq -r '.meta.provisioned_by' <<<"$desired_folder")"
desired_model_projection="$(model_projection "$desired_model")"
desired_skill_projection="$(skill_projection "$desired_skill")"
desired_folder_projection="$(folder_projection "$desired_folder")"

assert_model_owner_and_marker() {
  jq -e --arg owner "$owner_id" --arg marker "$managed_marker" \
    '.user_id == $owner and .meta.provisioned_by == $marker' \
    <<<"$1" >/dev/null \
    || { printf 'Refusing unmanaged or foreign model ID: %s\n' "$model_id" >&2; exit 1; }
}

verify_model() {
  api_request GET "/api/v1/models/model?id=$(urlencode "$model_id")"
  expect_success "model GET $model_id"
  assert_model_owner_and_marker "$api_body"
  [[ "$(model_projection "$api_body")" == "$desired_model_projection" ]] \
    || { printf 'Model projection mismatch: %s\n' "$model_id" >&2; exit 1; }
}

get_skill_export() {
  api_request GET /api/v1/skills/export
  expect_success 'skill export'
  skill_export_row="$(
    jq -cer --arg id "$skill_id" \
      '[.[] | select(.id == $id)] | if length == 1 then .[0] else error("managed skill missing or duplicated") end' \
      <<<"$api_body"
  )"
}

assert_skill_owner_and_marker() {
  jq -e --arg owner "$owner_id" --arg marker "$managed_marker" \
    '.user_id == $owner and ((.meta.tags // []) | index($marker)) != null' \
    <<<"$1" >/dev/null \
    || { printf 'Refusing unmanaged or foreign skill ID: %s\n' "$skill_id" >&2; exit 1; }
}

verify_skill() {
  api_request GET "/api/v1/skills/id/$(urlencode "$skill_id")"
  expect_success "skill GET $skill_id"
  assert_skill_owner_and_marker "$api_body"
  get_skill_export
  assert_skill_owner_and_marker "$skill_export_row"
  [[ "$(skill_projection "$skill_export_row")" == "$desired_skill_projection" ]] \
    || { printf 'Skill projection mismatch: %s\n' "$skill_id" >&2; exit 1; }
}

assert_folder_owner_and_marker() {
  jq -e --arg owner "$owner_id" --arg marker "$folder_marker" \
    '.user_id == $owner and .meta.provisioned_by == $marker' \
    <<<"$1" >/dev/null \
    || { printf 'Refusing unmanaged or foreign folder: %s\n' "$folder_name" >&2; exit 1; }
}

verify_folder() {
  api_request GET "/api/v1/folders/$(urlencode "$folder_id")"
  expect_success "folder GET $folder_name"
  assert_folder_owner_and_marker "$api_body"
  [[ "$(folder_projection "$api_body")" == "$desired_folder_projection" ]] \
    || { printf 'Folder projection mismatch: %s\n' "$folder_name" >&2; exit 1; }
}

api_request GET "/api/v1/skills/id/$(urlencode "$skill_id")"
case "$api_status" in
  200)
    assert_skill_owner_and_marker "$api_body"
    get_skill_export
    if [[ "$(skill_projection "$skill_export_row")" != "$desired_skill_projection" ]]; then
      api_request POST "/api/v1/skills/id/$(urlencode "$skill_id")/update" "$desired_skill"
      expect_success "skill update $skill_id"
    fi
    ;;
  404)
    api_request POST /api/v1/skills/create "$desired_skill"
    expect_success "skill create $skill_id"
    ;;
  *)
    expect_success "skill GET $skill_id"
    ;;
esac
verify_skill

api_request GET "/api/v1/models/model?id=$(urlencode "$model_id")"
case "$api_status" in
  200)
    assert_model_owner_and_marker "$api_body"
    if [[ "$(model_projection "$api_body")" != "$desired_model_projection" ]]; then
      api_request POST /api/v1/models/model/update "$desired_model"
      expect_success "model update $model_id"
    fi
    ;;
  404)
    api_request POST /api/v1/models/create "$desired_model"
    expect_success "model create $model_id"
    ;;
  *)
    expect_success "model GET $model_id"
    ;;
esac
verify_model

api_request GET /api/v1/folders/
expect_success 'folder list'
folder_matches="$(
  jq -c --arg name "$folder_name" \
    '[.[] | select(.parent_id == null and (.name | ascii_downcase) == ($name | ascii_downcase))]' \
    <<<"$api_body"
)"

case "$(jq 'length' <<<"$folder_matches")" in
  0)
    api_request POST /api/v1/folders/ "$desired_folder"
    expect_success "folder create $folder_name"
    folder_id="$(jq -er '.id' <<<"$api_body")"
    ;;
  1)
    folder_id="$(jq -er '.[0].id' <<<"$folder_matches")"
    api_request GET "/api/v1/folders/$(urlencode "$folder_id")"
    expect_success "folder GET $folder_name"
    assert_folder_owner_and_marker "$api_body"
    if [[ "$(folder_projection "$api_body")" != "$desired_folder_projection" ]]; then
      api_request POST "/api/v1/folders/$(urlencode "$folder_id")/update" \
        "$(jq -c 'del(.parent_id)' <<<"$desired_folder")"
      expect_success "folder update $folder_name"
    fi
    ;;
  *)
    printf 'Multiple root folders named %s\n' "$folder_name" >&2
    exit 1
    ;;
esac
verify_folder

api_request GET /api/v1/models/export
expect_success 'model export'
model_export="$api_body"
while IFS=$'\t' read -r stale_id stale_owner; do
  [[ -n "$stale_id" ]] || continue
  [[ "$stale_owner" == "$owner_id" ]] \
    || { printf 'Refusing to delete foreign managed model: %s\n' "$stale_id" >&2; exit 1; }
  api_request POST /api/v1/models/model/delete "$(jq -nc --arg id "$stale_id" '{id: $id}')"
  expect_success "model delete $stale_id"
  jq -e '. == true' <<<"$api_body" >/dev/null
done < <(
  jq -r --arg marker "$managed_marker" --arg desired_id "$model_id" \
    '.[] | select(.meta.provisioned_by == $marker and .id != $desired_id) | [.id, .user_id] | @tsv' \
    <<<"$model_export"
)

api_request GET /api/v1/skills/export
expect_success 'skill export for cleanup'
skill_export="$api_body"
while IFS=$'\t' read -r stale_id stale_owner; do
  [[ -n "$stale_id" ]] || continue
  [[ "$stale_owner" == "$owner_id" ]] \
    || { printf 'Refusing to delete foreign managed skill: %s\n' "$stale_id" >&2; exit 1; }
  api_request DELETE "/api/v1/skills/id/$(urlencode "$stale_id")/delete"
  expect_success "skill delete $stale_id"
  jq -e '. == true' <<<"$api_body" >/dev/null
done < <(
  jq -r --arg marker "$managed_marker" --arg desired_id "$skill_id" \
    '.[] | select((((.meta.tags // []) | index($marker)) != null) and .id != $desired_id) | [.id, .user_id] | @tsv' \
    <<<"$skill_export"
)

# Open WebUI v0.11.1 builds the effective UI registry through this pinned endpoint.
api_request GET '/api/models?refresh=true'
expect_success 'model registry refresh'
model_order_list="$(
  jq -c '[.data[] | select((.info.meta.hidden // false) == false)]
        | sort_by([
            (.name | sub(" (Low|Medium|High|Max)$"; "") | ascii_downcase),
            (if (.name | endswith(" Low")) then 0
             elif (.name | endswith(" Medium")) then 1
             elif (.name | endswith(" High")) then 2
             elif (.name | endswith(" Max")) then 3
             else -1 end),
            .id
          ])
        | map(.id)' <<<"$api_body"
)"

required_visible_model_ids="$(jq -c '.required_visible_model_ids' <<<"$desired")"
jq -e --argjson required "$required_visible_model_ids" '($required - .) == []' \
  <<<"$model_order_list" >/dev/null

api_request GET /api/v1/configs/models
expect_success 'model config GET'
model_config="$(jq -c --argjson order "$model_order_list" '.MODEL_ORDER_LIST = $order' <<<"$api_body")"
api_request POST /api/v1/configs/models "$model_config"
expect_success 'model config update'
jq -e --argjson order "$model_order_list" '.MODEL_ORDER_LIST == $order' <<<"$api_body" >/dev/null

verify_model
verify_skill
verify_folder
for endpoint in base export; do
  api_request GET "/api/v1/models/$endpoint"
  expect_success "model $endpoint GET for Sakura icon verification"
  jq -e --argjson icons "$sakura_icons" \
    'def sakura_icon: $icons[(.params.reasoning_effort // "default")] // $icons.default;
    all(.[] | select(.id | startswith("sacloud.")); .meta.profile_image_url == sakura_icon)' \
    <<<"$api_body" >/dev/null \
    || { printf 'Sakura model icon mismatch in %s\n' "$endpoint" >&2; exit 1; }
done

profile_image_url="data:image/webp;base64,$(base64 <"$profile_file" | tr -d '\n')"
profile_payload="$(jq -n \
  --arg name "$WEBUI_ADMIN_USERNAME" \
  --arg profile_image_url "$profile_image_url" \
  --argjson current "$auth_response" \
  '{
    name: $name,
    profile_image_url: $profile_image_url,
    bio: ($current.bio // null),
    gender: ($current.gender // null),
    date_of_birth: ($current.date_of_birth // null)
  }')"

profile_matches() {
  local response="$1"
  local current_image
  jq -e --arg name "$WEBUI_ADMIN_USERNAME" '.name == $name' <<<"$response" >/dev/null \
    || return 1
  current_image="$(jq -r '.profile_image_url // empty' <<<"$response")"
  case "$current_image" in
    data:image/webp\;base64,*) [[ "$current_image" == "$profile_image_url" ]] ;;
    /api/v1/users/*/profile/image)
      curl -fsS --connect-timeout 5 --max-time 60 \
        --header "Authorization: Bearer $token" "$base_url$current_image" \
        | cmp -s "$profile_file" -
      ;;
    *) return 1 ;;
  esac
}

profile_response="$auth_response"
if ! profile_matches "$profile_response"; then
  api_request POST /api/v1/auths/update/profile "$profile_payload"
  expect_success 'profile update'
  profile_response="$api_body"
fi
profile_matches "$profile_response" \
  || { printf '%s\n' 'Profile projection mismatch' >&2; exit 1; }

printf '%s\n' 'Open WebUI models, settings, Deep Research Skill, and profile are ready'
