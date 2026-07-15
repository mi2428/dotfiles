## re-redefine
#
cd() {
  local cd_status

  if (( $# == 0 )); then
    builtin cd -- /work
  else
    builtin cd "$@"
  fi
  cd_status=$?

  if (( cd_status != 0 )); then
    return $cd_status
  fi

  if whence -p exa 1> /dev/null; then
    EXA_ICON_SPACING=1 exa --icons .
  else
    ls --color=auto .
  fi
}
