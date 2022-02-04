#!/bin/zsh
src=$(ip r get 1.1.1.1 | \grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sed -n "3,3p" 2> /dev/null)
if [[ -n $src ]]; then
  echo "$src"
else
  echo "offline"
fi
