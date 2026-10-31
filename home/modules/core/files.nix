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
  herdrPackage = config.dotfiles.herdr.package;
  removeHerdrFile = ''
    remove_herdr_file() {
      path=$1
      expected_target=''${2:-}
      expected_marker=''${3:-}
      if [ -L "$path" ]; then
        current_target=$(readlink "$path")
        if [ -n "$expected_target" ] && [ "$current_target" = "$expected_target" ]; then
          rm -f "$path"
        else
          echo "Refusing to remove unknown OpenCode symlink: $path -> $current_target" >&2
          exit 1
        fi
      elif [ -f "$path" ]; then
        first_line=
        if [ -n "$expected_marker" ] \
          && IFS= read -r first_line < "$path" \
          && [ "$first_line" = '// installed by herdr' ] \
          && ${pkgs.gnugrep}/bin/grep -Fxq "// HERDR_INTEGRATION_ID=$expected_marker" "$path"; then
          rm -f "$path"
        else
          echo "Refusing to remove unmanaged OpenCode file: $path" >&2
          exit 1
        fi
      elif [ -e "$path" ]; then
        echo "Refusing to remove unmanaged OpenCode path: $path" >&2
        exit 1
      fi
    }
  '';
  legacyCleanupCheck = pkgs.runCommand "check-legacy-opencode-herdr-cleanup" { } ''
    ${removeHerdrFile}

    printf '%s\n' \
      '// installed by herdr' \
      '// HERDR_INTEGRATION_ID=opencode' \
      > "$TMPDIR/managed"
    remove_herdr_file "$TMPDIR/managed" "" opencode
    [ ! -e "$TMPDIR/managed" ]

    printf '%s\n' \
      '// installed by herdr' \
      '// HERDR_INTEGRATION_ID=other' \
      > "$TMPDIR/wrong-id"
    ! (remove_herdr_file "$TMPDIR/wrong-id" "" opencode >/dev/null 2>&1)
    [ -f "$TMPDIR/wrong-id" ]

    printf '%s\n' \
      'console.log("// installed by herdr")' \
      '// installed by herdr' \
      '// HERDR_INTEGRATION_ID=opencode' \
      > "$TMPDIR/user-file"
    ! (remove_herdr_file "$TMPDIR/user-file" "" opencode >/dev/null 2>&1)
    [ -f "$TMPDIR/user-file" ]

    ln -s /known/herdr/source "$TMPDIR/known-link"
    remove_herdr_file "$TMPDIR/known-link" /known/herdr/source
    [ ! -L "$TMPDIR/known-link" ]

    ln -s /other/source "$TMPDIR/unknown-link"
    ! (remove_herdr_file "$TMPDIR/unknown-link" /known/herdr/source >/dev/null 2>&1)
    [ -L "$TMPDIR/unknown-link" ]

    touch "$out"
  '';
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
    ".local/scripts/dotfiles-dev.sh" = mkLink ../../../scripts/dotfiles-dev.sh;
    ".local/scripts/opencode-profile.sh" = mkLink ../../../scripts/opencode-profile.sh;
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

  # OpenCode uses immutable package assets. Only harnesses that still require
  # an installer are updated here, with the exact patched Herdr binary.
  home.activation.installHerdrAgentIntegrations = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    herdr_bin="${herdrPackage}/bin/herdr"
    if [ ! -x "$herdr_bin" ]; then
      echo "Patched Herdr binary is missing: $herdr_bin" >&2
      exit 1
    fi

    for target in claude codex; do
      if command -v "$target" >/dev/null 2>&1 \
        || [ -x "/opt/homebrew/bin/$target" ] \
        || [ -x "/usr/local/bin/$target" ] \
        || [ -x "/home/linuxbrew/.linuxbrew/bin/$target" ]; then
        "$herdr_bin" integration install "$target" >/dev/null
      fi
    done
  '';

  # Remove only files carrying Herdr's installer marker and links to those
  # known paths. OpenCode now loads the patched dedicated Nix profile.
  home.activation.removeLegacyOpenCodeHerdrIntegration =
    lib.hm.dag.entryAfter [ "installHerdrAgentIntegrations" ] ''
      test -e "${legacyCleanupCheck}"
      ${removeHerdrFile}

      opencode_root="${config.home.homeDirectory}/.config/opencode"
      remove_herdr_file "$opencode_root/plugins/herdr-agent-state.js" "" opencode
      remove_herdr_file "$opencode_root/herdr-tui-session.js" "" opencode-tui
      if [ -L "$opencode_root/herdr-opencode" ]; then
        echo "Refusing to traverse unknown OpenCode symlink: $opencode_root/herdr-opencode" >&2
        exit 1
      elif [ -d "$opencode_root/herdr-opencode" ]; then
        remove_herdr_file "$opencode_root/herdr-opencode/tui.js" "" opencode-tui-v2
        rmdir "$opencode_root/herdr-opencode" 2>/dev/null || true
      elif [ -e "$opencode_root/herdr-opencode" ]; then
        echo "Refusing to remove unmanaged OpenCode path: $opencode_root/herdr-opencode" >&2
        exit 1
      fi

      for profile in chat slim; do
        profile_root="${config.home.homeDirectory}/.config/opencode-profiles/$profile/opencode"
        remove_herdr_file "$profile_root/herdr-opencode" "$opencode_root/herdr-opencode"
        remove_herdr_file "$profile_root/herdr-tui-session.js" "$opencode_root/herdr-tui-session.js"
        remove_herdr_file \
          "$profile_root/plugins/herdr-agent-state/index.js" \
          "$opencode_root/plugins/herdr-agent-state.js"
        rmdir "$profile_root/plugins/herdr-agent-state" 2>/dev/null || true
      done
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
