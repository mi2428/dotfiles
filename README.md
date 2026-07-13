# dotfiles
[![GitHub last commit](https://img.shields.io/github/last-commit/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commit/HEAD) [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commits/master) [![GitHub CI/CD](https://github.com/mi2428/dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/mi2428/dotfiles/actions/workflows/build.yml)

dotfiles since 2016

* zsh
* neovim
* tmux with tmuxinator

### Terminal color scheme

Based on [Google's Material Design Color Palette](https://material.io/design/style/color.html)

* https://www.martinseeler.com/iterm2-material-design

### Terminal fonts

Use the nerd font for non-ascii characters -- you can check icons from the [Cheat Sheet](https://www.nerdfonts.com/cheat-sheet).

* **Ubuntu:** https://fonts.google.com/specimen/Ubuntu
* **Ubuntu Mono:** https://fonts.google.com/specimen/Ubuntu+Mono
* **Source Code Pro:** https://fonts.google.com/specimen/Source+Code+Pro
* **Hack Nerd Fonts:** https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/Hack/Regular/HackNerdFont-Regular.ttf

## Use with docker

Type the following to open current directory with [mi2428/dotfiles](https://github.com/mi2428/dotfiles/pkgs/container/dotfiles):

```
% docker run -it --rm \
    -w /work \
    -v $PWD:/work \
    -e HOST_UID=$(id -u $USER) \
    -e HOST_GID=$(id -g $USER) \
    ghcr.io/mi2428/dotfiles:latest
```

To shorten the above docker command, you can copy [bin/inside](https://github.com/mi2428/dotfiles/blob/master/bin/inside) and put it to your `$PATH`.

```
% inside .
```

## Installation

Clone this repository just under your `$HOME`.

```
% git clone --depth 1 https://github.com/mi2428/dotfiles
```

The repository uses a `chezmoi` + `Nix` layout:

* `home/` is the source tree for Home Manager-managed files and adjacent static
  dotfile sources
* `bootstrap/` contains the scripts that install and apply the declarative setup
* `chezmoi/` contains secrets and the minimal pre-Nix bootstrap state

The former top-level `etc/` and `init/` trees have been retired. XDG config
sources are under `home/files/config/`, non-XDG dotfiles are under their
corresponding `home/files/` directory, and remaining static host assets are
under `home/files/hosts/`. Linux hosts share `home/hosts/linux.nix`; the
`linux-server` and `docker-dev` configuration names remain available.

### Minimal fallback

Use the Makefile fallback when chezmoi and Nix are unavailable.

```
% make install
```

This links:

* a minimal `~/.zshrc` plus `~/.zsh/*`
* `~/.tmux.conf` and `~/.tmux/*`

### Bootstrap

```
% ./bootstrap/bootstrap.sh
```

This is the standard path for installing and applying chezmoi and Nix.

It now does the following:

* applies the `chezmoi/` source state for secrets and bootstrap-managed files
* installs `nix` if needed
* builds and activates the selected flake host configuration

`bootstrap/bootstrap.sh` auto-detects `macos` and `linux-server`.
On macOS, automatic Nix installation is gated behind
`DOTFILES_BOOTSTRAP_DARWIN_DAEMON_INSTALL=1` because the daemon installer makes
system-wide changes.

### Current status

* Managed config and adjacent static sources live under `home/files/` and
  `home/`
* XDG configuration trees live under `home/files/config/`
* Remaining static host assets live under `home/files/hosts/`
* `chezmoi/` owns secrets and minimal pre-Nix bootstrapping

## Deploy hints

### Fix right prompt alignment

Remember to setup locale on your host - both `en_US` and `ja_JP` are requried

```
% sudo locale-gen en_US.UTF-8 ja_JP.UTF-8
```

### Import GPG key pair to create signed commit

**NOTE:** The simplest way is to copy-and-paste `.gnupg` directory from one to another -- no need type the followings.

```
% gpg --export --armor --output mi2428.public.key
% gpg --export-secret-keys --armor --output mi2428.secret.key
% shred --remove mi2428.secret.key
```

```
% chmod 700 ~/.gnupg
% echo "test" | gpg --clearsign 
```

Check `~/.gnupg/gpg-agent.conf` if you encountered "No pinentry" error.

```
% gpg --import mi2428.public.key
% gpg --import mi2428.secret.key
% gpg --pinentry-mode loopback --import mi2428.secret.key  # If "No pinentry" error occurred
% gpg --edit-key E8D3009C6341BDEAF038009685AB6867E2147DDA trust quit
% gpg --list-keys
% gpg --list-secret-keys
% gpgconf --kill gpg-agent
```

To skip password dialogue:

```
% echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
% gpgconf --kill gpg-agent
```

### sudo authentication
Touch ID / Apple Watch sudo is managed by nix-darwin via
`security.pam.services.sudo_local`. Keep local PAM tweaks out of `/etc/pam.d`
unless they are intentionally outside the flake.

### 1Password
Remember to activate the integration as below, or you will ask your vault password every time.
Also you need to install `op` command beforehand.

- Settings > Developer > Command-Line Interface (CLI) > Integrate with 1Password CLI

### AWS

#### Session Manager

Install the Session Manager plugin to use `aws ssm` command.

```
$ curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
$ sudo installer -pkg session-manager-plugin.pkg -target /
$ sudo ln -s /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin
```

### NeoVim

```
:PlugInstall
:UpdateRemotePlugins
```

### gnome-terminal preferences

To import profile:

```
dconf load /org/gnome/terminal/legacy/profiles:/ < material-shizk.dconf
```

To export profile:

```
dconf load /org/gnome/terminal/legacy/profiles:/ > material-shizk.dconf
```

### iTerm2 preferences

#### `General` / `Selection`
- Applications in terminal may access clipboard

#### `Appearance` / `General`
- Theme: **Minimal**
- Tab bar location: **Top**
- Status bar location: **Bottom**

#### `Appearance` / `Tabs`
- Show tab bar even when there is only one tab

#### `Appearance` / `Dimming`
- Uncheck: Dim inactive split panes

#### `Advanced` / `Hotkey`
- Duration in seconds of the hotkey window animation.: **0**

#### `Advanced` / `Session`
- Allow sessions to survice logging out and back in: **No**
