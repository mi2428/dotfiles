#!/bin/bash
export LC_ALL=en_US.UTF-8

HOST_USER=${HOST_USER:-shizk}
useradd -m -k /etc/skel -u $HOST_UID -g $HOST_GID -G wheel -s /bin/zsh ${HOST_USER}
cd /home/${HOST_USER}

exec sudo -E -u ${HOST_USER} $@
