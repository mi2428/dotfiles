{ platformFiles, ... }: {
  home.file.".gitconfig".source = platformFiles.git;

  home.file.".catppuccin-delta.gitconfig".source =
    ../../../home/files/git/catppuccin-delta.gitconfig;
}
