# home/files

This is the single source tree for Home Manager-managed files and adjacent
static dotfile sources.

- `config/` holds XDG configuration trees such as `nvim/` and `fish/`
- `git/`, `tmux/`, and `zsh/` hold non-XDG source files linked by Home Manager;
  `nvim/` and `zsh/` are also used by the emergency Make fallback
- `hosts/` holds host-specific overlays and host-local static files

Installation, activation, and verification scripts live under `bootstrap/`;
helper/setup scripts are under `bootstrap/setup/`. The former top-level
`etc/` and `init/` source trees are retired.
