## re-redefine
cd() {
  local d="${1:-/work}"
  if whence -p exa 1> /dev/null; then
    builtin cd $d && EXA_ICON_SPACING=1 exa --icons .
  else
    builtin cd $d && ls --color=auto .
  fi
}
