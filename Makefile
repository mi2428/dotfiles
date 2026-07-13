.DEFAULT_GOAL := help

REPO := $(CURDIR)
HOME_BIN := $(HOME)/.local/bin

.PHONY: help
help: ## Display available emergency targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9.-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Emergency setup

.PHONY: emergency
emergency: emergency-zsh emergency-tmux emergency-bin ## Link the minimal emergency environment

.PHONY: emergency-zsh
emergency-zsh: ## Link the repository zsh configuration
	@ln -sfn $(REPO)/etc/zsh/zshrc $(HOME)/.zshrc

.PHONY: emergency-tmux
emergency-tmux: ## Link the repository tmux configuration
	@ln -sfn $(REPO)/etc/tmux/tmux.conf $(HOME)/.tmux.conf

.PHONY: emergency-bin
emergency-bin: ## Link repository commands into ~/.local/bin
	@mkdir -p $(HOME_BIN)
	@for command in $(REPO)/bin/*; do \
		[ -f "$$command" ] || continue; \
		ln -sfn "$$command" "$(HOME_BIN)/$$(basename "$$command")"; \
	done

##@ Bootstrap

.PHONY: bootstrap
bootstrap: ## Check bootstrap prerequisites, then link the emergency environment
	@./bootstrap/bootstrap.sh
