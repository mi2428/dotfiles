#!/bin/bash
cd $HOME

DIST=""

if [[ -f /etc/lsb-release ]]; then
  DIST=$(grep DISTRIB_ID /etc/lsb-release | cut -d '=' -f 2)
fi

case $DIST in
  Ubuntu)
    apt install git make sudo ;;
  *)
    exit 127 ;;
esac

git clone --depth 1 https://github.com/mi2428/dotfiles $HOME/dotfiles
cd $HOME/dotfiles

case $DIST in
  Ubuntu)
    make ubuntu-server ;;
esac
