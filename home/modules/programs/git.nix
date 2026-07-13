{ hostName, ... }: {
  home.file.".gitconfig".source =
    if hostName == "macos" then
      ../../../home/files/git/gitconfig.macos
    else
      ../../../home/files/git/gitconfig;

  home.file.".catppuccin-delta.gitconfig".source =
    ../../../home/files/git/catppuccin-delta.gitconfig;
}
