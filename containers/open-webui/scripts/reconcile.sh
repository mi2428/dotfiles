#!/usr/bin/env bash
set -euo pipefail

config_dir="${1:?configuration directory is required}"
mode="${2:-reconcile}"
manifest_file="$config_dir/config/kimi-k2.7-deep-research.json"
system_file="$config_dir/config/kimi-k2.7-deep-research-system.md"
geoguessor_system_file="$config_dir/config/geoguessor-system.md"
chat_personality_file="$config_dir/config/chat-personality.md"
skill_file="$config_dir/skills/deep-research/SKILL.md"
profile_file="$config_dir/assets/profile.webp"
sakura_icon_file="$config_dir/assets/sakura-ai-engine.png"
sakura_icon_low_file="$config_dir/assets/sakura-ai-engine-low.png"
sakura_icon_medium_file="$config_dir/assets/sakura-ai-engine-medium.png"
sakura_icon_high_file="$config_dir/assets/sakura-ai-engine-high.png"
sakura_icon_max_file="$config_dir/assets/sakura-ai-engine-max.png"

for file in \
  "$manifest_file" "$system_file" "$geoguessor_system_file" "$chat_personality_file" "$skill_file" \
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

desired="$({
  jq \
    --argjson sakura_icons "$sakura_icons" \
    --rawfile system "$system_file" \
    --rawfile geoguessor_system "$geoguessor_system_file" \
    --rawfile chat_personality "$chat_personality_file" \
    --rawfile content "$skill_file" \
    '
      def require($condition; $message): if $condition then . else error($message) end;
      {
        marker: .marker,
        chat_personality: $chat_personality,
        model: (.model | .params.system = $system | .meta.profile_image_url = $sakura_icons.default),
        skill: (.skill | .content = $content),
        folder: {
          name: "GeoGuessor",
          parent_id: null,
          meta: {provisioned_by: "dotfiles:geoguessor-folder", icon: "earth_asia"},
          data: {system_prompt: $geoguessor_system, files: []}
        }
      }
      | . as $desired
      | require($desired.marker != ""; "managed marker is required")
      | require(($desired.chat_personality | length) > 0; "chat personality is required")
      | require($desired.model.meta.provisioned_by == $desired.marker; "model marker mismatch")
      | require(($desired.skill.meta.tags | index($desired.marker)) != null; "skill marker mismatch")
      | require($desired.folder.meta.provisioned_by == "dotfiles:geoguessor-folder"; "folder marker mismatch")
      | require($desired.folder.data.files == []; "GeoGuessor folder must not attach knowledge")
      | require($desired.model.base_model_id == "sacloud.preview/Kimi-K2.7-Code"; "unexpected base model")
      | require($desired.model.params.function_calling == "native"; "native function calling is required")
      | require($desired.model.params.max_tokens == 32768; "max_tokens must be 32768")
      | require(all($sakura_icons[]; startswith("data:image/png;base64,")); "unexpected model icons")
      | require(($desired.model.params | has("reasoning_effort") | not); "reasoning_effort is unsupported")
      | require($desired.model.meta.capabilities.web_search == true; "web search capability is required")
      | require($desired.model.meta.capabilities.code_interpreter == true; "code interpreter capability is required")
      | require($desired.model.meta.capabilities.citations == true; "citations capability is required")
      | require($desired.model.meta.capabilities.usage == true; "usage capability is required")
      | require($desired.model.meta.builtinTools.notes == true; "Notes are required")
      | require($desired.model.meta.builtinTools.subagents == true; "Sub-agents are required")
      | require($desired.model.meta.builtinTools.code_interpreter == true; "Code Interpreter is required")
      | require($desired.model.meta.builtinTools.knowledge == false; "Knowledge must remain disabled")
      | require($desired.model.meta.defaultFeatureIds == ["web_search", "code_interpreter"]; "default features must stay enabled")
      | require($desired.model.meta.skillIds == [$desired.skill.id]; "model must attach exactly the managed skill")
      | require(($desired.model.access_grants | length) == 0; "model must be owner-only")
      | require(($desired.skill.access_grants | length) == 0; "skill must be owner-only")
    ' "$manifest_file"
})"

