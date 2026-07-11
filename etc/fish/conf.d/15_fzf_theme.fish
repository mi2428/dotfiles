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
--color=bg:#1A1F24,fg:#E3E7EA,hl:#64B5F6 \
--color=bg+:#242B31,fg+:#FFFFFF,hl+:#82B1FF \
--color=border:#78909C,label:#C7D1D6 \
--color=preview-border:#64B5F6,preview-label:#82B1FF \
--color=list-border:#81C784,list-label:#69F0AE \
--color=input-border:#FFD740,input-label:#FFD740 \
--color=header-border:#4DD0E1,header-label:#84FFFF \
--color=info:#FFF176,prompt:#FFD740,pointer:#FFD740,marker:#69F0AE,spinner:#4DD0E1"
