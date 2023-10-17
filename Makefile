LINKER := $(CURDIR)/init/LINK
PKGDIR := $(CURDIR)/init/pkgs
DOCKER_REPO := ghcr.io/mi2428/dotfiles
DOCKER_REV := latest
DOCKER_TAG := $(DOCKER_REPO):$(DOCKER_REV)

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

.PHONY: ubuntu-docker
ubuntu-docker: install.ubuntu link.docker

.PHONY: checkpoint
checkpoint: link.checkpoint

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
	@xargs sudo pacman -S < $(PKGDIR)/pacman.txt || true

.PHONY: pkginstall.ubuntu
pkginstall.ubuntu:
	@xargs sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends < $(PKGDIR)/apt.txt || true
	@sudo ./init/pkgs/neovim || true
	@sudo ln -sf /usr/bin/batcat /usr/bin/bat || true

.PHONY: pkginstall.macos
pkginstall.macos:
	@chmod -R go-w /usr/local/share    2>/dev/null || true  # Apple silicon
	@chmod -R go-w /opt/homebrew/share 2>/dev/null || true  # Intel chip
	@brew bundle --file=/dev/stdin < $(PKGDIR)/Brewfile || true
	@./init/setup-sudo-with-touchid.sh || true
	@sudo ln -sf /opt/homebrew/bin/gtimeout /usr/local/bin/timeout 2>/dev/null || true  # Apple silicon
	@sudo ln -sf /usr/local/bin/gtimeout    /usr/local/bin/timeout 2>/dev/null || true  # Intel chip
	@sudo ln -sf /opt/homebrew/bin/python3  /usr/local/bin/python  2>/dev/null || true  # Apple silicon
	@sudo ln -sf /usr/local/bin/python3     /usr/local/bin/python  2>/dev/null || true  # Intel chip

.PHONY: postinstall.common
postinstall.common:
	@sh -c 'curl -fLo $(HOME)/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' || true
	@curl -L https://raw.githubusercontent.com/pimterry/notes/latest-release/_notes > /usr/local/share/zsh/site-functions/_notes || true
	@python3 -m pip install --upgrade pip
	@xargs pip3 install --upgrade < $(PKGDIR)/python3-pip.txt || true
	@xargs cargo install < $(PKGDIR)/cargo.txt || true

.PHONY: postinstall.linux
postinstall.linux:
	@curl -fsSL https://deno.land/install.sh | sh || true
	@mkdir -p $(HOME)/.local/share/zsh || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting $(HOME)/.local/share/zsh/zsh-syntax-highlighting || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $(HOME)/.local/share/zsh/zsh-autosuggestions || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-completions $(HOME)/.local/share/zsh/zsh-completions || true
	@git clone --depth 1 https://github.com/junegunn/fzf.git $(HOME)/.fzf && $(HOME)/.fzf/install --all || true
	@sudo locale-gen en_US.UTF-8 ja_JP.UTF-8

.PHONY: link.linux
link.linux:
	@$(LINKER) --force

.PHONY: link.linux-desktop
link.linux-desktop:
	@$(LINKER) --patch linux-desktop --force

.PHONY: link.macos
link.macos:
	@$(LINKER) --patch macos --force

.PHONY: link.docker
link.docker:
	@$(LINKER) --patch docker --force

.PHONY: link.checkpoint
link.checkpoint:
	ln -snf $(CURDIR)/etc/hosts/checkpoint/tmux/tmux.conf $(HOME)/.tmux.conf
	ln -snf $(CURDIR)/etc/hosts/checkpoint/bin $(HOME)/bin

.PHONY: unlink
unlink:
	@$(LINKER) --unlink

.PHONY: docker
docker:
	@docker build -t $(DOCKER_TAG) .
