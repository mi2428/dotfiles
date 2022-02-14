# dotfiles
[![GitHub last commit](https://img.shields.io/github/last-commit/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commit/HEAD) [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commits/master) [![GitHub CI/CD](https://github.com/mi2428/dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/mi2428/dotfiles/actions/workflows/build.yml)

dotfiles since 2016

* zsh
* neovim
* tmux with tmuxinator

### terminal color scheme

Based on [Google's Material Design Color Palette](https://material.io/design/style/color.html)

* https://www.martinseeler.com/iterm2-material-design

### terminal fonts

Use the nerd font for non-ascii characters

* **Ubuntu:** https://fonts.google.com/specimen/Ubuntu
* **Ubuntu Mono:** https://fonts.google.com/specimen/Ubuntu+Mono
* **Nerd Fonts:** https://www.nerdfonts.com/

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

### fix right prompt alignment

Remember to setup locale on your host - both `en_US` and `ja_JP` are requried

```
% sudo locale-gen en_US.UTF-8 ja_JP.UTF-8
```

### import GPG key pair to create signed commit

```
% gpg --import mi2428.public.key
% gpg --import mi2428.secret.key
% gpg --edit-key E8D3009C6341BDEAF038009685AB6867E2147DDA trust quit
% gpgconf --kill gpg-agent
```
