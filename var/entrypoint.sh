#!/bin/bash
HOST_USER=${HOST_USER:-shizk}

echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
useradd -m -k /etc/skel -u $HOST_UID -g $HOST_GID -G wheel -s /bin/zsh ${HOST_USER}
cd /work

exec sudo -u ${HOST_USER} $@
