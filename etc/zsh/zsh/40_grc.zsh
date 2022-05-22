if ! whence -p grc 1> /dev/null; then
    return
fi

if ! tty -s || [ ! -n "$TERM" ] || [ "$TERM" = dumb ] || (( ! $+commands[grc] )); then
  return
fi

cmds=(
  as
  ant
  blkid
  cc
  configure
  curl
  cvs
  df
  diff
  dig
  dnf
  docker
  docker-compose
  docker-machine
  du
  #env
  fdisk
  findmnt
  free
  g++
  gas
  gcc
  getfacl
  getsebool
  gmake
  id
  ifconfig
  iostat
  ip
  iptables
  iwconfig
  journalctl
  kubectl
  last
  ldap
  lolcat
  ld
  ls
  lsattr
  lsblk
  lsmod
  lsof
  lspci
  make
  mount
  mtr
  mvn
  netstat
  nmap
  ntpdate
  php
  ping
  ping6
  proftpd
  ps
  sar
  semanage
  sensors
  showmount
  sockstat
  ss
  stat
  sysctl
  systemctl
  #tcpdump
  traceroute
  traceroute6
  tune2fs
  ulimit
  uptime
  vmstat
  wdiff
  whois
)

for cmd in $cmds ; do
  if (( $+commands[$cmd] )) ; then
    case $cmd in
      mtr|ping|ping6)
        $cmd() {
          sudo grc --colour=auto ${commands[$0]} "$@"
        }
        ;;
      *)
        $cmd() {
          grc --colour=auto ${commands[$0]} "$@"
        }
      ;;
    esac
  fi
done

unset cmds cmd
