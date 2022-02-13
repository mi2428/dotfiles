if (( $+commands[arch] )); then
  alias x64='exec arch -arch x86_64 "$SHELL"'
  alias a64='exec arch -arch arm64e "$SHELL"'
fi


if whence -p trash 1> /dev/null; then
  alias rm='trash'
fi
