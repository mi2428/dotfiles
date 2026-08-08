#!/usr/bin/env bash
set -euo pipefail

HOST_USER=${HOST_USER:-teo}
HOST_UID=${HOST_UID:-1000}
HOST_GID=${HOST_GID:-1000}
DEFAULT_SHELL=${DEFAULT_SHELL:-/etc/skel/.nix-profile/bin/fish}

if ! grep -Fq "127.0.1.1 ${HOSTNAME}" /etc/hosts; then
  echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
fi

G="wheel"
if [[ -n ${HOST_DOCKER_GID:-} ]]; then
  groupadd -g "${HOST_DOCKER_GID}" dood 2>/dev/null || true
  G="${G},dood"
fi

PRIMARY_GROUP="${HOST_USER}"
if getent group "${HOST_USER}" >/dev/null 2>&1; then
  PRIMARY_GROUP="${HOST_USER}"
elif getent group "${HOST_GID}" >/dev/null 2>&1; then
  PRIMARY_GROUP="$(getent group "${HOST_GID}" | cut -d: -f1)"
else
  groupadd -g "${HOST_GID}" "${HOST_USER}"
fi

RUNTIME_USER="${HOST_USER}"
if id -u "${HOST_USER}" >/dev/null 2>&1; then
  RUNTIME_USER="${HOST_USER}"
elif getent passwd "${HOST_UID}" >/dev/null 2>&1; then
  RUNTIME_USER="$(getent passwd "${HOST_UID}" | cut -d: -f1)"
else
  useradd -m -k /etc/skel -u "${HOST_UID}" -g "${PRIMARY_GROUP}" -G "${G}" -s /bin/bash "${HOST_USER}"
fi

cd /work || exit 1

if (($# == 0)); then
  set -- "${DEFAULT_SHELL}" --login
fi

exec sudo -H -u "${RUNTIME_USER}" env PATH="$PATH" MCP_WORKSPACE_ROOT=/work "$@"
