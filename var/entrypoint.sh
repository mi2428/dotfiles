#!/bin/bash

uid=$(stat -c "%u" .)
gid=$(stat -c "%g" .)

usermod -u $uid $USER
groupmod -g $gid $USER
chown -R $uid:$gid $HOME

/usr/bin/toilet -f mono12 -F metal 2428
exec setpriv --reuid=$USER --regid=$USER --init-groups $@
