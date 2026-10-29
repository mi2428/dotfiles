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
  hermesConfig = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/dotfiles/home/files/hermes/config.yaml";
  macCompatibilityFiles = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
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
    "gh-dash/config.yml" = mkLink ../../files/config/gh-dash/config.yml;
    "herdr/config.toml" = mkLink ../../files/config/herdr/config.toml;
    "herdr/lazygit-unified.yml" = mkLink ../../files/config/herdr/lazygit-unified.yml;
    "hunk" = mkLink ../../files/config/hunk;
    "k9s" = mkLink ../../files/config/k9s;
    "lazydocker/config.yml" = mkLink ../../files/config/lazydocker/config.yml;
    "lazygit" = mkLink ../../files/config/lazygit;
    "starship" = mkLink ../../files/config/starship;
    "tuicr/config.toml" = mkLink ../../files/config/tuicr/config.toml;
    "yazi" = mkLink yaziConfig;
  };

  home.file = binFiles // macCompatibilityFiles // {
    ".codex/dot-q.config.toml" = mkLink ../../files/codex-dot-q.config.toml;
    ".codex/en.config.toml" = mkLink ../../files/codex-en.config.toml;
    ".local/libexec/dotfiles/codex-nvim-edit-event" = mkLink codexNvimEditEvent;
    ".local/libexec/dotfiles/gh-review-preview" = mkLink ghReviewPreview;
    ".gitignore" = mkLink ../../files/git/gitignore;
    ".curlrc" = mkLink ../../files/curl/curlrc;
    ".lesskey" = mkLink ../../files/less/lesskey;
    ".screenrc" = mkLink ../../files/screen/screenrc;
    ".wgetrc" = mkLink ../../files/wget/wgetrc;
    ".hermes/config.yaml" = mkLink hermesConfig;
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
        target_available=false
        if command -v "$target" >/dev/null 2>&1 \
          || [ -x "/opt/homebrew/bin/$target" ] \
          || [ -x "/usr/local/bin/$target" ] \
          || [ -x "/home/linuxbrew/.linuxbrew/bin/$target" ]; then
          target_available=true
        fi
        if [ "$target" = opencode ]; then
          if command -v opencode-v2 >/dev/null 2>&1 \
            && opencode-v2 --version >/dev/null 2>&1; then
            target_available=true
          else
            target_available=false
          fi
        fi

        if [ "$target_available" = true ]; then
          if [ "$target" = opencode ]; then
            cli_config="${config.home.homeDirectory}/.config/opencode/cli.json"
            if [ -L "$cli_config" ]; then
              writable_copy="$(mktemp "$cli_config.XXXXXX")"
              cp "$cli_config" "$writable_copy"
              chmod 0644 "$writable_copy"
              mv -f "$writable_copy" "$cli_config"
            fi
          fi
          "$herdr_bin" integration install "$target" >/dev/null
        fi
      done
    fi
  '';

  # Profile roots have their own cli.json, so mirror Herdr's V2 TUI plugin and
  # registration alongside the server integration links created by OpenCode.
  home.activation.linkHerdrProfileTuiPlugins =
    lib.hm.dag.entryAfter [ "installHerdrAgentIntegrations" "linkGeneration" ] ''
      herdr_config="${config.home.homeDirectory}/.config/opencode"
      herdr_tui_source="$herdr_config/herdr-opencode"
      herdr_tui_shared="$herdr_config/herdr-tui-session.js"
      herdr_tui_plugin="./herdr-opencode"

      if [ -f "$herdr_tui_source/tui.js" ] && [ -f "$herdr_tui_shared" ]; then
        link_herdr_tui_target() {
          source=$1
          target=$2
          if [ -L "$target" ]; then
            current_target=$(readlink "$target")
            [ "$current_target" = "$source" ] && return 0
            rm -f "$target"
          elif [ -e "$target" ]; then
            echo "Refusing to replace non-symlink Herdr TUI entry: $target" >&2
            exit 1
          fi
          mkdir -p "$(dirname "$target")"
          ln -s "$source" "$target"
        }

        register_herdr_tui_plugin() {
          cli_config=$1
          [ -f "$cli_config" ] || {
            echo "OpenCode profile cli.json is missing: $cli_config" >&2
            exit 1
          }
          cli_source=$cli_config
          if [ -L "$cli_config" ]; then
            cli_source=$(mktemp "$cli_config.XXXXXX")
            cp "$cli_config" "$cli_source"
            chmod 0644 "$cli_source"
          fi
          cli_temporary=$(mktemp "$cli_config.XXXXXX")
          if ${pkgs.jq}/bin/jq --arg plugin "$herdr_tui_plugin" '
            if .plugins == null then .plugins = []
            elif (.plugins | type) != "array" then error("plugins must be an array")
            else . end
            | if (.plugins | index($plugin)) == null then .plugins += [$plugin] else . end
          ' "$cli_source" > "$cli_temporary"; then
            chmod 0644 "$cli_temporary"
            mv -f "$cli_temporary" "$cli_config"
          else
            rm -f "$cli_temporary"
            [ "$cli_source" = "$cli_config" ] || rm -f "$cli_source"
            echo "Failed to register Herdr in OpenCode profile cli.json: $cli_config" >&2
            exit 1
          fi
          [ "$cli_source" = "$cli_config" ] || rm -f "$cli_source"
        }

        for profile in chat slim; do
          profile_root="${config.home.homeDirectory}/.config/opencode-profiles/$profile/opencode"
          link_herdr_tui_target "$herdr_tui_source" "$profile_root/herdr-opencode"
          link_herdr_tui_target "$herdr_tui_shared" "$profile_root/herdr-tui-session.js"
          register_herdr_tui_plugin "$profile_root/cli.json"
        done
      fi
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

}
