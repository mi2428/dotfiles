def require($condition; $message):
  if $condition then . else error($message) end;

def sakura_icon:
  (.params.reasoning_effort // "default") as $effort
  | if $effort == "high" then $sakura_icons.max
    elif $effort == "max" then $sakura_icons.default
    else $sakura_icons[$effort] // $sakura_icons.default end;

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
      hidden_model("sacloud.preview/Kimi-K2.7-Code"; "Sakura Kimi K2.7 Code"),
      hidden_model("sacloud.preview/gemma-4-31B-it"; "Sakura Gemma 4 31B IT"),
      hidden_model("sacloud.preview/Qwen3.6-35B-A3B"; "Sakura Qwen3.6 35B A3B"),
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
    + [{
      id: "sacloud.kimi-k2.7-code",
      base_model_id: "sacloud.preview/Kimi-K2.7-Code",
      name: "Sakura Kimi K2.7 Code",
      meta: {hidden: false, tags: [{name: "Kimi"}], skillIds: [], toolIds: []},
      params: {function_calling: "native", max_tokens: 32768},
      access_grants: [],
      is_active: true
    }]
    + hidden_variants("sacloud.gpt-oss-120b"; "gpt-oss-120b"; "GPT-OSS 120B"; "GPT-OSS"; ["low", "medium", "high"])
  )
} | .models |= map(
  if (.id | startswith("sacloud.")) then
    .meta.profile_image_url = sakura_icon
  else
    .
  end
);

({
  user_settings: {ui: {system: $chat_personality, title: {auto: true}}},
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
  retired_model_ids: [
    "sacloud.preview/Kimi-K2.6",
    "sacloud.kimi-k2.6-low", "sacloud.kimi-k2.6-medium",
    "sacloud.kimi-k2.6-high", "sacloud.kimi-k2.6-max",
    "kimi-k2.6-low", "kimi-k2.6-medium", "kimi-k2.6-high", "kimi-k2.6-max"
  ],
  required_visible_model_ids: [
    "sacloud.gemma-4-31b-it-low",
    "sacloud.gemma-4-31b-it-high",
    "sacloud.gemma-4-31b-it-max",
    "sacloud.qwen3.6-35b-a3b-high",
    "sacloud.qwen3.6-35b-a3b-max",
    "sacloud.kimi-k2.7-code"
  ]
})
| . as $desired
| require(($desired.user_settings.ui.system | length) > 0; "chat personality is required")
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
| require(all($sakura_icons[]; startswith("data:image/png;base64,")); "unexpected model icons")
| require(
    ($desired.model_import.models | map(.id) | length)
    == ($desired.model_import.models | map(.id) | unique | length);
    "model import contains duplicate IDs"
  )
| require(all($desired.model_import.models[]; .meta.skillIds == []); "regular models must not enable skills")
| require(all($desired.model_import.models[]; .meta.toolIds == []); "regular models must not enable external tools")
| ($desired.model_import.models | map(select(.id == "sacloud.kimi-k2.7-code"))) as $kimi_k27
| require(($kimi_k27 | length) == 1; "Kimi K2.7 Code alias must be unique")
| require($kimi_k27[0].meta.hidden == false; "Kimi K2.7 Code alias must be visible")
| require($kimi_k27[0].base_model_id == "sacloud.preview/Kimi-K2.7-Code"; "Kimi K2.7 Code alias base mismatch")
| require(($kimi_k27[0].params | has("reasoning_effort") | not); "Kimi K2.7 Code alias must not set reasoning effort")
| require($kimi_k27[0].params.function_calling == "native"; "Kimi K2.7 Code alias must use native function calling")
| require($kimi_k27[0].params.max_tokens == 32768; "Kimi K2.7 Code alias must cap output")
