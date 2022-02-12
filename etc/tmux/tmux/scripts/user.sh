#!/bin/zsh
w | awk '{for (I=NF-1;I>0;I--) if ($I == "users,") print $(I-1)}'
