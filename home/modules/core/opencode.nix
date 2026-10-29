{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkLink = source: {
    force = true;
    inherit source;
  };

  pluginVersions = builtins.fromJSON (
    builtins.readFile ../../files/config/opencode/plugin-versions.json
  );
  slimPlugin = "oh-my-opencode-slim@${pluginVersions.slim}";
  herdrPackage = config.dotfiles.herdr.package;

  openAIModels = {
    "gpt-5.6-sol".settings.reasoningEffort = "xhigh";
    "gpt-5.6-luna".settings.reasoningEffort = "low";
    "gpt-6-sol".settings.reasoningEffort = "max";
    "gpt-6-luna".settings.reasoningEffort = "low";
  };
  slimOpenAIModels = openAIModels // {
    "gpt-5.6-terra".settings.reasoningEffort = "xhigh";
  };

  mkSakuraModel = name: {
    inherit name;
    capabilities = {
      tools = true;
      input = [
        "text"
        "image"
      ];
      output = [ "text" ];
      temperature = false;
      reasoning.supported = true;
    };
    compatibility.reasoningField = "reasoning";
    limit = {
      context = 262144;
      output = 32768;
    };
  };
  sakuraProvider = {
    package = "@opencode/ai/providers/openai-compatible";
    name = "Sakura AI";
    settings = {
      baseURL = "https://sakura-ai-engine-gateway.tailef845a.ts.net/v1";
      timeout = false;
      headerTimeout = false;
      chunkTimeout = false;
    };
    models = {
      # The Gateway supplies max reasoning when omitted; the client owns tools.
      # Its 256K context and 32K output limits are set by mkSakuraModel.
      "preview/Kimi-K2.7-Code" = mkSakuraModel "Sakura Kimi K2.7 Code";
    };
  };

  mkProviders = models: {
    openai = { inherit models; };
    sakura = sakuraProvider;
  };

  commonPermissions = [
    {
      action = "shell";
      resource = "*";
      effect = "allow";
    }
    {
      action = "shell";
      resource = "sudo *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "rm -rf *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "git clean *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "git reset --hard *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "git checkout -- *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "git restore *";
      effect = "ask";
    }
    {
      action = "shell";
      resource = "git push *";
      effect = "ask";
    }
    {
      action = "external_directory";
      resource = "*";
      effect = "ask";
    }
    {
      action = "external_directory";
      resource = "~/obsidian/OpenCode/*";
      effect = "allow";
    }
  ];

  commonOpenCodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    update = "disable";
    share = "disabled";
    agents.title = {
      model = "openai/gpt-6-luna";
      disabled = true;
    };
    lsp = false;
    compaction = {
      auto = true;
      keep.tokens = 15000;
      buffer = 20000;
    };
    experimental.todo = true;
    watcher.ignore = [
      ".git/**"
      ".direnv/**"
      ".devenv/**"
      "node_modules/**"
      "target/**"
      "dist/**"
      "build/**"
      "result"
      "result-*"
    ];
    permissions = commonPermissions;
  };

  ponytailPlugin = {
    package = "${ponytailV2}";
    options.sourceRoot = "${ponytail}";
  };
  mkOpenCodeConfig =
    {
      model,
      models ? openAIModels,
      plugins ? [ ],
    }:
    commonOpenCodeConfig
    // {
      inherit model plugins;
      providers = mkProviders models;
    };

  chatConfig = commonOpenCodeConfig // {
    model = "openai/gpt-6-sol";
    providers = mkProviders openAIModels;
    default_agent = "chat";
    permissions = commonPermissions ++ [
      {
        action = "external_directory";
        resource = "*";
        effect = "deny";
      }
    ];
    agents = commonOpenCodeConfig.agents // {
      build.disabled = true;
      plan.disabled = true;
      general.disabled = true;
      explore.disabled = true;
    };
  };

  commonCliConfig = {
    "$schema" = "https://opencode.ai/v2/cli.json";
    theme.name = "catppuccin-mocha-mauve";
    diffs.view = "auto";
    scroll.acceleration = true;
    attention = {
      notifications = true;
      sound = false;
    };
    keybinds."variant.cycle" = "<leader>v";
  };
  todoCliConfig = commonCliConfig // {
    plugins = [ "./tui-plugins/todo" ];
  };
  herdrCliConfig = todoCliConfig // {
    plugins = todoCliConfig.plugins ++ [ "./herdr-opencode" ];
    session = {
      thinking = "show";
      grouping = "none";
      tps = true;
    };
    tabs = {
      mode = "auto";
      indicators = "status";
    };
  };
  chatCliConfig = commonCliConfig // {
    keybinds = commonCliConfig.keybinds // {
      "agent.list" = "none";
      "agent.cycle" = "none";
      "agent.cycle.reverse" = "none";
    };
  };

  json = pkgs.formats.json { };
  generated = {
    defaultConfig = json.generate "opencode-default.json" (
      (mkOpenCodeConfig {
        model = "openai/gpt-6-sol";
        plugins = [ ponytailPlugin ];
      })
      // {
        skills = [ "${ponytail}/skills" ];
        instructions = [ "${firstThingsFirstInstruction}" ];
      }
    );
    slimConfig = json.generate "opencode-slim.json" (
      (mkOpenCodeConfig {
        model = "amazon-bedrock/global.anthropic.claude-opus-5";
        models = slimOpenAIModels;
        plugins = [ slimPlugin ];
      })
      // {
        instructions = [ "${firstThingsFirstInstruction}" ];
      }
    );
    chatConfig = json.generate "opencode-chat.json" chatConfig;
    todoCli = json.generate "opencode-cli.json" todoCliConfig;
    herdrCli = json.generate "opencode-herdr-cli.json" herdrCliConfig;
    chatCli = json.generate "opencode-chat-cli.json" chatCliConfig;
  };

  todoOverlayPackageRoot = ../../files/config/opencode/plugins/tui;
  todoOverlayOpenCodePackage = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/opencode/tui-plugins/todo";
  ponytailV2 = ../../files/config/opencode/plugins/ponytail-v2;
  firstThingsFirstInstruction = ../../files/config/opencode/policies/first-things-first.md;
  herdrShellEnvPlugin = ../../files/config/opencode/plugins/herdr-shell-env.js;
  sessionTitlePlugin = ../../files/config/opencode/plugins/session-title.js;
  profileShellEnvPlugin = ../../files/config/opencode/plugins/profile-shell-env.js;
  obsidianExportPlugin = ../../files/config/opencode/plugins/obsidian-export.js;
  obsidianExportSkill = ../../files/agents/skills/obsidian-export;
  showmeSkill = ../../files/agents/skills/showme;
  slimOpenCodePluginConfig = ../../files/config/opencode/profiles/slim/oh-my-opencode-slim.jsonc;

  ponytail = pkgs.applyPatches {
    name = "ponytail-no-comment-prefix";
    src = pkgs.fetchFromGitHub {
      owner = "DietrichGebert";
      repo = "ponytail";
      rev = "0a4dd63ad4541f4f655c4108a295916f3c1d8fda";
      hash = "sha256-8cYggVltBAlZ/Zj4pl1bOu7mQdZFXCmDGW4RSpvRA+w=";
    };
    patches = [ ../../files/config/opencode/ponytail-no-comment-prefix.patch ];
  };

  herdrAgentLayout = pkgs.fetchFromGitHub {
    owner = "mi2428";
    repo = "herdr-agent-layout";
    rev = "8498296a84323f53b31229a3bdb3410ce1ba5cdf";
    hash = "sha256-hSCwYyWEYlurYNn4O0v7XUE5SpuMyEca62aTg5iRBXY=";
  };
  herdrAgentLayoutSkill = "${herdrAgentLayout}/skills/herdr-agent-layout";
