local pluginbase="$HOME/.zsh/plugin"

local -a plugins
plugins+=("zaw/zaw.zsh")
plugins+=("zsh-autosuggestions/zsh-autosuggestions.zsh")
plugins+=("zsh-completions/zsh-completions.plugin.zsh")
plugins+=("zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")

# load plugins
for plugin in ${plugins[@]}; do
    [[ -f "$pluginbase/$plugin" ]] && source "$pluginbase/$plugin" || \
    echo "\e[31mFailed to load \"$plugin\""
done


# use ctrl+f to accept a suggested word
bindkey '^O' autosuggest-accept

# Color to use when highlighting suggestion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=004'

# Prefix to use when saving original versions of bound widgets
ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX=autosuggest-orig-

#ZSH_AUTOSUGGEST_STRATEGY=default
ZSH_AUTOSUGGEST_STRATEGY=match_prev_cmd

# Widgets that clear the suggestion
ZSH_AUTOSUGGEST_CLEAR_WIDGETS=(
    history-search-forward
    history-search-backward
    history-beginning-search-forward
    history-beginning-search-backward
    history-substring-search-up
    history-substring-search-down
    up-line-or-history
    down-line-or-history
    accept-line
)

# Widgets that accept the entire suggestion
ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(
    forward-char
    end-of-line
    vi-forward-char
    vi-end-of-line
    vi-add-eol
)

# Widgets that accept the entire suggestion and execute it
ZSH_AUTOSUGGEST_EXECUTE_WIDGETS=(
)

# Widgets that accept the suggestion as far as the cursor moves
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(
    forward-word
    vi-forward-word
    vi-forward-word-end
    vi-forward-blank-word
    vi-forward-blank-word-end
)

