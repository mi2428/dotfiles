LINKER := $(CURDIR)/init/LINK
PKGDIR := $(CURDIR)/init/pkgs
DOCKER_REPO := mi2428/dotfiles
DOCKER_REV := latest
DOCKER_TAG := $(DOCKER_REV)/$(DOCKER_TAG)

.PHONY: default
default: ubuntu-server

.PHONY: archlinux
archlinux: install.arch link.linux-desktop

.PHONY: macos
macos: install.macos link.macos

.PHONY: ubuntu
ubuntu: install.ubuntu link.linux-desktop

.PHONY: ubuntu-server
ubuntu-server: install.ubuntu link.linux

.PHONY: install.archlinux
install.archlinux: preinstall.common pkginstall.archlinux postinstall.common postinstall.linux

.PHONY: install.ubuntu
install.ubuntu: preinstall.common pkginstall.ubuntu postinstall.common postinstall.linux

.PHONY: install.macos
install.macos: preinstall.common pkginstall.macos postinstall.common

.PHONY: preinstall.common
preinstall.common:
	@git pull || true

.PHONY: pkginstall.archlinux
pkginstall.archlinux:
	@xargs sudo pacman -S < $(PKGDIR)/pacman.txt

.PHONY: pkginstall.ubuntu
pkginstall.ubuntu:
	@xargs sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends < $(PKGDIR)/apt.txt
	@sudo ln -sf /usr/bin/batcat /usr/bin/bat || true

.PHONY: pkginstall.macos
pkginstall.macos:
	@chmod -R go-w /opt/homebrew/share
	@brew bundle --file=/dev/stdin < $(PKGDIR)/Brewfile
	@sudo ln -sf /usr/local/bin/gtimeout /usr/local/bin/timeout

.PHONY: postinstall.common
postinstall.common:
	@sh -c 'curl -fLo $(HOME)/.config/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
	@xargs pip3 install --upgrade < $(PKGDIR)/python3-pip.txt
	@xargs cargo install < $(PKGDIR)/cargo.txt

.PHONY: postinstall.linux
postinstall.linux:
	@curl -fsSL https://deno.land/install.sh | sh
	@mkdir -p $(HOME)/.local/share/zsh
	@git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting $(HOME)/.local/share/zsh/zsh-syntax-highlighting || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $(HOME)/.local/share/zsh/zsh-autosuggestions || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-completions $(HOME)/.local/share/zsh/zsh-completions || true

.PHONY: link.linux
link.linux:
	@$(LINKER) --force

.PHONY: link.linux-desktop
link.linux-desktop:
	@$(LINKER) --patch linux-desktop --force

.PHONY: link.macos
link.macos:
	@$(LINKER) --patch macos --force

.PHONY: unlink
unlink:
	@$(LINKER) --unlink

.PHONY: docker
docker:
	@docker build -t $(DOCKER_TAG) .
