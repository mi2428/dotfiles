#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Reconciliation failed at line %s (status %s)\n" "$LINENO" "$?" >&2' ERR

# Render repository declarations into one desired state. Dry-run mode performs no API calls;
# live mode updates only resources carrying this repository's ownership markers and fails
# closed on unmanaged ID or name collisions before deleting or replacing anything.
config_dir="${1:?configuration directory is required}"
mode="${2:-reconcile}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
geoguessor_system_file="$config_dir/config/geoguessor-system.md"
github_oss_translation_system_file="$config_dir/config/github-oss-translation-system.md"
movie_akinator_system_file="$config_dir/config/movie-akinator-system.md"
books_movies_subculture_system_file="$config_dir/config/books-movies-subculture-system.md"
chat_personality_file="$config_dir/config/chat-personality.md"
renderer_file="$script_dir/render-declarations.jq"
profile_file="$config_dir/assets/profile.webp"
sakura_icon_file="$config_dir/assets/sakura-ai-engine.png"
sakura_icon_low_file="$config_dir/assets/sakura-ai-engine-low.png"
sakura_icon_medium_file="$config_dir/assets/sakura-ai-engine-medium.png"
sakura_icon_high_file="$config_dir/assets/sakura-ai-engine-high.png"
sakura_icon_max_file="$config_dir/assets/sakura-ai-engine-max.png"

for file in \
  "$geoguessor_system_file" "$github_oss_translation_system_file" \
  "$movie_akinator_system_file" \
  "$books_movies_subculture_system_file" \
  "$chat_personality_file" "$renderer_file" \
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
  --argjson sakura_icons "$sakura_icons" \
  --rawfile geoguessor_system "$geoguessor_system_file" \
  --rawfile github_oss_translation_system "$github_oss_translation_system_file" \
  --rawfile movie_akinator_system "$movie_akinator_system_file" \
  --rawfile books_movies_subculture_system "$books_movies_subculture_system_file" \
  --rawfile chat_personality "$chat_personality_file" \
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
    args+=(--header 'Content-Type: application/json' --data-binary @-)
    raw="$(curl "${args[@]}" "$base_url$path" <<<"$payload")"
  else
    raw="$(curl "${args[@]}" "$base_url$path")"
  fi
  api_status="${raw##*$'\n'}"
  api_body="${raw%$'\n'*}"
}

