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

def model_import: {
  models: (
    [
      hidden_model("sacloud.preview/Kimi-K2.7-Code"; "Sakura Kimi K2.7 Code")
    ]
    + [{
      id: "sacloud.kimi-k2.7-code",
      base_model_id: "sacloud.preview/Kimi-K2.7-Code",
      name: "Sakura Kimi K2.7 Code",
      meta: {hidden: false, tags: [{name: "Kimi"}], skillIds: [], toolIds: ["image_inspect"]},
      params: {function_calling: "native", max_tokens: 32768, reasoning_effort: "max"},
      access_grants: [],
      is_active: true
    }]
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
  image_inspect_tool: {
    id: "image_inspect",
    name: "Inspect Image",
    content: $image_inspect_tool,
    meta: {provisioned_by: "dotfiles:image-inspect-tool"},
    access_grants: []
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
    "sacloud.llm-jp-3.1-8x13b-instruct4", "sacloud.preview/Qwen3-0.6B-cpu",
    "sacloud.preview/Phi-4-mini-instruct-cpu", "sacloud.preview/Qwen3-Embedding-4B-FP16",
    "sacloud.preview/gemma-4-31B-it", "sacloud.preview/Qwen3.6-35B-A3B",
    "sacloud.whisper-large-v3-turbo", "sacloud.preview/Qwen3-VL-30B-A3B-Instruct",
    "sacloud.multilingual-e5-large", "sacloud.gpt-oss-120b",
    "groq.groq/compound", "groq.groq/compound-mini",
    "groq.openai/gpt-oss-120b", "groq.openai/gpt-oss-20b",
    "groq.qwen/qwen3.6-27b", "groq.qwen/qwen3.8-27b",
    "sacloud.gemma-4-31b-it-low", "sacloud.gemma-4-31b-it-high", "sacloud.gemma-4-31b-it-max",
    "sacloud.qwen3.6-35b-a3b-high", "sacloud.qwen3.6-35b-a3b-max",
    "gpt-oss-120b-low", "gpt-oss-120b-medium", "gpt-oss-120b-high",
    "sacloud.preview/Kimi-K2.6",
    "sacloud.kimi-k2.6-low", "sacloud.kimi-k2.6-medium",
    "sacloud.kimi-k2.6-high", "sacloud.kimi-k2.6-max",
    "kimi-k2.6-low", "kimi-k2.6-medium", "kimi-k2.6-high", "kimi-k2.6-max"
  ],
  required_visible_model_ids: ["sacloud.kimi-k2.7-code"]
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
| require(all($desired.model_import.models[]; .meta.toolIds == (if .id == "sacloud.kimi-k2.7-code" then ["image_inspect"] else [] end)); "unexpected model tool bindings")
| require(($desired.image_inspect_tool.content | length) > 0; "image inspection tool is required")
| require($desired.image_inspect_tool.meta.provisioned_by == "dotfiles:image-inspect-tool"; "image inspection tool marker mismatch")
| ($desired.model_import.models | map(select(.id == "sacloud.kimi-k2.7-code"))) as $kimi_k27
| require(($kimi_k27 | length) == 1; "Kimi K2.7 Code alias must be unique")
| require($kimi_k27[0].meta.hidden == false; "Kimi K2.7 Code alias must be visible")
| require($kimi_k27[0].base_model_id == "sacloud.preview/Kimi-K2.7-Code"; "Kimi K2.7 Code alias base mismatch")
| require($kimi_k27[0].params.reasoning_effort == "max"; "Kimi K2.7 Code alias must use max reasoning effort")
| require($kimi_k27[0].params.function_calling == "native"; "Kimi K2.7 Code alias must use native function calling")
| require($kimi_k27[0].params.max_tokens == 32768; "Kimi K2.7 Code alias must cap output")
