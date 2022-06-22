#!/bin/bash
#See: https://gist.github.com/kawaz/d95fb3b547351e01f0f3f99783180b9f/raw/install-pam_tid-and-pam_reattach.sh
set -e
set -o pipefail

test -f /usr/lib/pam/pam_tid.so.2 || exit 1

if ! grep -Eq '^auth\s.*\spam_tid\.so$' /etc/pam.d/sudo; then
  ( set -e; set -o pipefail
    pam_sudo=$(awk 'fixed||!/^auth /{print} !fixed&&/^auth/{print "auth       sufficient     pam_tid.so";print;fixed=1}' /etc/pam.d/sudo)
    sudo tee /etc/pam.d/sudo <<<"$pam_sudo"
  )
fi

if ! grep -Eq '^auth\s.*\spam_reattach\.so$' /etc/pam.d/sudo; then
  ( set -e; set -o pipefail
    if [[ ! -x /usr/local/lib/pam/pam_reattach.so ]]; then
      type cmake 2>/dev/null || brew install cmake
      cd $(mktemp -d "${TMPDIR:-/tmp}/tmp.${1:-pam_reattach}.XXXXXXXXXX")
      git clone https://github.com/fabianishere/pam_reattach.git .
      cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local
      sudo make install
    fi
    pam_sudo=$(awk 'fixed||!/^auth .* pam_tid.so$/{print} !fixed&&/^auth/{print "auth       optional       pam_reattach.so";print;fixed=1}' /etc/pam.d/sudo)
    sudo tee /etc/pam.d/sudo <<<"$pam_sudo"
  )
fi
