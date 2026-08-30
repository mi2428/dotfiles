#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:?repository root is required}"
profile_file="$repo_root/containers/open-webui/assets/profile.webp"

: "${WEBUI_ADMIN_USERNAME:?set WEBUI_ADMIN_USERNAME}"
: "${WEBUI_ADMIN_EMAIL:?set WEBUI_ADMIN_EMAIL}"
: "${WEBUI_ADMIN_PASSWORD:?set WEBUI_ADMIN_PASSWORD}"

base_url="http://127.0.0.1:${OPEN_WEBUI_PORT:-38080}"
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

# The Sakura subset represents the speed/accuracy Pareto frontier as of August 2026.
jq -n \
  'def model($id; $name): {
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
  {models:
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
    + hidden_variants("sacloud.preview/Kimi-K2.7-Code"; "sacloud.kimi-k2.7-code"; "Sakura Kimi K2.7 Code"; "Kimi"; ["low", "medium", "high", "max"])
    + hidden_variants("sacloud.preview/Kimi-K2.6"; "kimi-k2.6"; "Kimi K2.6"; "Kimi"; ["low", "medium", "high", "max"])
    + hidden_variants("sacloud.preview/Kimi-K2.7-Code"; "kimi-k2.7-code"; "Kimi K2.7 Code"; "Kimi"; ["low", "medium", "high", "max"])
    + hidden_variants("sacloud.gpt-oss-120b"; "gpt-oss-120b"; "GPT-OSS 120B"; "GPT-OSS"; ["low", "medium", "high"])
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

jq -e 'length == 9 and all(.[];
    . == "sacloud.preview/Kimi-K2.7-Code" or
    test("^sacloud\\.gemma-4-31b-it-(low|high|max)$") or
    test("^sacloud\\.qwen3\\.6-35b-a3b-(high|max)$") or
    test("^sacloud\\.kimi-k2\\.6-(low|high|max)$"))' \
  <<<"$model_order_list" >/dev/null

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
