if not status is-interactive
    return
end

# Keep fish's native completion pager, but give its candidate, description,
# alternating-row, and selected states the same hierarchy as the other
# Catppuccin-themed terminal pickers.
set -g fish_pager_color_completion $CTP_TEXT
set -g fish_pager_color_description $CTP_SUBTEXT1
set -g fish_pager_color_prefix $CTP_LAVENDER --bold
set -g fish_pager_color_progress $CTP_OVERLAY1

set -g fish_pager_color_secondary_background --background=$CTP_MANTLE
set -g fish_pager_color_secondary_completion $CTP_TEXT
set -g fish_pager_color_secondary_description $CTP_SUBTEXT1
set -g fish_pager_color_secondary_prefix $CTP_LAVENDER --bold

set -g fish_pager_color_selected_background --background=$CTP_SURFACE1
set -g fish_pager_color_selected_completion $CTP_TEXT --bold
set -g fish_pager_color_selected_description $CTP_TEXT
set -g fish_pager_color_selected_prefix $CTP_ROSEWATER --bold
