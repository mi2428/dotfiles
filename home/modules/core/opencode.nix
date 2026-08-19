{ config, lib, pkgs, ... }:
let
  mkLink = source: {
    force = true;
    inherit source;
  };

  pluginVersions = builtins.fromJSON (
    builtins.readFile ../../files/config/opencode/plugin-versions.json
  );
  omoPlugin = "oh-my-openagent@${pluginVersions.omo}";
  slimPlugin = "oh-my-opencode-slim@${pluginVersions.slim}";

  openAIModels = {
    "gpt-5.6-sol".options.reasoningEffort = "xhigh";
    "gpt-5.3-codex-spark".options.reasoningEffort = "low";
  };
  slimOpenAIModels = openAIModels // {
    "gpt-5.6-terra".options.reasoningEffort = "xhigh";
    "gpt-5.6-luna".options.reasoningEffort = "low";
  };

  commonOpenCodeConfig = {
    "$schema" = "https://opencode.ai/config.json";
    autoupdate = false;
    share = "disabled";
    small_model = "openai/gpt-5.3-codex-spark";
    lsp = false;
    compaction = {
      auto = true;
      prune = true;
    };
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
    permission = {
      external_directory = {
        "*" = "ask";
        "~/obsidian/OpenCode/**" = "allow";
      };
      doom_loop = "ask";
      bash = {
        "*" = "allow";
        "sudo *" = "ask";
        "rm -rf *" = "ask";
        "git clean *" = "ask";
        "git reset --hard *" = "ask";
        "git checkout -- *" = "ask";
        "git restore *" = "ask";
        "git push *" = "ask";
      };
    };
  };

  mkOpenCodeConfig = { model, models ? openAIModels, plugin ? null }:
    commonOpenCodeConfig
    // {
      inherit model;
      provider.openai = { inherit models; };
    }
    // lib.optionalAttrs (plugin != null) {
      plugin = [ plugin ];
    };

  chatConfig = commonOpenCodeConfig // {
    model = "openai/gpt-5.6-sol";
    provider.openai.models = openAIModels;
    default_agent = "Chat";
    permission = commonOpenCodeConfig.permission // {
      external_directory."*" = "deny";
    };
    agent = {
      build.disable = true;
      plan.disable = true;
      general.disable = true;
      explore.disable = true;
    };
  };

  commonTuiConfig = {
    "$schema" = "https://opencode.ai/tui.json";
    theme = "catppuccin-mocha-mauve";
    diff_style = "auto";
    mouse = false;
    scroll_acceleration.enabled = true;
    attention = {
      enabled = true;
      notifications = true;
      sound = false;
    };
    keybinds.variant_cycle = "<leader>v";
  };
  mkTuiConfig = plugin:
    commonTuiConfig // {
      plugin = lib.optional (plugin != null) plugin ++ [ "./plugins/tui" ];
    };
  chatTuiConfig = commonTuiConfig // {
    keybinds = commonTuiConfig.keybinds // {
      agent_list = "none";
      agent_cycle = "none";
      agent_cycle_reverse = "none";
    };
  };

  json = pkgs.formats.json { };
  generated = {
    defaultConfig = json.generate "opencode-default.json" (mkOpenCodeConfig {
      model = "openai/gpt-5.6-sol";
      plugin = "${ponytail}/.opencode/plugins/ponytail.mjs";
    });
    omoConfig = json.generate "opencode-omo.json" (mkOpenCodeConfig {
      model = "openai/gpt-5.6-sol";
      plugin = omoPlugin;
    });
    slimConfig = json.generate "opencode-slim.json" (mkOpenCodeConfig {
      model = "amazon-bedrock/global.anthropic.claude-opus-5";
      models = slimOpenAIModels;
      plugin = slimPlugin;
    });
    chatConfig = json.generate "opencode-chat.json" chatConfig;
    defaultTui = json.generate "opencode-default-tui.json" (mkTuiConfig null);
    omoTui = json.generate "opencode-omo-tui.json" (mkTuiConfig omoPlugin);
    slimTui = json.generate "opencode-slim-tui.json" (mkTuiConfig slimPlugin);
    chatTui = json.generate "opencode-chat-tui.json" chatTuiConfig;
  };

  todoOverlayPackageRoot = ../../files/config/opencode/plugins/tui;
  todoOverlayOpenCodePackage = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.config/opencode/plugins/tui";
  herdrWorkerTitlePlugin = ../../files/config/opencode/plugins/herdr-worker-title.js;
  profileShellEnvPlugin = ../../files/config/opencode/plugins/profile-shell-env.js;
  obsidianExportPlugin = ../../files/config/opencode/plugins/obsidian-export.js;
  obsidianExportSkill = ../../files/agents/skills/obsidian-export;
  showmeSkill = ../../files/agents/skills/showme;
  slimOpenCodePluginConfig = ../../files/config/opencode/profiles/slim/oh-my-opencode-slim.jsonc;

  ponytail = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "16f29800fd2681bdf24f3eb4ccffe38be3baec6b";
    hash = "sha256-Y7d4s7uqjH6IbEXhqAiQ+yaxr6iiGcv2X64LuMtG1T8=";
  };

  herdrAgentLayout = pkgs.fetchFromGitHub {
    owner = "mi2428";
    repo = "herdr-agent-layout";
    rev = "8498296a84323f53b31229a3bdb3410ce1ba5cdf";
    hash = "sha256-hSCwYyWEYlurYNn4O0v7XUE5SpuMyEca62aTg5iRBXY=";
  };
  herdrAgentLayoutSkill = "${herdrAgentLayout}/skills/herdr-agent-layout";
