#!/bin/bash
HOST_USER=${HOST_USER:-shizk}
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}

echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

G="wheel"
if [[ -n ${HOST_DOCKER_GID} ]]; then
  groupadd -g "${HOST_DOCKER_GID}" dood 2>/dev/null || true
  G="${G},dood"
fi
groupadd -g "${HOST_GID}" "${HOST_USER}" 2>/dev/null || true
useradd -m -k /etc/skel -u "${HOST_UID}" -g "${HOST_GID}" -G "${G}" -s /bin/zsh "${HOST_USER}" 2>/dev/null || true

cd /work || exit 1

if (($# == 0)); then
  set -- /bin/zsh
fi

exec sudo -u "${HOST_USER}" -- "$@"
