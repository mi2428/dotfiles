.DEFAULT_GOAL := help

REPO := $(CURDIR)
HOME_BIN := $(HOME)/.local/bin
HOME_ZSH := $(HOME)/.zsh
HOME_TMUX := $(HOME)/.tmux

.PHONY: help
help: ## Display available emergency targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9.-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Emergency setup

.PHONY: emergency
emergency: emergency-zsh emergency-tmux emergency-bin ## Link the minimal emergency environment

.PHONY: min
min: emergency ## Alias for emergency

.PHONY: link-minimal
link-minimal: emergency ## Alias for emergency

.PHONY: emergency-zsh
emergency-zsh: ## Link the repository zsh configuration
	@mkdir -p $(HOME_ZSH)
	@ln -sfn $(REPO)/etc/zsh/zshrc $(HOME)/.zshrc
	@ln -sfn $(REPO)/etc/zsh/zlogin $(HOME)/.zlogin
	@for config in $(REPO)/etc/zsh/zsh/*; do \
		[ -f "$$config" ] || continue; \
		ln -sfn "$$config" "$(HOME_ZSH)/$$(basename "$$config")"; \
	done

.PHONY: emergency-tmux
emergency-tmux: ## Link the repository tmux configuration
	@mkdir -p $(HOME_TMUX) $(HOME_TMUX)/scripts
	@ln -sfn $(REPO)/etc/tmux/tmux.conf $(HOME)/.tmux.conf
	@for config in $(REPO)/etc/tmux/tmux/*.conf; do \
		[ -f "$$config" ] || continue; \
		ln -sfn "$$config" "$(HOME_TMUX)/$$(basename "$$config")"; \
	done
	@for script in $(REPO)/etc/tmux/tmux/scripts/*; do \
		[ -f "$$script" ] || continue; \
		ln -sfn "$$script" "$(HOME_TMUX)/scripts/$$(basename "$$script")"; \
	done

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
