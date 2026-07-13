# dotfiles

My shell stack since 2016.

- The everyday stack is Ghostty, fish, herdr, tmux, and Neovim.
- Regular text uses `Ubuntu Mono`. Nerd Font glyphs come from Ghostty itself.
- The terminal theme is [Catppuccin](https://github.com/catppuccin/catppuccin), usually Mocha.
- This repo is Nix-based: `home/` and `flake.nix` define the steady state, while `chezmoi/` handles bootstrap and secrets.

>[!TIP]
> **TL;DR** This curl clones repo into `~/dotfiles` and runs [`bootstrap/bootstrap.sh`](/Users/teo/dotfiles/bootstrap/bootstrap.sh).
> ```console
> bash -c "$(curl -fsLS https://raw.githubusercontent.com/mi2428/dotfiles/refs/heads/master/scripts/setup.sh)"
> ```

> [!NOTE]
> Catppuccin can shift socially expected color names a bit, so something intended as cyan or light blue may look slightly greenish in CLI output.
> This mostly happens when an application uses ANSI color slots, because the terminal maps those slots through the active theme palette instead of using an explicit RGB value.
> When an application uses truecolor, it can request the intended RGB color directly, so the result is usually closer to what the app meant.

## Getting Started

Existing repo:

```console
cd ~/dotfiles
./bootstrap/bootstrap.sh --host MBP-M4Pro48G-C3VH95F6P6
```

```console
$ task

Tasks
  age.init           Generate the repo age identity and local chezmoi config
  age.unlock         Decrypt key.txt.age into ~/.config/chezmoi/key.txt
  secrets.encrypt    Encrypt ssh and/or gnupg into chezmoi source state
  secrets.decrypt    Decrypt ssh and/or gnupg into a target directory
  secrets.backup     Backup ssh and gnupg into encrypted chezmoi source state
  secrets.clear      Remove local staging and decrypted secret work directories
  docker.build       Build Dockerfile locally as ghcr.io/OWNER/IMAGE:TAG
  docker.login       Login to ghcr.io with GHCR_TOKEN, GITHUB_TOKEN, or gh auth token
  docker.push        Build and push Dockerfile to ghcr.io as ghcr.io/OWNER/IMAGE:TAG

Defaults
  GHCR_OWNER         mi2428
  GHCR_IMAGE_NAME    dotfiles
  TAG                latest
  DOCKER_RUNTIME     docker
  PLATFORMS          linux/amd64,linux/arm64
  IMPORT_GPG         0
  DECRYPT_HOME       $HOME/.cache/dotfiles/secrets/decrypted-home

Examples
  task age.init
  task secrets.encrypt
  task secrets.encrypt BUNDLE=ssh
  task secrets.encrypt BUNDLE=gnupg GPG_KEY_IDS='E8D3009C6341BDEAF038009685AB6867E2147DDA'
  task secrets.decrypt IMPORT_GPG=1 DECRYPT_HOME=$HOME
  task secrets.backup
  task docker.build TAG=latest
  task docker.push TAG=latest
```

## Hints

#### Secrets

Managed with `chezmoi/` + `age`:

- It manages `~/.ssh`.
- It manages `~/.gnupg`.

Backup:

```console
task secrets.backup
```

Decrypt into cache:

```console
task secrets.decrypt
```

Decrypt into the real home when needed:

```console
task secrets.decrypt IMPORT_GPG=1 DECRYPT_HOME=$HOME
```

#### Packages

Main package list: [`home/modules/core/packages.nix`](/Users/teo/dotfiles/home/modules/core/packages.nix)

- It is worth checking `gh`, `go-task`, `herdr`, `tmux`, and `neovim` there first.
- Ghostty is installed outside this repo.

#### Host Memo

- The current macOS bootstrap host name is `MBP-M4Pro48G-C3VH95F6P6`.
- Secret template data lives in `chezmoi/.chezmoidata/`.
- If colors look wrong, check ANSI versus truecolor first.

#### sudo authentication

Touch ID and Apple Watch sudo are managed by nix-darwin via `security.pam.services.sudo_local`. Keep local PAM edits out of `/etc/pam.d` unless they are intentionally outside the flake.

#### visudo

This is the memo I want to keep for local sudoers shape:

```console
# root and users in group wheel can run anything on any machine as any user
root    ALL = (ALL) ALL
%admin  ALL = (ALL) ALL
mi      ALL = NOPASSWD: /usr/local/sbin/mtr,/usr/local/bin/grc,/sbin/ping,/sbin/ping6,/usr/sbin/tcpdump,/usr/sbin/purge
```

#### pam-watchid

Apple Watch sudo used to be enabled with `pam-watchid`. If I ever need to re-check the old path, this was the installer:

```console
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mostpinkest/pam-watchid/HEAD/install.sh)" -- enable
```

And this was the corresponding `/etc/pam.d/sudo` snippet:

```console
auth       sufficient     pam_watchid.so "reason=execute a command as root"
auth       sufficient     pam_tid.so
```

#### 1Password

Remember to enable CLI integration in 1Password or it will keep asking for the vault password. The path was `Settings > Developer > Command-Line Interface (CLI) > Integrate with 1Password CLI`.

#### AWS Session Manager

If `aws ssm` is missing the Session Manager plugin on macOS, this was the install path:

```console
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
sudo installer -pkg session-manager-plugin.pkg -target /
sudo ln -s /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin
```

#### iTerm2 Preferences

Old iTerm2 preferences worth remembering:

- Under `General / Selection`, keep "Applications in terminal may access clipboard" enabled.
- Under `Appearance / General`, use the **Minimal** theme, put the tab bar at the top, and the status bar at the bottom.
- Under `Appearance / Tabs`, keep "Show tab bar even when there is only one tab" enabled.
- Under `Appearance / Dimming`, keep inactive split dimming disabled.
- Under `Advanced / Hotkey`, set the hotkey window animation duration to `0`.
- Under `Advanced / Session`, keep "Allow sessions to survive logging out and back in" set to `No`.
