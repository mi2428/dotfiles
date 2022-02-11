linker := $(CURDIR)/init/LINK
unlinker := $(CURDIR)/init/UNLINK
pkgdir := $(CURDIR)/init/pkgs

.PHONY: default
default: ubuntu-server

.PHONY: archlinux
archlinux: install.arch link.linux-desktop

.PHONY: macos
macos: install.mac link.mac

.PHONY: ubuntu
ubuntu: install.ubuntu link.linux-desktop

.PHONY: ubuntu-server
ubuntu-server: install.ubuntu link.linux


.PHONY: install.arch
install.arch:
	sudo pacman -S - < $(pkgdir)/pacman.txt
	sudo -H pip3 install --upgrade -r $(pkgdir)/python3-pip.txt

.PHONY: install.mac
install.mac:
	curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash
	chmod -R go-w /opt/homebrew/share
	/opt/homebrew/brew bundle --file=/dev/stdin < $(pkgdir)/Brewfile
	sudo -H pip3 install --upgrade -r $(pkgdir)/python3-pip.txt
	sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout

.PHONY: install.ubuntu
install.ubuntu:
	sudo -H pip3 install --upgrade -r $(pkgdir)/python3-pip.txt


.PHONY: link.linux
link.linux:
	$(linker) -t basic

.PHONY: link.linux-desktop
link.linux-desktop:
	$(linker) -t linux-desktop

.PHONY: link.macos
link.macos:
	$(linker) -t macos


.PHONY: update
update:
	brew update && brew upgrade -y || true
	pip3 update
	cargo update

