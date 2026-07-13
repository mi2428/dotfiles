{ hostName, lib, ... }:
let
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
    if relativePath == "12_general_path.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/12_general_path.macos.zsh
    else if relativePath == "14_general_fzf.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/14_general_fzf.macos.zsh
    else if relativePath == "22_aliases.zsh" && hostName == "macos" then
      ../../../home/files/zsh/zsh/22_aliases.macos.zsh
    else if relativePath == "22_aliases.zsh" && hostName == "docker-dev" then
      ../../../home/files/zsh/zsh/22_aliases.docker-dev.zsh
    else
      ../../../home/files/zsh/zsh/${relativePath};
  zshFiles = lib.listToAttrs (map
    (relativePath:
      lib.nameValuePair ".zsh/${relativePath}" {
        source = sourceFor relativePath;
      })
    relativeFiles);
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = lib.mkMerge [
      (lib.mkBefore ''
        [[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && . "$HOME/.fig/shell/zshrc.pre.zsh"
      '')
      ''
        for conf in "$HOME"/.zsh/*.zsh(N); do
          source "$conf"
        done

        if [ -f "$HOME/.zshrc_functions/assume-role" ]; then
          export SORACOM_AWS_LOGIN_ITEM_ID=jggxzohgplnedvzyftmxinlgdu
          source "$HOME/.zshrc_functions/assume-role"
        fi

        export SDKMAN_DIR="$HOME/.sdkman"
        [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

        if [[ "$TERM_PROGRAM" == "kiro" ]] && command -v kiro >/dev/null 2>&1; then
          kiro_shell_integration_path="$(kiro --locate-shell-integration-path zsh 2>/dev/null)"
          [[ -n "$kiro_shell_integration_path" && -f "$kiro_shell_integration_path" ]] && . "$kiro_shell_integration_path"
        fi

        [[ -f "$HOME/.openclaw/completions/openclaw.zsh" ]] && source "$HOME/.openclaw/completions/openclaw.zsh"
      ''
      (lib.mkAfter ''
        [[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && . "$HOME/.fig/shell/zshrc.post.zsh"
      '')
    ];
  };

  home.file = zshFiles;
}