expect_success() {
  local operation="$1"
  if [[ ! "$api_status" =~ ^2[0-9][0-9]$ ]]; then
    printf '%s failed with HTTP %s\n' "$operation" "$api_status" >&2
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

# Enforce user-specific prompt and title behavior; static UI defaults stay in Compose.
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
  '.ui.system == $desired.user_settings.ui.system
    and .ui.title.auto == true
    and .ui.widescreenMode == true' \
  <<<"$api_body" >/dev/null

regular_model_ids="$(jq -c '[.models[].id]' <<<"$model_import")"
model_list_projection() {
  local source="$1"
  jq -cS --argjson ids "$regular_model_ids" '
    [
      .[]
      | select(.id as $id | $ids | index($id))
      | {
          id, base_model_id, name,
          meta: (.meta | del(.chat_variables_schema)),
          params,
          access_grants: ((.access_grants // [])
            | map({principal_type, principal_id, permission})
            | sort_by([.principal_type, .principal_id, .permission])),
          is_active
        }
    ] | sort_by(.id)
  ' <<<"$source"
}
desired_regular_models="$(model_list_projection "$(jq -c '.models' <<<"$model_import")")"
api_request GET /api/v1/models/export
expect_success 'regular model idempotence check'
current_regular_models="$(jq -cS --argjson desired "$desired_regular_models" '
  def normalize:
    {
      id, base_model_id, name,
      meta: (.meta | del(.chat_variables_schema)),
      params,
      access_grants: ((.access_grants // [])
        | map({principal_type, principal_id, permission})
        | sort_by([.principal_type, .principal_id, .permission])),
      is_active
    };
  def project($actual; $template):
    $template
    | if type == "object" then
        reduce keys_unsorted[] as $key ({};
          .[$key] = project($actual[$key]; $template[$key]))
      else $actual end;
  . as $actual
  | [
      $desired[] as $expected
      | [$actual[] | select(.id == $expected.id) | normalize] as $matches
      | if ($matches | length) == 1 then project($matches[0]; $expected) else null end
    ]
  | sort_by(.id)
' <<<"$api_body")"
if [[ "$current_regular_models" != "$desired_regular_models" ]]; then
  api_request POST /api/v1/models/import "$model_import"
  expect_success 'model import'
  jq -e '. == true' <<<"$api_body" >/dev/null
fi

# Open WebUI exposes provider bases and custom variants through separate import views.
for endpoint in base export; do
  api_request GET "/api/v1/models/$endpoint"
  expect_success "model $endpoint GET for Sakura icons"
  sakura_icon_patch="$(
    jq -c --argjson icons "$sakura_icons" '
      def sakura_icon:
        (.params.reasoning_effort // "default") as $effort
        | if $effort == "high" then $icons.max
          elif $effort == "max" then $icons.default
          else $icons[$effort] // $icons.default end;
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

folder_projection() {
  jq -cS '{
    name,
    parent_id: (.parent_id // null),
    provisioned_by: .meta.provisioned_by,
    icon: .meta.icon,
    system_prompt: .data.system_prompt,
    files: .data.files
  }' <<<"$1"
}

desired_folder="$(jq -c '.folder' <<<"$desired")"
desired_translation_folder="$(jq -c '.translation_folder' <<<"$desired")"
desired_movie_akinator_folder="$(jq -c '.movie_akinator_folder' <<<"$desired")"
desired_books_movies_subculture_folder="$(jq -c '.books_movies_subculture_folder' <<<"$desired")"

assert_folder_owner_and_marker() {
  local response="$1"
  local folder_name="$2"
  local folder_marker="$3"
  jq -e --arg owner "$owner_id" --arg marker "$folder_marker" \
    '.user_id == $owner and .meta.provisioned_by == $marker' \
    <<<"$response" >/dev/null \
    || { printf 'Refusing unmanaged or foreign folder: %s\n' "$folder_name" >&2; exit 1; }
}

verify_folder() {
  local folder_id="$1"
  local desired_folder="$2"
  local folder_name folder_marker desired_folder_projection
  folder_name="$(jq -r '.name' <<<"$desired_folder")"
  folder_marker="$(jq -r '.meta.provisioned_by' <<<"$desired_folder")"
  desired_folder_projection="$(folder_projection "$desired_folder")"
  api_request GET "/api/v1/folders/$(urlencode "$folder_id")"
  expect_success "folder GET $folder_name"
  assert_folder_owner_and_marker "$api_body" "$folder_name" "$folder_marker"
  [[ "$(folder_projection "$api_body")" == "$desired_folder_projection" ]] \
    || { printf 'Folder projection mismatch: %s\n' "$folder_name" >&2; exit 1; }
}

managed_folder_ids=()

find_managed_folder_ids() {
  local folder_marker="$1"
  local folder_list folder_id
  managed_folder_ids=()
  api_request GET /api/v1/folders/
  expect_success 'folder list'
  folder_list="$api_body"
  while IFS= read -r folder_id; do
    api_request GET "/api/v1/folders/$(urlencode "$folder_id")"
    expect_success 'folder GET for marker lookup'
    if jq -e --arg owner "$owner_id" --arg marker "$folder_marker" \
      '.user_id == $owner and .meta.provisioned_by == $marker' \
      <<<"$api_body" >/dev/null; then
      managed_folder_ids+=("$folder_id")
    fi
  done < <(jq -r '.[].id' <<<"$folder_list")
}

upsert_folder() {
  local desired_folder="$1"
  local folder_name folder_marker parent_id folder_list folder_matches folder_id
  local current_parent_id desired_folder_projection parent_payload
  folder_name="$(jq -r '.name' <<<"$desired_folder")"
  folder_marker="$(jq -r '.meta.provisioned_by' <<<"$desired_folder")"
  parent_id="$(jq -r '.parent_id // empty' <<<"$desired_folder")"
  desired_folder_projection="$(folder_projection "$desired_folder")"

  find_managed_folder_ids "$folder_marker"
  api_request GET /api/v1/folders/
  expect_success 'folder list'
  folder_list="$api_body"
  folder_matches="$(
    jq -c --arg name "$folder_name" --arg parent_id "$parent_id" \
      '[.[] | select(((.parent_id // "") == $parent_id)
        and (.name | ascii_downcase) == ($name | ascii_downcase))]' \
      <<<"$folder_list"
  )"

  case "${#managed_folder_ids[@]}" in
    0)
      [[ "$(jq 'length' <<<"$folder_matches")" == 0 ]] \
        || { printf 'Refusing unmanaged folder: %s\n' "$folder_name" >&2; exit 1; }
      api_request POST /api/v1/folders/ "$desired_folder"
      expect_success "folder create $folder_name"
      folder_id="$(jq -er '.id' <<<"$api_body")"
      ;;
    1)
      folder_id="${managed_folder_ids[0]}"
      jq -e --arg id "$folder_id" '[.[] | select(.id != $id)] | length == 0' \
        <<<"$folder_matches" >/dev/null \
        || { printf 'Folder name is already in use: %s\n' "$folder_name" >&2; exit 1; }
      api_request GET "/api/v1/folders/$(urlencode "$folder_id")"
      expect_success "folder GET $folder_name"
      assert_folder_owner_and_marker "$api_body" "$folder_name" "$folder_marker"
      current_parent_id="$(jq -r '.parent_id // empty' <<<"$api_body")"
      if [[ "$current_parent_id" != "$parent_id" ]]; then
        parent_payload="$(jq -nc --arg parent_id "$parent_id" \
          '{parent_id: (if $parent_id == "" then null else $parent_id end)}')"
        api_request POST "/api/v1/folders/$(urlencode "$folder_id")/update/parent" "$parent_payload"
        expect_success "folder move $folder_name"
      fi
      if [[ "$(folder_projection "$api_body")" != "$desired_folder_projection" ]]; then
        api_request POST "/api/v1/folders/$(urlencode "$folder_id")/update" \
          "$(jq -c 'del(.parent_id)' <<<"$desired_folder")"
        expect_success "folder update $folder_name"
      fi
      ;;
    *)
      printf 'Multiple managed folders use marker: %s\n' "$folder_marker" >&2
      exit 1
      ;;
  esac

  verify_folder "$folder_id" "$desired_folder"
  upserted_folder_id="$folder_id"
}

