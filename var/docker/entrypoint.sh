#!/bin/bash
HOST_USER=${HOST_USER:-shizk}

echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

G="wheel"
if [[ -n ${HOST_DOCKER_GID} ]]; then
  groupadd -g ${HOST_DOCKER_GID} dood 2>/dev/null || true
  G="${G},${HOST_DOCKER_GID}"
fi
groupadd -g $HOST_GID ${HOST_USER} 2>/dev/null || true
useradd -m -k /etc/skel -u ${HOST_UID} -g ${HOST_GID} -G ${G} -s /bin/zsh ${HOST_USER} 2>/dev/null || true

cd /work

exec sudo -u ${HOST_USER} $@
