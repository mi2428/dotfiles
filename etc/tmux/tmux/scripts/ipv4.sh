#!/bin/zsh
src=$(ip r get 1.1.1.1 2>/dev/null | awk '{for (I=1;I<NF;I++) if ($I == "src") print $(I+1)}')
if [[ -n $src ]]; then
  echo "$src"
else
  echo "no ipv4"
fi
