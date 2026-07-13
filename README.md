# dotfiles

Since 2016.

Current base stack:

- Ghostty + herdr
- tmux + Neovim
- zsh

Font policy:

- regular text: `Ubuntu Mono`
- Nerd Font glyphs: rely on Ghostty built-ins
- not using `Hack Nerd Font`
- not using `Source Code Pro`

Layout:

- Nix is the base layer
- `home/` and `flake.nix` define the steady state
- `chezmoi/` handles bootstrap and secrets
- in short: Nix-based, bootstrap with chezmoi

## Bootstrap

For a fresh machine:

```console
bash -c "$(curl -fsLS https://raw.githubusercontent.com/mi2428/dotfiles/refs/heads/master/scripts/setup.sh)"
```

[`scripts/setup.sh`](/Users/teo/dotfiles/scripts/setup.sh) clones this repo into `~/dotfiles` and then runs [`bootstrap/bootstrap.sh`](/Users/teo/dotfiles/bootstrap/bootstrap.sh).

`bootstrap/bootstrap.sh` does three things:

- applies `chezmoi/`
- installs Nix if needed
- activates the host configuration

If the repo is already present:

```console
cd ~/dotfiles
./bootstrap/bootstrap.sh --host MBP-M4Pro48G-C3VH95F6P6
```


> [!NOTE]
> **Color Note:** With Catppuccin, CLI colors can drift away from the socially expected color name.
> The reason is the difference between ANSI color slots and truecolor.
> ANSI uses palette slots like `31` or `36`, so the terminal theme decides the final rendered color.
> Truecolor uses explicit RGB values like `#89dceb`, so the app can request the intended color directly.
> In practice, an ANSI-based app may render something that feels closer to green even when the intent was "cyan" or "light blue."

## Hints

### Task

```console
task
```

Common commands:

- `task age.init`
- `task age.unlock`
- `task secrets.backup`
- `task docker.build TAG=latest`
- `task docker.push TAG=latest`

### Secrets

Managed with `chezmoi/` + `age`:

- `~/.ssh`
- `~/.gnupg`

Normal backup flow:

```console
task secrets.backup
```

Decrypt into cache:

```console
task secrets.decrypt
```

Decrypt into the real home only when needed:

```console
task secrets.decrypt IMPORT_GPG=1 DECRYPT_HOME=$HOME
```

### Ghostty

Ghostty is the outer terminal. Config lives in [`home/files/config/ghostty/config.ghostty`](/Users/teo/dotfiles/home/files/config/ghostty/config.ghostty).

Assumptions:

- `Ubuntu Mono`
- Catppuccin theme
- quick terminal enabled
- Ghostty covers Nerd Font glyphs

### herdr

The terminal multiplexer I want to use first. Config: [`home/files/config/herdr/config.toml`](/Users/teo/dotfiles/home/files/config/herdr/config.toml).

### tmux

Still part of the base workflow. Muscle memory remains. Config:

- [`home/modules/programs/tmux.nix`](/Users/teo/dotfiles/home/modules/programs/tmux.nix)
- [`home/files/tmux/tmux.conf`](/Users/teo/dotfiles/home/files/tmux/tmux.conf)

### Neovim

Neovim is managed through Home Manager. Config:

- [`home/modules/programs/nvim.nix`](/Users/teo/dotfiles/home/modules/programs/nvim.nix)
- [`home/files/config/nvim/init.lua`](/Users/teo/dotfiles/home/files/config/nvim/init.lua)

### Packages

CLI packages mainly live in [`home/modules/core/packages.nix`](/Users/teo/dotfiles/home/modules/core/packages.nix).

Things I care about here:

- `gh`
- `go-task`
- `herdr`
- `tmux`
- `neovim`
- `ghostty` is installed outside this repo

### Host Memo

- current macOS bootstrap host name: `MBP-M4Pro48G-C3VH95F6P6`
- secret template data lives in `chezmoi/.chezmoidata/`
- if colors look wrong, first check whether the app is using ANSI or truecolor
