#!/bin/bash
HOST_USER=${HOST_USER:-shizk}

useradd -m -k /etc/skel -u $HOST_UID -g $HOST_GID -G wheel -s /bin/zsh ${HOST_USER}
cd /work

exec sudo -E -u ${HOST_USER} $@
