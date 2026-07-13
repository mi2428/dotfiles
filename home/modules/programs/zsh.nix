{ config, lib, ... }:
let
  inherit (config.dotfiles) platform;
  relativeFiles = [
    "05_catppuccin_theme.zsh"
    "10_general.zsh"
    "12_general_path.zsh"
    "14_general_fzf.zsh"
    "20_aliases.zsh"
    "22_aliases.zsh"
    "30_appearance.zsh"
    "40_grc.zsh"
  ];
  sourceFor = relativePath:
    if builtins.hasAttr relativePath platform.zsh.overrides then
      platform.zsh.overrides.${relativePath}
    else
      ../../../home/files/zsh/${relativePath};
  initFragments = map
    (relativePath: ''
      # ${relativePath}
      ${builtins.readFile (sourceFor relativePath)}
    '')
    relativeFiles;
in {
  programs.zsh = let
    initPrelude = ''
      # Fig pre block.
      [[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && . "$HOME/.fig/shell/zshrc.pre.zsh"

      if [[ -d "$HOME/.zsh" ]]; then
        while IFS= read -r conf; do
          [[ -f "$conf" ]] && source "$conf"
        done < <(find "$HOME/.zsh" -type l | sort)
      fi
    '';
    initEpilogue = ''
      if [[ "$TERM_PROGRAM" == "kiro" ]] && command -v kiro >/dev/null 2>&1; then
        kiro_shell_integration_path="$(kiro --locate-shell-integration-path zsh 2>/dev/null)"
        [[ -n "$kiro_shell_integration_path" && -f "$kiro_shell_integration_path" ]] && . "$kiro_shell_integration_path"
      fi

      [[ -f "$HOME/.openclaw/completions/openclaw.zsh" ]] && source "$HOME/.openclaw/completions/openclaw.zsh"

      # SDKMAN must be initialized after the rest of the shell setup.
      export SDKMAN_DIR="$HOME/.sdkman"
      [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

      # Fig post block.
      [[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && . "$HOME/.fig/shell/zshrc.post.zsh"
    '';
  in {
    enable = true;
    enableCompletion = true;
    completionInit = "";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    # The sourced assets still own most shell behavior; HM owns the assembly
    # order and surrounding integration.
    initContent = lib.mkMerge [
      (lib.mkBefore initPrelude)
      (lib.mkOrder 550 (lib.concatStringsSep "\n" initFragments))
      (lib.mkAfter initEpilogue)
    ];
  };
}
