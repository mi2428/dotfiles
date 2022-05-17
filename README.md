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

Use the nerd font for non-ascii characters, which will be installed by Brewfile

* **Ubuntu:** https://fonts.google.com/specimen/Ubuntu
* **Ubuntu Mono:** https://fonts.google.com/specimen/Ubuntu+Mono
* **Hack Nerd Fonts:** https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/Hack/Regular/complete

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

### Linux computers

**Ubuntu:** run `make ubuntu` containing the following two rules:

```
% make install.ubuntu
% make link.linux-desktop
```

**ArchLinux:** run `make archlinux` containing the following two rules:

```
% make install.archlinux
% make link.linux-desktop
```

### macOS computers

First run the software update and install [HomeBrew](https://brew.sh/) with:

```
% sudo softwareupdate -i -a
% xcode-select --install
% bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then run `make macos` including the following to complete setup.

```
% make install.macos  # install dependencies
% make link.macos     # create symbolic links
```

### Linux servers

Paste the below line and wait until the terminal goes silent.

```
% curl -fsSL https://raw.githubusercontent.com/mi2428/dotfiles/master/init/kick.sh | bash
```

**Ubuntu:** run `make ubuntu-server` containing the following two rules:

```
% make install.ubuntu
% make link.linux
```

## Deploy hints

### Fix right prompt alignment

Remember to setup locale on your host - both `en_US` and `ja_JP` are requried

```
% sudo locale-gen en_US.UTF-8 ja_JP.UTF-8
```

### Import GPG key pair to create signed commit

```
% chown 700 ~/.gnupg
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

### visudo

```
# root and users in group wheel can run anything on any machine as any user
root    ALL = (ALL) ALL
%admin  ALL = (ALL) ALL
mi      ALL = NOPASSWD: /usr/local/sbin/mtr,/usr/local/bin/grc,/sbin/ping,/sbin/ping6
```

### iTerm2 preferences

#### `Appearance` > `General`
- Theme: **Minimal**
- Tab bar location: **Top**
- Status bar location: **Bottom**

#### `Appearance` > `Tabs`
- Show tab bar even when there is only one tab

#### `Advanced` > `Hotkey`
- Duration in seconds of the hotkey window animation.: **0**

