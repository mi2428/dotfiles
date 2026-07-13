# home/files

Static files that should eventually be managed by `home.file` or
`xdg.configFile` live here.

- `config/` holds XDG-managed trees such as `nvim/`; `nvim/` is also linked by
  the emergency Make fallback
- `git/`, `tmux/`, and `zsh/` hold first-wave source files that are linked by
  Home Manager; `zsh/` is also linked by the emergency Make fallback
- `hosts/` holds host-specific overlays that still have not been absorbed into
  `profiles/` or `hosts/*.nix`, plus a few host-local static files that still
  need an eventual owner
