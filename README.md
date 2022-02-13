# .files
[![GitHub last commit](https://img.shields.io/github/last-commit/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commit/HEAD) [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commits/master) [![GitHub CI/CD](https://github.com/mi2428/dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/mi2428/dotfiles/actions/workflows/build.yml)

### terminal color scheme

Based on [Google's Material Design Color Palette](https://material.io/design/style/color.html)

* https://www.martinseeler.com/iterm2-material-design

### terminal fonts

* **Ubuntu:** https://fonts.google.com/specimen/Ubuntu
* **Ubuntu Mono:** https://fonts.google.com/specimen/Ubuntu+Mono
* **Nerd Fonts:** https://www.nerdfonts.com/

## Docker

```
% docker run -it --rm \
  -w /work \
  -v $PWD:/work \
  -e HOST_UID=$(id -u $USER) \
  -e HOST_GID=$(id -g $USER) \
  ghcr.io/mi2428/dotfiles:latest
```

## Installation

### for Linux computers

`make ubuntu` do the following two commands:

```
% make install.ubuntu
% make link.linux-desktop
```

`make archlinux` do the following two commands:

```
% make install.archlinux
% make link.linux-desktop
```

### for macOS computers

First run the software update and install [HomeBrew](https://brew.sh/).

```
% sudo softwareupdate -i -a
% xcode-select --install
% bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

`make macos` do the following:

```
% make install.macos  # install dependencies
% make link.macos     # create symbolic links
```

### for Linux servers

```
% curl -fsSL https://raw.githubusercontent.com/mi2428/dotfiles/master/init/kick.sh | bash
```

```
% make install.ubuntu
% make link.linux
```

## Hints

### import GPG key pair to create signed commit

```
% gpg --import mi2428.public.key
% gpg --import mi2428.secret.key
% gpg --edit-key E8D3009C6341BDEAF038009685AB6867E2147DDA trust quit
% gpgconf --kill gpg-agent
```
