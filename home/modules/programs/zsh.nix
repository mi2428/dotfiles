{ ... }:
{
  home.file.".zshenv" = {
    force = true;
    source = ../../../home/files/zsh/zshenv;
  };

  home.file.".zshrc" = {
    force = true;
    source = ../../../home/files/zsh/zshrc;
  };
}
