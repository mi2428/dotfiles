{ lib, platformName, ... }:
let
  installTaskFromApt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "${platformName}" = "linux" ] && [ -r /etc/os-release ]; then
      . /etc/os-release

      if [ "''${ID:-}" = "ubuntu" ] \
        && ! command -v task >/dev/null 2>&1; then
        curl_bin="$(command -v curl || true)"
        sudo_bin="$(command -v sudo || true)"

        if [ -z "$curl_bin" ] && [ -x /usr/bin/curl ]; then
          curl_bin=/usr/bin/curl
        fi

        if [ -z "$sudo_bin" ] && [ -x /usr/bin/sudo ]; then
          sudo_bin=/usr/bin/sudo
        fi

        if [ -z "$curl_bin" ]; then
          echo "home-manager: curl is required to install task via apt" >&2
          exit 1
        fi

        if [ -z "$sudo_bin" ]; then
          echo "home-manager: sudo is required to install task via apt" >&2
          exit 1
        fi

        if [ ! -f /etc/apt/sources.list.d/task-task.list ] \
          && [ ! -f /etc/apt/sources.list.d/task_task.list ] \
          && [ ! -f /etc/apt/sources.list.d/task.list ]; then
          "$curl_bin" -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | "$sudo_bin" -E bash
        fi

        "$sudo_bin" env DEBIAN_FRONTEND=noninteractive apt-get update
        "$sudo_bin" env DEBIAN_FRONTEND=noninteractive apt-get install -y task
      fi
    fi
  '';
in {
  home.activation.installTaskFromSystemPackageManager = installTaskFromApt;
}
