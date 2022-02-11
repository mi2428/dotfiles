#!/bin/bash

_vol="$(pacmd list-sinks | grep -E -o "front-left: [[:digit:]]*" | cut -d ' ' -f 2)"
muted="$(pacmd list-sinks | grep "muted: yes")"

vol=$(($_vol * 100 / 65535))

[[ -n "$muted" ]] && \
    echo -n "$vol% (muted)" || \
    echo -n "$vol%"
