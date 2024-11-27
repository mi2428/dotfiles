LINKER := $(CURDIR)/init/LINK
PKGDIR := $(CURDIR)/init/pkgs
DOCKER_REPO := ghcr.io/mi2428/dotfiles
DOCKER_REV := latest
DOCKER_TAG := $(DOCKER_REPO):$(DOCKER_REV)


.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9.-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Deployment

.PHONY: default
default: ubuntu-server  ## Setup as a Ubuntu Server

.PHONY: archlinux
archlinux: install.arch link.linux-desktop  ## Setup Arch Linux

.PHONY: macos
macos: install.macos link.macos  ## Setup macOS

.PHONY: ubuntu
ubuntu: install.ubuntu link.linux-desktop  ## Setup Ubuntu Desktop

.PHONY: ubuntu-server
ubuntu-server: install.ubuntu link.linux  ## Setup Ubuntu Server

.PHONY: ubuntu-docker
ubuntu-docker: install.ubuntu link.docker  ## Setup dockerized Ubuntu Server

.PHONY: checkpoint
checkpoint: link.checkpoint  ## Setup Checkpoint

##@ Development

.PHONY: install.archlinux
install.archlinux: preinstall.common pkginstall.archlinux postinstall.common postinstall.linux ##

.PHONY: install.ubuntu
install.ubuntu: preinstall.common pkginstall.ubuntu postinstall.common postinstall.linux ##

.PHONY: install.macos
install.macos: preinstall.common pkginstall.macos postinstall.common ##

.PHONY: preinstall.common
preinstall.common: ##
	@git pull || true

.PHONY: pkginstall.archlinux
pkginstall.archlinux: ## 
	@xargs sudo pacman -S < $(PKGDIR)/pacman.txt || true

.PHONY: pkginstall.ubuntu
pkginstall.ubuntu: ##
	@xargs sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends < $(PKGDIR)/apt.txt || true
	@sudo ./init/pkgs/neovim || true
	@sudo ln -sf /usr/bin/batcat /usr/bin/bat || true

.PHONY: pkginstall.macos
pkginstall.macos: ##
	@chmod -R go-w /usr/local/share    2>/dev/null || true  # Apple silicon
	@chmod -R go-w /opt/homebrew/share 2>/dev/null || true  # Intel chip
	@brew bundle --file=/dev/stdin < $(PKGDIR)/Brewfile || true
	@./init/setup-sudo-with-touchid.sh || true
	@sudo ln -sf /opt/homebrew/bin/gtimeout /usr/local/bin/timeout 2>/dev/null || true  # Apple silicon
	@sudo ln -sf /usr/local/bin/gtimeout    /usr/local/bin/timeout 2>/dev/null || true  # Intel chip
	@sudo ln -sf /opt/homebrew/bin/python3  /usr/local/bin/python  2>/dev/null || true  # Apple silicon
	@sudo ln -sf /usr/local/bin/python3     /usr/local/bin/python  2>/dev/null || true  # Intel chip

.PHONY: postinstall.common
postinstall.common: ##
	@sh -c 'curl -fLo $(HOME)/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' || true
	@curl -L https://raw.githubusercontent.com/pimterry/notes/latest-release/_notes > /usr/local/share/zsh/site-functions/_notes || true
	#@python3 -m pip install --upgrade pip
	#@xargs pip3 install --upgrade < $(PKGDIR)/python3-pip.txt || true
	@xargs cargo install --force < $(PKGDIR)/cargo.txt || true

.PHONY: postinstall.linux
postinstall.linux: ##
	@curl -fsSL https://deno.land/install.sh | sh || true
	@mkdir -p $(HOME)/.local/share/zsh || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting $(HOME)/.local/share/zsh/zsh-syntax-highlighting || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $(HOME)/.local/share/zsh/zsh-autosuggestions || true
	@git clone --depth 1 https://github.com/zsh-users/zsh-completions $(HOME)/.local/share/zsh/zsh-completions || true
	@git clone --depth 1 https://github.com/junegunn/fzf.git $(HOME)/.fzf && $(HOME)/.fzf/install --all || true
	@sudo locale-gen en_US.UTF-8 ja_JP.UTF-8

.PHONY: link.linux
link.linux: ##
	#@$(LINKER) --force
	@$(LINKER) --patch linux-server --force

.PHONY: link.linux-desktop
link.linux-desktop: ##
	@$(LINKER) --patch linux-desktop --force

.PHONY: link.macos
link.macos: ##
	@$(LINKER) --patch macos --force

.PHONY: link.docker
link.docker: ##
	@$(LINKER) --patch docker --force

.PHONY: link.checkpoint
link.checkpoint: ##
	@ln -snf $(CURDIR)/etc/hosts/checkpoint/tmux/tmux.conf $(HOME)/.tmux.conf
	@ln -snf $(CURDIR)/etc/hosts/checkpoint/bin $(HOME)/bin

.PHONY: unlink
unlink: ## Uninstall dotfiles environment
	@$(LINKER) --unlink

.PHONY: docker
docker: ##
	@docker build -t $(DOCKER_TAG) .
