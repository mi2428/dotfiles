# home/files

This is the single source tree for Home Manager-managed files and adjacent
static dotfile sources.

- `config/` holds XDG configuration trees such as `nvim/` and `fish/`
- `git/`, `tmux/`, and `zsh/` hold non-XDG source files linked by Home Manager;
  `tmux/` and `zsh/` are also used by the minimal Make fallback

Installation and activation scripts live under `bootstrap/`.
