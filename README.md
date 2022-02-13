# .files
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

Then run `make macos` to complete setup.

```
% make install.macos  # install dependencies
% make link.macos     # create symbolic links
```

### for Linux servers

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

### import GPG key pair to create signed commit

```
% gpg --import mi2428.public.key
% gpg --import mi2428.secret.key
% gpg --edit-key E8D3009C6341BDEAF038009685AB6867E2147DDA trust quit
% gpgconf --kill gpg-agent
```

### structure

As of Sun Feb 13 15:49:50 JST 2022

```
% tree -a -L 4 -I ".git"
.
├── .github
│   └── workflows
│       └── build.yml
├── .gitignore
├── Dockerfile
├── Makefile
├── README.md
├── bin
│   ├── inside
│   └── sjis-unzip
├── etc
│   ├── curl
│   │   └── curlrc
│   ├── git
│   │   └── gitconfig
│   ├── hosts
│   │   ├── linux-desktop
│   │   │   ├── compton
│   │   │   ├── conky
│   │   │   ├── dunst
│   │   │   ├── git
│   │   │   ├── gtk
│   │   │   ├── gtk-3.0
│   │   │   ├── i3
│   │   │   ├── latexmk
│   │   │   ├── mlterm
│   │   │   ├── psd
│   │   │   ├── rofi
│   │   │   ├── synergys
│   │   │   ├── systemd
│   │   │   ├── tmux
│   │   │   ├── x11
│   │   │   ├── xbindkeys
│   │   │   └── xinit
│   │   └── macos
│   │       ├── git
│   │       ├── karabiner
│   │       ├── latexmk
│   │       ├── nvim
│   │       ├── tmux
│   │       └── zsh
│   ├── nvim
│   │   ├── configs
│   │   │   ├── 10_general.vim
│   │   │   ├── 12_appearance.vim
│   │   │   ├── 20_defx.vim
│   │   │   ├── 21_ddc.vim
│   │   │   └── 22_fzf.vim
│   │   └── init.vim
│   ├── tmux
│   │   ├── tmux
│   │   │   └── scripts
│   │   └── tmux.conf
│   ├── wget
│   │   └── wgetrc
│   └── zsh
│       ├── zlogin
│       ├── zsh
│       │   ├── 10_general.zsh
│       │   ├── 20_aliases.zsh
│       │   ├── 30_appearance.zsh
│       │   └── 40_grc.zsh
│       └── zshrc
├── init
│   ├── LINK
│   ├── kick.sh
│   └── pkgs
│       ├── Brewfile
│       ├── apt.txt
│       ├── cargo.txt
│       ├── pacman.txt
│       └── python3-pip.txt
└── var
    ├── bettertouchtool
    │   └── ShizkBook.bttpreset
    ├── entrypoint.sh
    └── iterm2
        ├── ShizkBook.json
        ├── material-theme-darker.itermcolors
        ├── material-theme-ocean.itermcolors
        ├── material-theme-palenight.itermcolors
        └── material-theme.itermcolors

45 directories, 37 files
```
