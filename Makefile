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
	@xargs sudo -H pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	@xargs sudo -H cargo install < $(pkgdir)/cargo.txt

.PHONY: install.macos
install.macos:
	chmod -R go-w /opt/homebrew/share
	brew bundle --file=/dev/stdin < $(pkgdir)/Brewfile
	sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout
	xargs sudo -H pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	xargs sudo -H cargo install < $(pkgdir)/cargo.txt

.PHONY: install.ubuntu
install.ubuntu:
	@xargs sudo apt-get install -y --no-install-recommends < $(pkgdir)/apt.txt
	@xargs sudo -H pip3 install --upgrade < $(pkgdir)/python3-pip.txt
	@xargs sudo -H cargo install < $(pkgdir)/cargo.txt


.PHONY: link.linux
link.linux:
	@$(linker) -t basic

.PHONY: link.linux-desktop
link.linux-desktop:
	@$(linker) -t linux-desktop

.PHONY: link.macos
link.macos:
	@$(linker) -t macos


.PHONY: update
update:
	@which brew 1> /dev/null 2>&1 && brew update && brew upgrade -y || true
	@xargs sudo -H pip3 install --upgrade < $(pkgdir)/python3-pip.txt


.PHONY: unlink
unlink:
	@$(unlinker)

