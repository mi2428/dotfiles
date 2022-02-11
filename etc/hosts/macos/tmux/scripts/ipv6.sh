#!/bin/zsh
src=$(ip -6 r get 2001:4860:4860::8888 2> /dev/null | awk '{print $NF}')
if [[ -n $src ]]; then
  echo "$src"
else
  echo "no ipv6"
fi
