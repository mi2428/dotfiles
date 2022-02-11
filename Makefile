.PHONY: install.mac
install.mac:
	brew install init/pkg/Brewfile
	pip3 install init/pkg/Pip3file
	chmod -R go-w /opt/homebrew/share
	sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout

.PHONY: install.basic
install.basic:
	brew install init/pkg/Brewfile
	pip3 install init/pkg/Pip3file
	chmod -R go-w /opt/homebrew/share
	sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout

.PHONY: link-basic
link-basic:
	LINK -t basic

.PHONY: link.macos
link.macos:
	LINK -t macos


.PHONY: update
update:
	brew update && brew upgrade -y || true
	pip3 update
	cargo update

