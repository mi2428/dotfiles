linker := $(CURDIR)/init/LINK
unlinker := $(CURDIR)/init/UNLINK
pkgdir := $(CURDIR)/init/pkgs

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

.PHONY: install.arch
install.arch: preinstall.common pkginstall.arch postinstall.common

.PHONY: install.ubuntu
install.ubuntu: preinstall.common pkginstall.ubuntu postinstall.common

.PHONY: install.macos
install.macos: preinstall.common pkginstall.macos postinstall.common

.PHONY: preinstall.common
preinstall.common:
	@sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

.PHONY: pkginstall.arch
pkginstall.arch: install.common
	@xargs sudo pacman -S < $(pkgdir)/pacman.txt

.PHONY: pkginstall.ubuntu
pkginstall.ubuntu: install.common
	@xargs sudo apt-get install -y --no-install-recommends < $(pkgdir)/apt.txt

.PHONY: pkginstall.macos
pkginstall.macos: install.common
	@chmod -R go-w /opt/homebrew/share
	@brew bundle --file=/dev/stdin < $(pkgdir)/Brewfile
	@sudo ln -sf /usr/local/bin/gtimeout /usr/local/bin/timeout

.PHONY: postinstall.common
postinstall.common:
	@xargs pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	@xargs cargo install < $(pkgdir)/cargo.txt

.PHONY: link.linux
link.linux:
	@$(linker) -t basic

.PHONY: link.linux-desktop
link.linux-desktop:
	@$(linker) -t linux-desktop

.PHONY: link.macos
link.macos:
	@$(linker) -t macos

.PHONY: unlink
unlink:
	@$(unlinker)

