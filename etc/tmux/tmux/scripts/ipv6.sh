#!/bin/zsh
#
src=$(ip -6 r get 2001:4860:4860::8888 2>/dev/null | awk '{for (I=1;I<NF;I++) if ($I == "src") print $(I+1)}')
if [[ -n $src ]]; then
  echo "$src"
else
  echo "no ipv6"
fi
