.DEFAULT_GOAL := help

REPO := $(CURDIR)
HOME_ZSH := $(HOME)/.zsh
HOME_NVIM := $(HOME)/.config/nvim

.PHONY: help
help: ## Display available emergency targets
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9.-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Emergency setup

.PHONY: emergency
emergency: emergency-zsh emergency-nvim ## Link the minimal Linux zsh + nvim emergency environment

.PHONY: min
min: emergency ## Alias for emergency

.PHONY: link-minimal
link-minimal: emergency ## Alias for emergency

.PHONY: emergency-zsh
emergency-zsh: ## Link the repository zsh configuration
	@mkdir -p $(HOME_ZSH)
	@ln -sfn $(REPO)/home/files/zsh/zshrc $(HOME)/.zshrc
	@ln -sfn $(REPO)/home/files/zsh/zlogin $(HOME)/.zlogin
	@for config in $(REPO)/home/files/zsh/zsh/*; do \
		[ -f "$$config" ] || continue; \
		ln -sfn "$$config" "$(HOME_ZSH)/$$(basename "$$config")"; \
	done

.PHONY: emergency-nvim
emergency-nvim: ## Link the repository Neovim configuration
	@mkdir -p $(HOME)/.config
	@ln -sfn $(REPO)/home/files/config/nvim $(HOME_NVIM)

##@ Bootstrap

.PHONY: bootstrap
bootstrap: ## Install/apply chezmoi and Home Manager for this host
	@./bootstrap/bootstrap.sh
