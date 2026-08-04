{ config, lib, pkgs, ... }:
let
  mkLink = source: {
    force = true;
    inherit source;
  };
  catppuccinYazi = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "yazi";
    rev = "baaf5d1c9427b836fbefd126aa855f9eab7a9d0d";
    hash = "sha256-L6SApM07CSQk0znEsFP8WaxW+ZHcindXo612r1XcwIg=";
  };
  catppuccinBat = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "bat";
    rev = "6810349b28055dce54076712fc05fc68da4b8ec0";
    hash = "sha256-lJapSgRVENTrbmpVyn+UQabC9fpV1G1e+CdlJ090uvg=";
  };
  yaziConfig = pkgs.runCommandLocal "dotfiles-yazi-config" { } ''
    mkdir -p "$out"
    ln -s "${../../files/config/yazi/theme.toml}" "$out/theme.toml"
    ln -s "${catppuccinBat}/themes/Catppuccin Mocha.tmTheme" "$out/Catppuccin-mocha.tmTheme"
    ln -s "${../../files/config/yazi/keymap.toml}" "$out/keymap.toml"
    ln -s "${../../files/config/yazi/init.lua}" "$out/init.lua"
    mkdir -p "$out/plugins"
    ln -s "${../../files/config/yazi/plugins/enter-cd-or-open.yazi}" "$out/plugins/enter-cd-or-open.yazi"
  '';
  binRoot = ../../../bin;
  binFiles = lib.mapAttrs'
    (name: _: lib.nameValuePair ".local/bin/${name}" (mkLink (binRoot + "/${name}")))
    (lib.filterAttrs (_: type: type == "regular") (builtins.readDir binRoot));
  codexNvimEditEvent = ../../files/libexec/dotfiles/codex-nvim-edit-event;
  ghReviewPreview = ../../files/libexec/dotfiles/gh-review-preview;
  herdrOpenCodeIntegration = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.config/opencode/plugins/herdr-agent-state.js";
  todoOverlayPackageRoot = ../../files/config/opencode/plugins/tui;
  todoOverlayOpenCodePackage = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.config/opencode/plugins/tui";
  slimOpenCodePluginConfig = ../../files/config/opencode/profiles/slim/oh-my-opencode-slim.jsonc;
  macCompatibilityFiles = lib.optionalAttrs pkgs.stdenv.isDarwin {
    "Library/Application Support/com.mitchellh.ghostty/themes" =
      mkLink ../../files/config/ghostty/themes;
    "Library/Application Support/lazygit/config.yml" =
      mkLink ../../files/config/lazygit/config.yml;
    "Library/Application Support/lazygit/functions.sh" =
      mkLink ../../files/config/lazygit/functions.sh;
    "Library/Application Support/lazygit/themes-mergable" =
      mkLink ../../files/config/lazygit/themes-mergable;
    "Library/Application Support/jesseduffield/lazydocker/config.yml" =
      mkLink ../../files/config/lazydocker/config.yml;
    "Library/Application Support/k9s/config.yaml" =
      mkLink ../../files/config/k9s/config.yaml;
    "Library/Application Support/k9s/skins" =
      mkLink ../../files/config/k9s/skins;
  };
