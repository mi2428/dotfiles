#!/bin/bash
if [[ -z $@ ]]; then
    OPTIONS="Power-off\nReboot\nSuspend\nHibernate"
    echo -e $OPTIONS
else
    case $option in
    Reboot)
        systemctl reboot ;;
    Power-off)
        systemctl poweroff ;;
    Suspend)
        systemctl suspend ;;
    Hibernate)
        systemctl hibernate ;;
    *)
        ;;
    esac
fi
