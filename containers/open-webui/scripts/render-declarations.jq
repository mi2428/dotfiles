def require($condition; $message):
  if $condition then . else error($message) end;

def sakura_icon:
  $sakura_icons[(.params.reasoning_effort // "default")] // $sakura_icons.default;

def model($id; $name): {
  id: $id,
  base_model_id: null,
  name: $name,
  meta: {hidden: false, skillIds: [], toolIds: []},
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
    meta: {hidden: false, tags: [{name: $tag}], skillIds: [], toolIds: []},
    params: {reasoning_effort: $effort},
    access_grants: [],
    is_active: true
  });

def kimi_system($effort):
  "あなたは日本語で高品質な分析と調査を行う。最終回答は自然な日本語だけで記述し、固有名詞、コード、URL、必要な直接引用を除いて中国語・英語・韓国語を混入させない。送信前に言語と文章の破損を点検する。回答前に現実の現在日時を確認する。事実、推論、不明点を区別し、必要に応じて説明的な見出し、箇条書き、表で構造化する。Web調査では一次資料を優先し、重要な主張には出典URLを付け、資料間の矛盾と残る不確実性を明示する。" +
  (if $effort == "low" then
     " 正確性を保つ最小限の分析を行い、明白でない重要主張を一度検証してから、要旨を先に簡潔に答える。サブエージェントは使わない。"
   elif $effort == "high" then
     " 速度より品質を優先する。最初に作業を分解し、複数の根拠を照合し、反対仮説を検討する。独立した調査が複数ある場合は delegate_task で最大2件を並列化し、統合後に漏れと矛盾を一度監査してから答える。"
   elif $effort == "max" then
     " 速度や簡潔さより完全性と情報密度を優先する。単一の親セッションで作業を細かく分解し、独立した調査・検証を delegate_task で最大4件並列化する。親は各結果を比較統合し、欠落や矛盾があれば不足だけ追加検証して、前提、論点、根拠、反対仮説、具体例、限界まで展開する。別の外部エージェントループには委譲せず、利用可能な出力長を十分に使って詳細に答える。"
   else
     ""
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
      description:
        (if $effort == "low" then
           "素早さを優先し、必要な確認を行いながら要点を簡潔に回答します。"
         elif $effort == "high" then
           "複数の観点と根拠を照合し、必要に応じて2件まで並行調査して回答します。"
         else
           "最大4件の調査を並行し、根拠・反証・具体例・限界まで掘り下げた詳細な回答を作成します。"
         end),
      capabilities: {web_search: true},
      builtinTools: {subagents: ($effort != "low"), web_search: true},
      skillIds: [],
      toolIds: []
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

# The Sakura subset represents the speed/accuracy Pareto frontier as of August 2026.
def model_import: {
  models: (
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
  )
} | .models |= map(
  if (.id | startswith("sacloud.")) then
    .meta.profile_image_url = sakura_icon
  else
    .
  end
);

($manifest[0] | {
  marker: .marker,
  user_settings: {ui: {system: $chat_personality, title: {auto: true}}},
  model: (.model | .params.system = $system | .meta.profile_image_url = $sakura_icons.default),
  status_filter: {
    id: "deep_research_status",
    name: "Deep Research Status",
    content: $status_filter_content,
    meta: {
      description: "Deep Research開始直後の進捗を表示します。",
      provisioned_by: .marker
    }
  },
  skill: (.skill | .content = $content),
  folder: {
    name: "GeoGuessor",
    parent_id: null,
    meta: {provisioned_by: "dotfiles:geoguessor-folder", icon: "earth_asia"},
    data: {system_prompt: $geoguessor_system, files: []}
  },
  translation_folder: {
    name: "翻訳（エンジニア）",
    parent_id: null,
    meta: {provisioned_by: "dotfiles:github-oss-translation-folder", icon: "left_right_arrow"},
    data: {system_prompt: $github_oss_translation_system, files: []}
  },
  movie_akinator_folder: {
    name: "映画アキネーター",
    parent_id: null,
    meta: {provisioned_by: "dotfiles:movie-akinator-folder", icon: "clapper"},
    data: {system_prompt: $movie_akinator_system, files: []}
  },
  books_movies_subculture_folder: {
    name: "本・映画・サブカル",
    parent_id: null,
    meta: {provisioned_by: "dotfiles:books-movies-subculture-folder", icon: "books"},
    data: {system_prompt: $books_movies_subculture_system, files: []}
  },
  model_import: model_import,
  required_visible_model_ids: [
    "sacloud.preview/Kimi-K2.7-Code",
    .model.id,
    "sacloud.gemma-4-31b-it-low",
    "sacloud.gemma-4-31b-it-high",
    "sacloud.gemma-4-31b-it-max",
    "sacloud.qwen3.6-35b-a3b-high",
    "sacloud.qwen3.6-35b-a3b-max",
    "sacloud.kimi-k2.6-low",
    "sacloud.kimi-k2.6-high",
    "sacloud.kimi-k2.6-max"
  ]
})
| . as $desired
| require($desired.marker != ""; "managed marker is required")
| require(($desired.user_settings.ui.system | length) > 0; "chat personality is required")
| require($desired.model.meta.provisioned_by == $desired.marker; "model marker mismatch")
| require(($desired.skill.meta.tags | index($desired.marker)) != null; "skill marker mismatch")
| require($desired.folder.meta.provisioned_by == "dotfiles:geoguessor-folder"; "folder marker mismatch")
| require($desired.folder.data.files == []; "GeoGuessor folder must not attach knowledge")
| require($desired.translation_folder.parent_id == null; "translation folder must be a root folder")
| require(($desired.translation_folder.data.system_prompt | length) > 0; "translation prompt is required")
| require($desired.translation_folder.data.files == []; "translation folder must not attach knowledge")
| require($desired.movie_akinator_folder.parent_id == null; "movie Akinator must be a root folder")
| require(($desired.movie_akinator_folder.data.system_prompt | length) > 0; "movie Akinator prompt is required")
| require($desired.movie_akinator_folder.data.files == []; "movie Akinator must not attach knowledge")
| require($desired.books_movies_subculture_folder.parent_id == null; "books, movies, and subculture must be a root folder")
| require(($desired.books_movies_subculture_folder.data.system_prompt | length) > 0; "books, movies, and subculture prompt is required")
| require($desired.books_movies_subculture_folder.data.files == []; "books, movies, and subculture folder must not attach knowledge")
| require($desired.model.base_model_id == "sacloud.preview/Kimi-K2.7-Code"; "unexpected base model")
| require($desired.model.params.function_calling == "native"; "native function calling is required")
| require($desired.model.params.max_tokens == 32768; "max_tokens must be 32768")
| require(all($sakura_icons[]; startswith("data:image/png;base64,")); "unexpected model icons")
| require(($desired.model.params | has("reasoning_effort") | not); "reasoning_effort is unsupported")
| require($desired.model.meta.capabilities.web_search == false; "built-in web search must stay disabled")
| require($desired.model.meta.capabilities.code_interpreter == false; "code interpreter must stay disabled")
| require($desired.model.meta.capabilities.citations == true; "citations capability is required")
| require($desired.model.meta.capabilities.usage == true; "usage capability is required")
| require($desired.model.meta.builtinTools.notes == false; "Notes must stay disabled")
| require($desired.model.meta.builtinTools.time == false; "Time must stay disabled")
| require($desired.model.meta.builtinTools.user_input == false; "User input must stay disabled")
| require($desired.model.meta.builtinTools.subagents == false; "sub-agents must stay disabled")
| require($desired.model.meta.builtinTools.code_interpreter == false; "Code Interpreter must stay disabled")
| require($desired.model.meta.builtinTools.knowledge == false; "Knowledge must remain disabled")
| require($desired.model.meta.defaultFeatureIds == []; "default features must stay disabled")
| require($desired.model.meta.filterIds == ["deep_research_status"]; "unexpected Deep Research filters")
| require($desired.model.meta.skillIds == []; "the outer model must not load an extra research skill")
| require($desired.model.meta.toolIds == ["server:deep-research"]; "the external research tool must be the only default tool")
| require(($desired.model.access_grants | length) == 0; "model must be owner-only")
| require(($desired.skill.access_grants | length) == 0; "skill must be owner-only")
| require(
    ($desired.model_import.models | map(.id) | length)
    == ($desired.model_import.models | map(.id) | unique | length);
    "model import contains duplicate IDs"
  )
| require(all($desired.model_import.models[]; .meta.skillIds == []); "regular models must not enable skills")
| require(all($desired.model_import.models[]; .meta.toolIds == []); "regular models must not enable external tools")
| ($desired.model_import.models[] | select(.id == "sacloud.kimi-k2.6-low")) as $kimi_low
| ($desired.model_import.models[] | select(.id == "sacloud.kimi-k2.6-high")) as $kimi_high
| ($desired.model_import.models[] | select(.id == "sacloud.kimi-k2.6-max")) as $kimi_max
| require($kimi_low.meta.builtinTools.subagents == false; "Kimi Low must not enable sub-agents")
| require(($kimi_low.meta.description | contains("簡潔")); "Kimi Low description must explain its concise behavior")
| require($kimi_high.meta.builtinTools.subagents == true; "Kimi High must enable sub-agents")
| require(($kimi_high.params.system | contains("最大2件")); "Kimi High must use at most two parallel sub-agents")
| require(($kimi_high.meta.description | contains("2件")); "Kimi High description must explain its parallel behavior")
| require($kimi_max.meta.capabilities.web_search == true; "Kimi Max must support web search")
| require($kimi_max.meta.builtinTools.subagents == true; "Kimi Max must enable sub-agents")
| require(($kimi_max.params.system | contains("最大4件")); "Kimi Max must use at most four parallel sub-agents")
| require(($kimi_max.meta.description | contains("4件")); "Kimi Max description must explain its parallel behavior")
| require(($kimi_max.params.system | contains("deep_research") | not); "Kimi Max must not delegate research")
