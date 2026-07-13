REPO := $(CURDIR)
HOME_ZSH := $(HOME)/.zsh
HOME_TMUX := $(HOME)/.tmux

.PHONY: install
install: ## Link the minimal shell and tmux configuration
	@mkdir -p $(HOME)
	@ln -sfn $(REPO)/home/files/zsh $(HOME_ZSH)
	@printf '%s\n' \
		'if [ -d "$$HOME/.zsh" ]; then' \
		'  for conf in "$$HOME"/.zsh/*.zsh; do' \
		'    [ -f "$$conf" ] || continue' \
		'    . "$$conf"' \
		'  done' \
		'fi' > $(HOME)/.zshrc
	@ln -sfn $(REPO)/home/files/tmux/tmux.conf $(HOME)/.tmux.conf
	@ln -sfn $(REPO)/home/files/tmux $(HOME_TMUX)
