if not command -sq grc
    return
end

if not status is-interactive
    return
end

if test -z "$TERM"; or test "$TERM" = dumb
    return
end

set -l grc_cmds \
    as \
    ant \
    blkid \
    cc \
    configure \
    curl \
    cvs \
    df \
    diff \
    dig \
    dnf \
    du \
    fdisk \
    findmnt \
    free \
    g++ \
    gas \
    gcc \
    getfacl \
    getsebool \
    gmake \
    id \
    ifconfig \
    iostat \
    ip \
    iptables \
    iwconfig \
    journalctl \
    kubectl \
    last \
    ldap \
    lolcat \
    ld \
    lsattr \
    lsblk \
    lsmod \
    lsof \
    lspci \
    make \
    mount \
    mtr \
    mvn \
    netstat \
    nmap \
    ntpdate \
    php \
    ping \
    ping6 \
    proftpd \
    ps \
    sar \
    semanage \
    sensors \
    showmount \
    sockstat \
    ss \
    stat \
    sysctl \
    systemctl \
    traceroute \
    traceroute6 \
    tune2fs \
    ulimit \
    uptime \
    vmstat \
    wdiff \
    whois

for cmd in $grc_cmds
    if not command -sq "$cmd"
        continue
    end

    # Keep explicit aliases/functions such as ls=eza intact.
    if functions -q "$cmd"
        continue
    end

    set -l escaped (string escape -- $cmd)
    eval "
        function $escaped --wraps '$escaped'
            grc --colour=auto $escaped \$argv
        end
    "
end
