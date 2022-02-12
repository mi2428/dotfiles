# .files
[![GitHub last commit](https://img.shields.io/github/last-commit/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commit/HEAD) [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/mi2428/dotfiles)](https://github.com/mi2428/dotfiles/commits/master) [![GitHub CI/CD](https://github.com/mi2428/dotfiles/actions/workflows/build.yml/badge.svg)](https://github.com/mi2428/dotfiles/actions/workflows/build.yml)

### Fonts

* https://fonts.google.com/specimen/Ubuntu
* https://fonts.google.com/specimen/Ubuntu+Mono
* https://www.nerdfonts.com/

## Installation

### For Linux computers


`make ubuntu` do the following two commands:

```
% make install.ubuntu
% make link.linux-desktop
```

```
% make install.archlinux
% make link.linux-desktop
```

### For macOS computers

```
% sudo softwareupdate -i -a
% xcode-select --install
% bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```
% make install.macos  # install dependencies
% make link.macos     # create symbolic links
```

### For linux servers

```
% curl -fsSL https://raw.githubusercontent.com/mi2428/dotfiles/master/init/kick.sh | bash
```

```
% make install.ubuntu
% make link.linux
```

## Hints

### Import GPG key

```
% gpg --import mi2428.public.key
% gpg --import mi2428.secret.key
% gpg --edit-key E8D3009C6341BDEAF038009685AB6867E2147DDA trust quit
% gpgconf --kill gpg-agent
```