delete_empty_managed_folder() {
  local folder_marker="$1"
  local folder_id folder_list
  find_managed_folder_ids "$folder_marker"
  case "${#managed_folder_ids[@]}" in
    0) return ;;
    1) folder_id="${managed_folder_ids[0]}" ;;
    *) printf 'Multiple managed folders use marker: %s\n' "$folder_marker" >&2; exit 1 ;;
  esac
  api_request GET /api/v1/folders/
  expect_success 'folder list before cleanup'
  folder_list="$api_body"
  jq -e --arg id "$folder_id" '[.[] | select(.parent_id == $id)] | length == 0' \
    <<<"$folder_list" >/dev/null \
    || { printf 'Refusing to delete a managed folder with children: %s\n' "$folder_id" >&2; exit 1; }
  api_request DELETE "/api/v1/folders/$(urlencode "$folder_id")?delete_contents=false"
  expect_success 'managed folder cleanup'
  jq -e '. == true' <<<"$api_body" >/dev/null
}

upserted_folder_id=
upsert_folder "$desired_folder"
geoguessor_folder_id="$upserted_folder_id"
upsert_folder "$desired_translation_folder"
translation_folder_id="$upserted_folder_id"
delete_empty_managed_folder dotfiles:translation-folder
upsert_folder "$desired_movie_akinator_folder"
movie_akinator_folder_id="$upserted_folder_id"
upsert_folder "$desired_books_movies_subculture_folder"
books_movies_subculture_folder_id="$upserted_folder_id"

# Open WebUI v0.11.3 builds the effective UI registry through this pinned endpoint.
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
if ! jq -e --argjson order "$model_order_list" '.MODEL_ORDER_LIST == $order' <<<"$api_body" >/dev/null; then
  api_request POST /api/v1/configs/models "$model_config"
  expect_success 'model config update'
  jq -e --argjson order "$model_order_list" '.MODEL_ORDER_LIST == $order' <<<"$api_body" >/dev/null
fi

verify_folder "$geoguessor_folder_id" "$desired_folder"
verify_folder "$translation_folder_id" "$desired_translation_folder"
verify_folder "$movie_akinator_folder_id" "$desired_movie_akinator_folder"
verify_folder "$books_movies_subculture_folder_id" "$desired_books_movies_subculture_folder"
for endpoint in base export; do
  api_request GET "/api/v1/models/$endpoint"
  expect_success "model $endpoint GET for Sakura icon verification"
  jq -e --argjson icons "$sakura_icons" \
    'def sakura_icon:
      (.params.reasoning_effort // "default") as $effort
      | if $effort == "high" then $icons.max
        elif $effort == "max" then $icons.default
        else $icons[$effort] // $icons.default end;
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

printf '%s\n' 'Open WebUI models, settings, folders, and profile are ready'
