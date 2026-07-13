# home/files

Static files that should eventually be managed by `home.file` or
`xdg.configFile` live here.

- `config/` holds XDG-managed trees such as `nvim/`
- `git/`, `tmux/`, and `zsh/` hold first-wave source files that are linked by
  Home Manager and the emergency Make targets
- `hosts/` holds host-specific overlays that still have not been absorbed into
  `profiles/` or `hosts/*.nix`
