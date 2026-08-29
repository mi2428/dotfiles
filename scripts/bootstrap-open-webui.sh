#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repository root is required}"
profile_file="$repo_root/containers/open-webui/profile.webp"

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

base_url="http://127.0.0.1:${OPEN_WEBUI_PORT:-8080}"
compose=(docker compose -f "$repo_root/containers/open-webui/compose.yml")
marker=/app/backend/data/.profile-provisioned

for _ in {1..90}; do
  if curl -fsS "$base_url/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "$base_url/health" >/dev/null

token="$({
  jq -n \
    --arg email "$WEBUI_ADMIN_EMAIL" \
    --arg password "$WEBUI_ADMIN_PASSWORD" \
    '{email: $email, password: $password}' \
    | curl -fsS "$base_url/api/v1/auths/signin" \
        -H 'Content-Type: application/json' \
        --data-binary @-
} | jq -er '.token')"

jq -n \
  'def model($id; $name): {
    id: $id,
    base_model_id: null,
    name: $name,
    meta: {},
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
      meta: {tags: [{name: $tag}]},
      params: {reasoning_effort: $effort},
      access_grants: [],
      is_active: true
    });
  {models:
    [
      model("llm-jp-3.1-8x13b-instruct4"; "LLM-jp 3.1 8x13B Instruct 4"),
      model("preview/Qwen3-0.6B-cpu"; "Qwen3 0.6B CPU"),
      model("preview/Phi-4-mini-instruct-cpu"; "Phi-4 Mini Instruct CPU"),
      model("preview/Qwen3-Embedding-4B-FP16"; "Qwen3 Embedding 4B FP16"),
      hidden_model("preview/Kimi-K2.6"; "Kimi K2.6"),
      model("preview/gemma-4-31B-it"; "Gemma 4 31B IT"),
      model("preview/Qwen3.6-35B-A3B"; "Qwen3.6 35B A3B"),
      hidden_model("preview/Kimi-K2.7-Code"; "Kimi K2.7 Code"),
      model("whisper-large-v3-turbo"; "Whisper Large V3 Turbo"),
      model("preview/Qwen3-VL-30B-A3B-Instruct"; "Qwen3 VL 30B A3B Instruct"),
      model("multilingual-e5-large"; "Multilingual E5 Large"),
      hidden_model("gpt-oss-120b"; "GPT-OSS 120B")
    ]
    + variants("preview/Kimi-K2.6"; "kimi-k2.6"; "Kimi K2.6"; "Kimi"; ["low", "medium", "high", "max"])
    + variants("preview/Kimi-K2.7-Code"; "kimi-k2.7-code"; "Kimi K2.7 Code"; "Kimi"; ["low", "medium", "high", "max"])
    + variants("gpt-oss-120b"; "gpt-oss-120b"; "GPT-OSS 120B"; "GPT-OSS"; ["low", "medium", "high"])
  }' \
  | curl -fsS "$base_url/api/v1/models/import" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $token" \
      --data-binary @- \
  | jq -e '. == true' \
      >/dev/null

model_order_list="$(
  curl -fsS "$base_url/api/models?refresh=true" \
    -H "Authorization: Bearer $token" \
    | jq -c '[.data[] | select((.info.meta.hidden // false) == false)]
        | sort_by([
            (.name | sub(" (Low|Medium|High|Max)$"; "") | ascii_downcase),
            (if (.name | endswith(" Low")) then 0
             elif (.name | endswith(" Medium")) then 1
             elif (.name | endswith(" High")) then 2
             elif (.name | endswith(" Max")) then 3
             else -1 end),
            .id
          ])
        | map(.id)'
)"

curl -fsS "$base_url/api/v1/configs/models" \
  -H "Authorization: Bearer $token" \
  | jq --argjson order "$model_order_list" '.MODEL_ORDER_LIST = $order' \
  | curl -fsS "$base_url/api/v1/configs/models" \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $token" \
      --data-binary @- \
  | jq -e --argjson order "$model_order_list" '.MODEL_ORDER_LIST == $order' \
      >/dev/null

if ! "${compose[@]}" exec -T open-webui test -f "$marker"; then
  profile_image_url="data:image/webp;base64,$(base64 <"$profile_file" | tr -d '\n')"

  jq -n \
    --arg name "$WEBUI_ADMIN_USERNAME" \
    --arg profile_image_url "$profile_image_url" \
    '{name: $name, profile_image_url: $profile_image_url, bio: null, gender: null, date_of_birth: null}' \
    | curl -fsS "$base_url/api/v1/auths/update/profile" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $token" \
        --data-binary @- \
    | jq -e '.profile_image_url | startswith("data:image/webp;base64,")' \
        >/dev/null

  "${compose[@]}" exec -T open-webui touch "$marker"
fi

printf '%s\n' 'Open WebUI models and profile are ready'