# The Sakura subset represents the speed/accuracy Pareto frontier as of August 2026.
legacy_models="$(jq -n --argjson sakura_icons "$sakura_icons" \
  'def sakura_icon: $sakura_icons[(.params.reasoning_effort // "default")];
  def model($id; $name): {
    id: $id,
    base_model_id: null,
    name: $name,
    meta: {hidden: false},
    params: {},
    access_grants: [],
    is_active: true
  };
  def hidden_model($id; $name):
    model($id; $name) | .meta.hidden = true;
  def variants($base; $slug; $name; $tag; $efforts):
    $efforts
    | map(. as $effort | {
      id: ($slug + "-" + $effort),
      base_model_id: $base,
      name: ($name + " " + (($effort[0:1] | ascii_upcase) + $effort[1:])),
      meta: {hidden: false, tags: [{name: $tag}]},
      params: {reasoning_effort: $effort},
      access_grants: [],
      is_active: true
    });
  def kimi_system($effort):
    "あなたは日本語で高品質な分析と調査を行う。最終回答は自然な日本語だけで記述し、固有名詞、コード、URL、必要な直接引用を除いて中国語・英語・韓国語を混入させない。送信前に言語と文章の破損を点検する。事実、推論、不明点を区別し、必要に応じて説明的な見出し、箇条書き、表で構造化する。Web調査では現在日時を確認し、一次資料を優先し、重要な主張には出典URLを付け、資料間の矛盾と残る不確実性を明示する。" +
    (if $effort == "low" then
       " 正確性を保つ最小限の分析を行い、明白でない重要主張を一度検証してから、要旨を先に簡潔に答える。サブエージェントは使わない。"
     elif $effort == "high" then
       " 速度より品質を優先する。最初に作業を分解し、複数の根拠を照合し、反対仮説を検討する。独立した調査が複数ある場合は delegate_task で最大2件を並列化し、統合後に漏れと矛盾を一度監査してから答える。"
     else
       " 速度、待ち時間、トークン節約を評価対象にせず、利用可能な推論・ツール予算で完全性を最大化する。最初に成功条件と調査計画を定め、独立した論点を delegate_task で2〜4件のフォアグラウンド・サブエージェントへ並列委譲する。各結果の出典と不確実性を照合し、情報の穴が残れば検索と検証を反復する。草稿後に反証役として前提、欠落、引用、数値、言語を監査し、修正した最終回答だけを提示する。長さ自体を目的にせず、必要な詳細を省略しない。"
     end);
  def kimi_variants($base; $slug; $name; $tag; $efforts):
    $efforts
    | map(. as $effort | {
      id: ($slug + "-" + $effort),
      base_model_id: $base,
      name: ($name + " " + (($effort[0:1] | ascii_upcase) + $effort[1:])),
      meta: {
        hidden: false,
        tags: [{name: $tag}],
        capabilities: {web_search: true},
        builtinTools: {subagents: true, web_search: true}
      },
      params: {
        reasoning_effort: $effort,
        function_calling: "native",
        max_tokens: 32000,
        compact_token_threshold:
          (if $effort == "low" then 80000 elif $effort == "high" then 140000 else 180000 end),
        system: kimi_system($effort)
      },
      access_grants: [],
      is_active: true
    });
  def hidden_variants($base; $slug; $name; $tag; $efforts):
    variants($base; $slug; $name; $tag; $efforts) | map(.meta.hidden = true);
  {models: (
    [
      hidden_model("sacloud.llm-jp-3.1-8x13b-instruct4"; "Sakura LLM-jp 3.1 8x13B Instruct 4"),
      hidden_model("sacloud.preview/Qwen3-0.6B-cpu"; "Sakura Qwen3 0.6B CPU"),
      hidden_model("sacloud.preview/Phi-4-mini-instruct-cpu"; "Sakura Phi-4 Mini Instruct CPU"),
      hidden_model("sacloud.preview/Qwen3-Embedding-4B-FP16"; "Sakura Qwen3 Embedding 4B FP16"),
      hidden_model("sacloud.preview/Kimi-K2.6"; "Sakura Kimi K2.6"),
      hidden_model("sacloud.preview/gemma-4-31B-it"; "Sakura Gemma 4 31B IT"),
      hidden_model("sacloud.preview/Qwen3.6-35B-A3B"; "Sakura Qwen3.6 35B A3B"),
      model("sacloud.preview/Kimi-K2.7-Code"; "Sakura Kimi K2.7 Code"),
      hidden_model("sacloud.whisper-large-v3-turbo"; "Sakura Whisper Large V3 Turbo"),
      hidden_model("sacloud.preview/Qwen3-VL-30B-A3B-Instruct"; "Sakura Qwen3 VL 30B A3B Instruct"),
      hidden_model("sacloud.multilingual-e5-large"; "Sakura Multilingual E5 Large"),
      hidden_model("sacloud.gpt-oss-120b"; "Sakura GPT-OSS 120B"),
      hidden_model("groq.groq/compound"; "Groq Compound"),
      hidden_model("groq.groq/compound-mini"; "Groq Compound Mini"),
      hidden_model("groq.openai/gpt-oss-120b"; "Groq GPT-OSS 120B"),
      hidden_model("groq.openai/gpt-oss-20b"; "Groq GPT-OSS 20B"),
      hidden_model("groq.qwen/qwen3.6-27b"; "Groq Qwen3.6 27B"),
      hidden_model("groq.qwen/qwen3.8-27b"; "Groq Qwen3.8 27B")
    ]
    + variants("sacloud.preview/gemma-4-31B-it"; "sacloud.gemma-4-31b-it"; "Sakura Gemma 4 31B IT"; "Gemma"; ["low", "high", "max"])
    + variants("sacloud.preview/Qwen3.6-35B-A3B"; "sacloud.qwen3.6-35b-a3b"; "Sakura Qwen3.6 35B A3B"; "Qwen"; ["high", "max"])
    + kimi_variants("sacloud.preview/Kimi-K2.6"; "sacloud.kimi-k2.6"; "Sakura Kimi K2.6"; "Kimi"; ["low", "high", "max"])
    + hidden_variants("sacloud.preview/Kimi-K2.6"; "sacloud.kimi-k2.6"; "Sakura Kimi K2.6"; "Kimi"; ["medium"])
    + hidden_variants("sacloud.preview/Kimi-K2.6"; "kimi-k2.6"; "Kimi K2.6"; "Kimi"; ["low", "medium", "high", "max"])
    + hidden_variants("sacloud.gpt-oss-120b"; "gpt-oss-120b"; "GPT-OSS 120B"; "GPT-OSS"; ["low", "medium", "high"])
  )} | .models |= map(
    if (.id | startswith("sacloud.")) then
      .meta.profile_image_url = sakura_icon
    else
      .
    end
  )')"

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
profile_marker=/app/backend/data/.profile-provisioned
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

