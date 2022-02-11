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
install.arch:
	@xargs sudo pacman -S < $(pkgdir)/pacman.txt
	@xargs pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	@xargs cargo install < $(pkgdir)/cargo.txt

.PHONY: install.macos
install.macos:
	@chmod -R go-w /opt/homebrew/share
	@brew bundle --file=/dev/stdin < $(pkgdir)/Brewfile
	@sudo ln -sf /usr/local/bin/gtimeout /usr/local/bin/timeout
	@xargs pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	@xargs cargo install < $(pkgdir)/cargo.txt

.PHONY: install.ubuntu
install.ubuntu:
	@xargs sudo apt-get install -y --no-install-recommends < $(pkgdir)/apt.txt
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