in
{
  xdg.configFile = {
    "opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode/agents/herdr-worker.md" = mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode/commands/en.md" = mkLink ../../files/config/opencode/commands/en.md;
    "opencode/commands/obsidian.md" = mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode/commands/showme.md" = mkLink ../../files/config/opencode/commands/showme.md;
    "opencode/opencode.jsonc" = mkLink generated.defaultConfig;
    "opencode/cli.json" = mkLink generated.todoCli;
    "opencode/plugins/herdr-shell-env/index.js" = mkLink herdrShellEnvPlugin;
    "opencode/plugins/session-title/index.js" = mkLink sessionTitlePlugin;
    "opencode/plugins/obsidian-export/index.js" = mkLink obsidianExportPlugin;
    "opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;

    "opencode-profiles/chat/opencode/agents/chat.md" =
      mkLink ../../files/config/opencode/agents/chat.md;
    "opencode-profiles/chat/opencode/opencode.jsonc" = mkLink generated.chatConfig;
    "opencode-profiles/chat/opencode/cli.json" = mkLink generated.chatCli;
    "opencode-profiles/chat/opencode/plugins/profile-shell-env/index.js" = mkLink profileShellEnvPlugin;
    "opencode-profiles/chat/opencode/plugins/session-title/index.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/chat/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;

    # Herdr sessions use the normal server configuration plus a dedicated TUI
    # profile. The launcher injects the selected agent and model at runtime.
    "opencode-profiles/herdr/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/herdr/opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode-profiles/herdr/opencode/agents/herdr-worker.md" =
      mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode-profiles/herdr/opencode/commands/en.md" =
      mkLink ../../files/config/opencode/commands/en.md;
    "opencode-profiles/herdr/opencode/commands/obsidian.md" =
      mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode-profiles/herdr/opencode/commands/showme.md" =
      mkLink ../../files/config/opencode/commands/showme.md;
    "opencode-profiles/herdr/opencode/opencode.jsonc" = mkLink generated.defaultConfig;
    "opencode-profiles/herdr/opencode/cli.json" = mkLink generated.herdrCli;
    "opencode-profiles/herdr/opencode/herdr-opencode/tui.js" = mkLink (
      herdrPackage + "/share/herdr/opencode/tui.js"
    );
    "opencode-profiles/herdr/opencode/herdr-tui-session.js" = mkLink (
      herdrPackage + "/share/herdr/herdr-tui-session.js"
    );
    "opencode-profiles/herdr/opencode/plugins/herdr-agent-state/index.js" = mkLink (
      herdrPackage + "/share/herdr/opencode/herdr-agent-state.js"
    );
    "opencode-profiles/herdr/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/herdr/opencode/tui-plugins/todo" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/herdr/opencode/plugins/profile-shell-env/index.js" =
      mkLink profileShellEnvPlugin;
    "opencode-profiles/herdr/opencode/plugins/session-title/index.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/herdr/opencode/plugins/obsidian-export/index.js" = mkLink obsidianExportPlugin;

    # These are config-only profiles: sessions, auth, cache, and state remain
    # shared, while framework plugin registries stay isolated.
    "opencode-profiles/slim/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/slim/opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode-profiles/slim/opencode/agents/herdr-worker.md" =
      mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode-profiles/slim/opencode/commands/en.md" =
      mkLink ../../files/config/opencode/commands/en.md;
    "opencode-profiles/slim/opencode/commands/obsidian.md" =
      mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode-profiles/slim/opencode/commands/showme.md" =
      mkLink ../../files/config/opencode/commands/showme.md;
    "opencode-profiles/slim/opencode/opencode.jsonc" = mkLink generated.slimConfig;
    "opencode-profiles/slim/opencode/cli.json" = mkLink generated.todoCli;
    "opencode-profiles/slim/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/slim/opencode/tui-plugins/todo" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/slim/opencode/plugins/profile-shell-env/index.js" = mkLink profileShellEnvPlugin;
    "opencode-profiles/slim/opencode/plugins/herdr-shell-env/index.js" = mkLink herdrShellEnvPlugin;
    "opencode-profiles/slim/opencode/plugins/session-title/index.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/slim/opencode/plugins/obsidian-export/index.js" = mkLink obsidianExportPlugin;
    "opencode-profiles/slim/opencode/oh-my-opencode-slim.seed.jsonc" = mkLink slimOpenCodePluginConfig;
  };

  home.file = {
    ".agents/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
    ".agents/skills/obsidian-export" = mkLink obsidianExportSkill;
    ".agents/skills/showme" = mkLink showmeSkill;
    ".agents/skills/pr-review" = mkLink ../../files/agents/skills/pr-review;
    ".agents/skills/repo-qa" = mkLink ../../files/agents/skills/repo-qa;
    ".claude/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
  };

  # Install the shared Todo package once. Slim links to this package so it
  # never creates an incompatible duplicate OpenTUI dependency tree.
  home.activation.installOpenCodeTodoOverlayDeps = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    todo_overlay_source="${todoOverlayPackageRoot}"
    todo_overlay_package="${config.home.homeDirectory}/.config/opencode/tui-plugins/todo"
    todo_overlay_files=(
      package.json
      bun.lock
      tui.tsx
      lib/todo-overlay.ts
    )

    for todo_overlay_file in "''${todo_overlay_files[@]}"; do
      if [ ! -f "$todo_overlay_source/$todo_overlay_file" ]; then
        echo "OpenCode Todo overlay source file is missing: $todo_overlay_source/$todo_overlay_file" >&2
        exit 1
      fi
    done

    mkdir -p "$todo_overlay_package/lib"
    for todo_overlay_file in "''${todo_overlay_files[@]}"; do
      todo_overlay_destination="$todo_overlay_package/$todo_overlay_file"
      rm -f "$todo_overlay_destination"
      mkdir -p "$(dirname "$todo_overlay_destination")"
      cp "$todo_overlay_source/$todo_overlay_file" "$todo_overlay_destination"
    done

    (
      cd "$todo_overlay_package"
      ${pkgs.bun}/bin/bun install --frozen-lockfile --production
    )
  '';

  # Slim's /preset command owns the writable runtime file. Keep a managed seed
  # beside it, warn on drift, and require an explicit reset to overwrite it.
  home.activation.ensureOpenCodeSlimPluginConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    slim_seed="${config.home.homeDirectory}/.config/opencode-profiles/slim/opencode/oh-my-opencode-slim.seed.jsonc"
    slim_config="${config.home.homeDirectory}/.config/opencode-profiles/slim/opencode/oh-my-opencode-slim.jsonc"
    if [ -L "$slim_config" ]; then
      rm -f "$slim_config"
    fi
    if [ ! -e "$slim_config" ]; then
      cp "$slim_seed" "$slim_config"
      chmod 0644 "$slim_config"
    elif ! cmp -s "$slim_seed" "$slim_config"; then
      echo "warning: OpenCode Slim runtime config differs from its managed seed" >&2
      echo "warning: inspect with 'oc-slim-config status'; reset explicitly with 'oc-slim-config reset --force'" >&2
    fi
  '';
}