api_request GET /api/v1/users/user/settings
expect_success 'user settings GET'
user_settings="$(jq -c --argjson desired "$desired" '.ui = (.ui // {}) | .ui.system = $desired.chat_personality' <<<"$api_body")"
api_request POST /api/v1/users/user/settings/update "$user_settings"
expect_success 'user settings update'
jq -e --argjson desired "$desired" '.ui.system == $desired.chat_personality' <<<"$api_body" >/dev/null

api_request POST /api/v1/models/import "$legacy_models"
expect_success 'legacy model import'
jq -e '. == true' <<<"$api_body" >/dev/null

for endpoint in base export; do
  api_request GET "/api/v1/models/$endpoint"
  expect_success "model $endpoint GET for Sakura icons"
  sakura_icon_patch="$(
    jq -c --argjson icons "$sakura_icons" '
      def sakura_icon: $icons[(.params.reasoning_effort // "default")];
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

jq -e --arg managed_id "$model_id" '
    ([
      "sacloud.preview/Kimi-K2.7-Code",
      $managed_id,
      "sacloud.gemma-4-31b-it-low",
      "sacloud.gemma-4-31b-it-high",
      "sacloud.gemma-4-31b-it-max",
      "sacloud.qwen3.6-35b-a3b-high",
      "sacloud.qwen3.6-35b-a3b-max",
      "sacloud.kimi-k2.6-low",
      "sacloud.kimi-k2.6-high",
      "sacloud.kimi-k2.6-max"
    ] - .) == []' \
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
    'def sakura_icon: $icons[(.params.reasoning_effort // "default")];
    all(.[] | select(.id | startswith("sacloud.")); .meta.profile_image_url == sakura_icon)' \
    <<<"$api_body" >/dev/null \
    || { printf 'Sakura model icon mismatch in %s\n' "$endpoint" >&2; exit 1; }
done

if [[ ! -f "$profile_marker" ]]; then
  [[ -r "$profile_file" ]] || { printf 'Missing %s\n' "$profile_file" >&2; exit 1; }
  profile_image_url="data:image/webp;base64,$(base64 <"$profile_file" | tr -d '\n')"

  profile_payload="$(jq -n \
    --arg name "$WEBUI_ADMIN_USERNAME" \
    --arg profile_image_url "$profile_image_url" \
    '{name: $name, profile_image_url: $profile_image_url, bio: null, gender: null, date_of_birth: null}')"
  api_request POST /api/v1/auths/update/profile "$profile_payload"
  expect_success 'profile update'
  jq -e '.profile_image_url | startswith("data:image/webp;base64,")' <<<"$api_body" >/dev/null

  touch "$profile_marker"
fi

printf '%s\n' 'Open WebUI models, settings, Deep Research Skill, and profile are ready'
