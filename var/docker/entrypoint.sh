#!/bin/bash
HOST_USER=${HOST_USER:-shizk}

echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
groupadd -g $HOST_GID ${HOST_USER} 2>/dev/null || true
useradd -m -k /etc/skel -u $HOST_UID -g $HOST_GID -G wheel,docker -s /bin/zsh ${HOST_USER} 2>/dev/null || true
cd /work

exec sudo -u ${HOST_USER} $@
