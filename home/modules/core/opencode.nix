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
      }
    );
    # OmO 5.1.48 exposes only a V2 startup stub; keep this profile OmO-free
    # until its agents, tools, and hooks are supported.
    omoConfig = json.generate "opencode-omo.json" (mkOpenCodeConfig {
      model = "openai/gpt-6-sol";
    });
    slimConfig = json.generate "opencode-slim.json" (mkOpenCodeConfig {
      model = "amazon-bedrock/global.anthropic.claude-opus-5";
      models = slimOpenAIModels;
      plugins = [ slimPlugin ];
    });
    chatConfig = json.generate "opencode-chat.json" chatConfig;
    todoCli = json.generate "opencode-cli.json" todoCliConfig;
    chatCli = json.generate "opencode-chat-cli.json" chatCliConfig;
  };

  todoOverlayPackageRoot = ../../files/config/opencode/plugins/tui;
  todoOverlayOpenCodePackage = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/opencode/tui-plugins/todo";
  ponytailV2 = ../../files/config/opencode/plugins/ponytail-v2;
  firstThingsFirstPlugin = ../../files/config/opencode/plugins/first-things-first.js;
  herdrWorkerTitlePlugin = ../../files/config/opencode/plugins/herdr-worker-title.js;
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
    "opencode/plugins/first-things-first.js" = mkLink firstThingsFirstPlugin;
    "opencode/plugins/herdr-worker-title.js" = mkLink herdrWorkerTitlePlugin;
    "opencode/plugins/session-title.js" = mkLink sessionTitlePlugin;
    "opencode/plugins/obsidian-export.js" = mkLink obsidianExportPlugin;
    "opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;

    "opencode-profiles/chat/opencode/agents/chat.md" =
      mkLink ../../files/config/opencode/agents/chat.md;
    "opencode-profiles/chat/opencode/opencode.jsonc" = mkLink generated.chatConfig;
    "opencode-profiles/chat/opencode/cli.json" = mkLink generated.chatCli;
    "opencode-profiles/chat/opencode/plugins/chat-system.js" =
      mkLink ../../files/config/opencode/plugins/chat-system.js;
    "opencode-profiles/chat/opencode/plugins/profile-shell-env.js" = mkLink profileShellEnvPlugin;
    "opencode-profiles/chat/opencode/plugins/session-title.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/chat/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;

    # These are config-only profiles: sessions, auth, cache, and state remain
    # shared, while framework plugin registries stay isolated.
    "opencode-profiles/omo/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/omo/opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode-profiles/omo/opencode/agents/herdr-worker.md" =
      mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode-profiles/omo/opencode/commands/en.md" = mkLink ../../files/config/opencode/commands/en.md;
    "opencode-profiles/omo/opencode/commands/obsidian.md" =
      mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode-profiles/omo/opencode/commands/showme.md" =
      mkLink ../../files/config/opencode/commands/showme.md;
    "opencode-profiles/omo/opencode/opencode.jsonc" = mkLink generated.omoConfig;
    "opencode-profiles/omo/opencode/cli.json" = mkLink generated.todoCli;
    "opencode-profiles/omo/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/omo/opencode/plugins/first-things-first.js" = mkLink firstThingsFirstPlugin;
    "opencode-profiles/omo/opencode/tui-plugins/todo" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/omo/opencode/plugins/profile-shell-env.js" = mkLink profileShellEnvPlugin;
    "opencode-profiles/omo/opencode/plugins/herdr-worker-title.js" = mkLink herdrWorkerTitlePlugin;
    "opencode-profiles/omo/opencode/plugins/session-title.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/omo/opencode/plugins/obsidian-export.js" = mkLink obsidianExportPlugin;

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
    "opencode-profiles/slim/opencode/plugins/first-things-first.js" = mkLink firstThingsFirstPlugin;
    "opencode-profiles/slim/opencode/tui-plugins/todo" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/slim/opencode/plugins/profile-shell-env.js" = mkLink profileShellEnvPlugin;
    "opencode-profiles/slim/opencode/plugins/herdr-worker-title.js" = mkLink herdrWorkerTitlePlugin;
    "opencode-profiles/slim/opencode/plugins/session-title.js" = mkLink sessionTitlePlugin;
    "opencode-profiles/slim/opencode/plugins/obsidian-export.js" = mkLink obsidianExportPlugin;
    "opencode-profiles/slim/opencode/oh-my-opencode-slim.seed.jsonc" = mkLink slimOpenCodePluginConfig;
  };

  home.file = {
    ".omo/omo.jsonc" = mkLink ../../files/omo/omo.jsonc;
    ".agents/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
    ".agents/skills/obsidian-export" = mkLink obsidianExportSkill;
    ".agents/skills/showme" = mkLink showmeSkill;
    ".agents/skills/pr-review" = mkLink ../../files/agents/skills/pr-review;
    ".agents/skills/repo-qa" = mkLink ../../files/agents/skills/repo-qa;
    ".claude/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
  };

  # Herdr is installed outside Nix on macOS. Project its generated OpenCode
  # plugin into each profile after the installer has run.
  home.activation.linkOpenCodeProfileHerdrIntegration =
    lib.hm.dag.entryAfter [ "installHerdrAgentIntegrations" "linkGeneration" ]
      ''
        integration_source="${config.home.homeDirectory}/.config/opencode/plugins/herdr-agent-state.js"
        integration_targets=(
          "${config.home.homeDirectory}/.config/opencode-profiles/chat/opencode/plugins/herdr-agent-state.js"
          "${config.home.homeDirectory}/.config/opencode-profiles/omo/opencode/plugins/herdr-agent-state.js"
          "${config.home.homeDirectory}/.config/opencode-profiles/slim/opencode/plugins/herdr-agent-state.js"
        )
        for integration_target in "''${integration_targets[@]}"; do
          if [ -f "$integration_source" ]; then
            if [ -e "$integration_target" ] && [ ! -L "$integration_target" ]; then
              echo "Refusing to replace non-symlink OpenCode integration: $integration_target" >&2
              exit 1
            fi
            mkdir -p "$(dirname "$integration_target")"
            ln -sfn "$integration_source" "$integration_target"
          elif [ -L "$integration_target" ]; then
            rm -f "$integration_target"
          fi
        done
      '';

  # Install the shared Todo package once. OmO and Slim link to this package so
  # they never create incompatible duplicate OpenTUI dependency trees.
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