in {
  xdg.configFile = {
    "opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode/agents/herdr-worker.md" =
      mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode/commands/en.md" = mkLink ../../files/config/opencode/commands/en.md;
    "opencode/commands/obsidian.md" = mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode/commands/showme.md" = mkLink ../../files/config/opencode/commands/showme.md;
    "opencode/opencode.jsonc" = mkLink generated.defaultConfig;
    "opencode/plugins/herdr-worker-title.js" = mkLink herdrWorkerTitlePlugin;
    "opencode/plugins/obsidian-export.js" = mkLink obsidianExportPlugin;
    "opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode/tui.json" = mkLink generated.defaultTui;

    "opencode-profiles/chat/opencode/agents/chat.md" =
      mkLink ../../files/config/opencode/agents/chat.md;
    "opencode-profiles/chat/opencode/opencode.jsonc" = mkLink generated.chatConfig;
    "opencode-profiles/chat/opencode/plugins/chat-system.js" =
      mkLink ../../files/config/opencode/plugins/chat-system.js;
    "opencode-profiles/chat/opencode/plugins/profile-shell-env.js" =
      mkLink profileShellEnvPlugin;
    "opencode-profiles/chat/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/chat/opencode/tui.json" = mkLink generated.chatTui;

    # These are config-only profiles: sessions, auth, cache, and state remain
    # shared, while framework plugin registries stay isolated.
    "opencode-profiles/omo/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/omo/opencode/agents/herdr-supervisor.md" =
      mkLink ../../files/config/opencode/agents/herdr-supervisor.md;
    "opencode-profiles/omo/opencode/agents/herdr-worker.md" =
      mkLink ../../files/config/opencode/agents/herdr-worker.md;
    "opencode-profiles/omo/opencode/commands/en.md" =
      mkLink ../../files/config/opencode/commands/en.md;
    "opencode-profiles/omo/opencode/commands/obsidian.md" =
      mkLink ../../files/config/opencode/commands/obsidian.md;
    "opencode-profiles/omo/opencode/commands/showme.md" =
      mkLink ../../files/config/opencode/commands/showme.md;
    "opencode-profiles/omo/opencode/opencode.jsonc" = mkLink generated.omoConfig;
    "opencode-profiles/omo/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/omo/opencode/tui.json" = mkLink generated.omoTui;
    "opencode-profiles/omo/opencode/plugins/tui" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/omo/opencode/plugins/profile-shell-env.js" =
      mkLink profileShellEnvPlugin;
    "opencode-profiles/omo/opencode/plugins/herdr-worker-title.js" =
      mkLink herdrWorkerTitlePlugin;
    "opencode-profiles/omo/opencode/plugins/obsidian-export.js" =
      mkLink obsidianExportPlugin;

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
    "opencode-profiles/slim/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/slim/opencode/tui.json" = mkLink generated.slimTui;
    "opencode-profiles/slim/opencode/plugins/tui" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/slim/opencode/plugins/profile-shell-env.js" =
      mkLink profileShellEnvPlugin;
    "opencode-profiles/slim/opencode/plugins/herdr-worker-title.js" =
      mkLink herdrWorkerTitlePlugin;
    "opencode-profiles/slim/opencode/plugins/obsidian-export.js" =
      mkLink obsidianExportPlugin;
    "opencode-profiles/slim/opencode/oh-my-opencode-slim.seed.jsonc" =
      mkLink slimOpenCodePluginConfig;
  };

  home.file = {
    ".omo/omo.jsonc" = mkLink ../../files/omo/omo.jsonc;
    ".agents/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
    ".agents/skills/obsidian-export" = mkLink obsidianExportSkill;
    ".agents/skills/showme" = mkLink showmeSkill;
    ".agents/skills/pr-review" =
      mkLink ../../files/agents/skills/pr-review;
    ".agents/skills/repo-qa" =
      mkLink ../../files/agents/skills/repo-qa;
    ".claude/skills/herdr-agent-layout" = mkLink herdrAgentLayoutSkill;
  };

  # Herdr is installed outside Nix on macOS. Project its generated OpenCode
  # integration only after the installer has run, and never leave a dangling
  # profile plugin on machines where Herdr is absent.
  home.activation.linkOpenCodeProfileHerdrIntegration =
    lib.hm.dag.entryAfter [ "installHerdrAgentIntegrations" "linkGeneration" ] ''
      integration_source="${config.home.homeDirectory}/.config/opencode/plugins/herdr-agent-state.js"
      for profile in chat omo slim; do
        integration_target="${config.home.homeDirectory}/.config/opencode-profiles/$profile/opencode/plugins/herdr-agent-state.js"
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
  home.activation.installOpenCodeTodoOverlayDeps =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      todo_overlay_source="${todoOverlayPackageRoot}"
      todo_overlay_package="${config.home.homeDirectory}/.config/opencode/plugins/tui"
      todo_overlay_files=(
        package.json
        bun.lock
        tui.ts
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
  home.activation.ensureOpenCodeSlimPluginConfig =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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
