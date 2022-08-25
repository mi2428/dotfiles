#!/bin/zsh
src=$(ip r get 1.1.1.1 | \grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -n 1 2> /dev/null)
if [[ -n $src ]]; then
  echo "$src"
else
  echo "no ipv4"
fi