in {
  xdg.configFile = {
    "atuin/config.toml" = mkLink ../../files/config/atuin/config.toml;
    "bat" = mkLink ../../files/config/bat;
    "btop" = mkLink ../../files/config/btop;
    "e1s/config.yml" = mkLink ../../files/config/e1s/config.yml;
    "eza" = mkLink ../../files/config/eza;
    "fzf" = mkLink ../../files/config/fzf;
    "ghostty/config" = mkLink ../../files/config/ghostty/config.ghostty;
    "ghostty/themes" = mkLink ../../files/config/ghostty/themes;
    "ghostty/shaders" = mkLink ../../files/config/ghostty/shaders;
    "glow" = mkLink ../../files/config/glow;
    "herdr/config.toml" = mkLink ../../files/config/herdr/config.toml;
    "herdr/lazygit-unified.yml" = mkLink ../../files/config/herdr/lazygit-unified.yml;
    "hunk" = mkLink ../../files/config/hunk;
    "k9s" = mkLink ../../files/config/k9s;
    "lazydocker/config.yml" = mkLink ../../files/config/lazydocker/config.yml;
    "lazygit" = mkLink ../../files/config/lazygit;
    "opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode/opencode.jsonc" = mkLink ../../files/config/opencode/opencode.jsonc;
    # Official Catppuccin OpenCode theme, vendored from catppuccin/opencode.
    "opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode/tui.json" = mkLink ../../files/config/opencode/tui.json;
    # The default OpenCode root stays framework-free. OmO and Slim use separate
    # XDG roots selected by wrappers, so their plugin registries never mix.
    "opencode-profiles/omo/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/omo/opencode/opencode.jsonc" =
      mkLink ../../files/config/opencode/profiles/omo/opencode.jsonc;
    "opencode-profiles/omo/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/omo/opencode/tui.json" =
      mkLink ../../files/config/opencode/profiles/omo/tui.json;
    "opencode-profiles/omo/opencode/plugins/tui" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/omo/opencode/plugins/herdr-agent-state.js" = {
      force = true;
      source = herdrOpenCodeIntegration;
    };
    "opencode-profiles/slim/opencode/AGENTS.md" = mkLink ../../files/config/opencode/AGENTS.md;
    "opencode-profiles/slim/opencode/opencode.jsonc" =
      mkLink ../../files/config/opencode/profiles/slim/opencode.jsonc;
    "opencode-profiles/slim/opencode/themes/catppuccin-mocha-mauve.json" =
      mkLink ../../files/config/opencode/themes/catppuccin-mocha-mauve.json;
    "opencode-profiles/slim/opencode/tui.json" =
      mkLink ../../files/config/opencode/profiles/slim/tui.json;
    "opencode-profiles/slim/opencode/plugins/tui" = {
      force = true;
      source = todoOverlayOpenCodePackage;
    };
    "opencode-profiles/slim/opencode/plugins/herdr-agent-state.js" = {
      force = true;
      source = herdrOpenCodeIntegration;
    };
    "starship" = mkLink ../../files/config/starship;
    "yazi" = mkLink yaziConfig;
  };

  home.file = binFiles // macCompatibilityFiles // {
    ".omo/omo.jsonc" = mkLink ../../files/omo/omo.jsonc;
    ".local/libexec/dotfiles/codex-nvim-edit-event" = mkLink codexNvimEditEvent;
    ".local/libexec/dotfiles/gh-review-preview" = mkLink ghReviewPreview;
    ".gitignore" = mkLink ../../files/git/gitignore;
    ".curlrc" = mkLink ../../files/curl/curlrc;
    ".lesskey" = mkLink ../../files/less/lesskey;
    ".screenrc" = mkLink ../../files/screen/screenrc;
    ".wgetrc" = mkLink ../../files/wget/wgetrc;
  };

  # Herdr's installers are idempotent and keep each harness hook at the
  # integration version shipped by the installed Herdr binary. Run this after
  # links exist so the generated OpenCode plugin can also feed isolated roots.
  home.activation.installHerdrAgentIntegrations = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    herdr_bin="$(command -v herdr || true)"
    if [ -z "$herdr_bin" ]; then
      for candidate in /opt/homebrew/bin/herdr /usr/local/bin/herdr /home/linuxbrew/.linuxbrew/bin/herdr; do
        if [ -x "$candidate" ]; then
          herdr_bin="$candidate"
          break
        fi
      done
    fi

    if [ -n "$herdr_bin" ]; then
      for target in claude codex opencode; do
        if command -v "$target" >/dev/null 2>&1 \
          || [ -x "/opt/homebrew/bin/$target" ] \
          || [ -x "/usr/local/bin/$target" ] \
          || [ -x "/home/linuxbrew/.linuxbrew/bin/$target" ]; then
          "$herdr_bin" integration install "$target" >/dev/null
        fi
      done
    fi
  '';

  # The default package owns the single dependency install. OmO and Slim link
  # their plugin package to this directory, so their isolated XDG roots do not
  # install incompatible duplicate OpenTUI trees.
  home.activation.installOpenCodeTodoOverlayDeps = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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

  # Herdr owns its SessionStart hook but preserves other entries in
  # ~/.codex/hooks.json. Merge the private Neovim edit bridge from its
  # immutable source; linkGeneration then projects the matching libexec path.
  home.activation.installCodexNvimEditHooks = lib.hm.dag.entryAfter [ "installHerdrAgentIntegrations" ] ''
    if [ -d "${config.home.homeDirectory}/.codex" ]; then
      ${pkgs.python3}/bin/python3 \
        "${codexNvimEditEvent}" \
        install --quiet
    fi
  '';

  # Unlike the immutable core/profile files, Slim's plugin config must remain
  # writable because its /preset manager persists changes there. Seed it once
  # and preserve later interactive edits across Home Manager activations.
  home.activation.ensureOpenCodeSlimPluginConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    slim_config="${config.home.homeDirectory}/.config/opencode-profiles/slim/opencode/oh-my-opencode-slim.jsonc"
    if [ -L "$slim_config" ]; then
      # Remove only a stale managed link from an earlier generation.
      rm -f "$slim_config"
    fi
    if [ ! -e "$slim_config" ]; then
      mkdir -p "$(dirname "$slim_config")"
      cp "${slimOpenCodePluginConfig}" "$slim_config"
      chmod 0644 "$slim_config"
    fi
  '';
}
