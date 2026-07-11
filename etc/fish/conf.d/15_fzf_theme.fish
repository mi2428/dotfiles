if not status is-interactive
    return
end

if not command -sq fzf
    return
end

set -gx FZF_DEFAULT_OPTS "\
--height=60% \
--layout=reverse \
--border \
--style=full \
--info=inline-right \
--prompt=❯ \
--pointer=▶ \
--marker=✓ \
--separator=─ \
--scrollbar=│ \
--preview-window=right,55%,border-left \
--bind='ctrl-/:change-preview-window(right,55%,border-left|down,60%,border-top|hidden)' \
--color=bg:-1,fg:$CTP_TEXT,hl:$CTP_BLUE \
--color=bg+:$CTP_SURFACE0,fg+:$CTP_ROSEWATER,hl+:$CTP_LAVENDER \
--color=border:$CTP_OVERLAY1,label:$CTP_SUBTEXT1 \
--color=preview-border:$CTP_BLUE,preview-label:$CTP_LAVENDER \
--color=list-border:$CTP_GREEN,list-label:$CTP_GREEN \
--color=input-border:$CTP_YELLOW,input-label:$CTP_YELLOW \
--color=header-border:$CTP_TEAL,header-label:$CTP_SKY \
--color=info:$CTP_OVERLAY0,prompt:$CTP_MAUVE,pointer:$CTP_PEACH,marker:$CTP_GREEN,spinner:$CTP_SKY"
