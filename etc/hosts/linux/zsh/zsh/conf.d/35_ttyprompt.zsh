if [[ -z "$(echo $TTY | \grep pts)" ]]; then

RPROMPT='%~'
PROMPT='%# '

fi
