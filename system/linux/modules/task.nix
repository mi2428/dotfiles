{ lib, platformName, ... }:
let
  installTaskFromApt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "${platformName}" = "linux" ] && [ -r /etc/os-release ]; then
      . /etc/os-release

      if [ "${ID:-}" = "ubuntu" ] \
        && ! dpkg-query -W task >/dev/null 2>&1; then
        if ! command -v curl >/dev/null 2>&1; then
          echo "home-manager: curl is required to install task via apt" >&2
          exit 1
        fi

        if ! command -v sudo >/dev/null 2>&1; then
          echo "home-manager: sudo is required to install task via apt" >&2
          exit 1
        fi

        if [ ! -f /etc/apt/sources.list.d/task-task.list ] \
          && [ ! -f /etc/apt/sources.list.d/task_task.list ] \
          && [ ! -f /etc/apt/sources.list.d/task.list ]; then
          curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | sudo -E bash
        fi

        sudo apt-get update
        sudo apt-get install -y task
      fi
    fi
  '';
in {
  home.activation.installTaskFromSystemPackageManager = installTaskFromApt;
}
