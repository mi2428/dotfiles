# Catppuccin flavour selection. Uncomment exactly one line.
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR latte
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR frappe
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR macchiato
set -gx DOTFILES_CATPPUCCIN_FLAVOUR mocha

switch $DOTFILES_CATPPUCCIN_FLAVOUR
    case latte
        set -gx DOTFILES_CATPPUCCIN_BAT_THEME "Catppuccin Latte"
        set -gx CTP_ROSEWATER "#dc8a78"
        set -gx CTP_FLAMINGO "#dd7878"
        set -gx CTP_PINK "#ea76cb"
        set -gx CTP_MAUVE "#8839ef"
        set -gx CTP_MAUVE_RGB "136;57;239"
        set -gx CTP_RED "#d20f39"
        set -gx CTP_RED_RGB "210;15;57"
        set -gx CTP_MAROON "#e64553"
        set -gx CTP_PEACH "#fe640b"
        set -gx CTP_PEACH_RGB "254;100;11"
        set -gx CTP_YELLOW "#df8e1d"
        set -gx CTP_YELLOW_RGB "223;142;29"
        set -gx CTP_GREEN "#40a02b"
        set -gx CTP_GREEN_RGB "64;160;43"
        set -gx CTP_TEAL "#179299"
        set -gx CTP_TEAL_RGB "23;146;153"
        set -gx CTP_SKY "#04a5e5"
        set -gx CTP_SAPPHIRE "#209fb5"
        set -gx CTP_SAPPHIRE_RGB "32;159;181"
        set -gx CTP_BLUE "#1e66f5"
        set -gx CTP_BLUE_RGB "30;102;245"
        set -gx CTP_LAVENDER "#7287fd"
        set -gx CTP_TEXT "#4c4f69"
        set -gx CTP_TEXT_RGB "76;79;105"
        set -gx CTP_SUBTEXT1 "#5c5f77"
        set -gx CTP_SUBTEXT0 "#6c6f85"
        set -gx CTP_OVERLAY2 "#7c7f93"
        set -gx CTP_OVERLAY1 "#8c8fa1"
        set -gx CTP_OVERLAY0 "#9ca0b0"
        set -gx CTP_SURFACE2 "#acb0be"
        set -gx CTP_SURFACE1 "#bcc0cc"
        set -gx CTP_SURFACE0 "#ccd0da"
        set -gx CTP_SURFACE0_RGB "204;208;218"
        set -gx CTP_BASE "#eff1f5"
        set -gx CTP_MANTLE "#e6e9ef"
        set -gx CTP_CRUST "#dce0e8"
        set -gx LSCOLORS "exfxcxdxbxegedabagacad"
    case frappe
        set -gx DOTFILES_CATPPUCCIN_BAT_THEME "Catppuccin Frappe"
        set -gx CTP_ROSEWATER "#f2d5cf"
        set -gx CTP_FLAMINGO "#eebebe"
        set -gx CTP_PINK "#f4b8e4"
        set -gx CTP_MAUVE "#ca9ee6"
        set -gx CTP_MAUVE_RGB "202;158;230"
        set -gx CTP_RED "#e78284"
        set -gx CTP_RED_RGB "231;130;132"
        set -gx CTP_MAROON "#ea999c"
        set -gx CTP_PEACH "#ef9f76"
        set -gx CTP_PEACH_RGB "239;159;118"
        set -gx CTP_YELLOW "#e5c890"
        set -gx CTP_YELLOW_RGB "229;200;144"
        set -gx CTP_GREEN "#a6d189"
        set -gx CTP_GREEN_RGB "166;209;137"
        set -gx CTP_TEAL "#81c8be"
        set -gx CTP_TEAL_RGB "129;200;190"
        set -gx CTP_SKY "#99d1db"
        set -gx CTP_SAPPHIRE "#85c1dc"
        set -gx CTP_SAPPHIRE_RGB "133;193;220"
        set -gx CTP_BLUE "#8caaee"
        set -gx CTP_BLUE_RGB "140;170;238"
        set -gx CTP_LAVENDER "#babbf1"
        set -gx CTP_TEXT "#c6d0f5"
        set -gx CTP_TEXT_RGB "198;208;245"
        set -gx CTP_SUBTEXT1 "#b5bfe2"
        set -gx CTP_SUBTEXT0 "#a5adce"
        set -gx CTP_OVERLAY2 "#949cbb"
        set -gx CTP_OVERLAY1 "#838ba7"
        set -gx CTP_OVERLAY0 "#737994"
        set -gx CTP_SURFACE2 "#626880"
        set -gx CTP_SURFACE1 "#51576d"
        set -gx CTP_SURFACE0 "#414559"
        set -gx CTP_SURFACE0_RGB "65;69;89"
        set -gx CTP_BASE "#303446"
        set -gx CTP_MANTLE "#292c3c"
        set -gx CTP_CRUST "#232634"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
    case mocha
        set -gx DOTFILES_CATPPUCCIN_BAT_THEME "Catppuccin Mocha"
        set -gx CTP_ROSEWATER "#f5e0dc"
        set -gx CTP_FLAMINGO "#f2cdcd"
        set -gx CTP_PINK "#f5c2e7"
        set -gx CTP_MAUVE "#cba6f7"
        set -gx CTP_MAUVE_RGB "203;166;247"
        set -gx CTP_RED "#f38ba8"
        set -gx CTP_RED_RGB "243;139;168"
        set -gx CTP_MAROON "#eba0ac"
        set -gx CTP_PEACH "#fab387"
        set -gx CTP_PEACH_RGB "250;179;135"
        set -gx CTP_YELLOW "#f9e2af"
        set -gx CTP_YELLOW_RGB "249;226;175"
        set -gx CTP_GREEN "#a6e3a1"
        set -gx CTP_GREEN_RGB "166;227;161"
        set -gx CTP_TEAL "#94e2d5"
        set -gx CTP_TEAL_RGB "148;226;213"
        set -gx CTP_SKY "#89dceb"
        set -gx CTP_SAPPHIRE "#74c7ec"
        set -gx CTP_SAPPHIRE_RGB "116;199;236"
        set -gx CTP_BLUE "#89b4fa"
        set -gx CTP_BLUE_RGB "137;180;250"
        set -gx CTP_LAVENDER "#b4befe"
        set -gx CTP_TEXT "#cdd6f4"
        set -gx CTP_TEXT_RGB "205;214;244"
        set -gx CTP_SUBTEXT1 "#bac2de"
        set -gx CTP_SUBTEXT0 "#a6adc8"
        set -gx CTP_OVERLAY2 "#9399b2"
        set -gx CTP_OVERLAY1 "#7f849c"
        set -gx CTP_OVERLAY0 "#6c7086"
        set -gx CTP_SURFACE2 "#585b70"
        set -gx CTP_SURFACE1 "#45475a"
        set -gx CTP_SURFACE0 "#313244"
        set -gx CTP_SURFACE0_RGB "49;50;68"
        set -gx CTP_BASE "#1e1e2e"
        set -gx CTP_MANTLE "#181825"
        set -gx CTP_CRUST "#11111b"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
    case '*'
        set -gx DOTFILES_CATPPUCCIN_FLAVOUR mocha
        set -gx DOTFILES_CATPPUCCIN_BAT_THEME "Catppuccin Mocha"
        set -gx CTP_ROSEWATER "#f5e0dc"
        set -gx CTP_FLAMINGO "#f2cdcd"
        set -gx CTP_PINK "#f5c2e7"
        set -gx CTP_MAUVE "#cba6f7"
        set -gx CTP_MAUVE_RGB "203;166;247"
        set -gx CTP_RED "#f38ba8"
        set -gx CTP_RED_RGB "243;139;168"
        set -gx CTP_MAROON "#eba0ac"
        set -gx CTP_PEACH "#fab387"
        set -gx CTP_PEACH_RGB "250;179;135"
        set -gx CTP_YELLOW "#f9e2af"
        set -gx CTP_YELLOW_RGB "249;226;175"
        set -gx CTP_GREEN "#a6e3a1"
        set -gx CTP_GREEN_RGB "166;227;161"
        set -gx CTP_TEAL "#94e2d5"
        set -gx CTP_TEAL_RGB "148;226;213"
        set -gx CTP_SKY "#89dceb"
        set -gx CTP_SAPPHIRE "#74c7ec"
        set -gx CTP_SAPPHIRE_RGB "116;199;236"
        set -gx CTP_BLUE "#89b4fa"
        set -gx CTP_BLUE_RGB "137;180;250"
        set -gx CTP_LAVENDER "#b4befe"
        set -gx CTP_TEXT "#cdd6f4"
        set -gx CTP_TEXT_RGB "205;214;244"
        set -gx CTP_SUBTEXT1 "#bac2de"
        set -gx CTP_SUBTEXT0 "#a6adc8"
        set -gx CTP_OVERLAY2 "#9399b2"
        set -gx CTP_OVERLAY1 "#7f849c"
        set -gx CTP_OVERLAY0 "#6c7086"
        set -gx CTP_SURFACE2 "#585b70"
        set -gx CTP_SURFACE1 "#45475a"
        set -gx CTP_SURFACE0 "#313244"
        set -gx CTP_SURFACE0_RGB "49;50;68"
        set -gx CTP_BASE "#1e1e2e"
        set -gx CTP_MANTLE "#181825"
        set -gx CTP_CRUST "#11111b"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
end

set -gx BAT_THEME $DOTFILES_CATPPUCCIN_BAT_THEME
set -gx CLICOLOR 1

set -gx LS_COLORS "\
di=1;38;2;$CTP_BLUE_RGB:\
ln=38;2;$CTP_SAPPHIRE_RGB:\
pi=38;2;$CTP_PEACH_RGB:\
bd=1;38;2;$CTP_MAUVE_RGB:\
cd=1;38;2;$CTP_MAUVE_RGB:\
so=38;2;$CTP_TEAL_RGB:\
ex=1;38;2;$CTP_GREEN_RGB:\
*.zip=38;2;$CTP_RED_RGB:\
*.tar=38;2;$CTP_RED_RGB:\
*.gz=38;2;$CTP_RED_RGB:\
*.bz2=38;2;$CTP_RED_RGB:\
*.xz=38;2;$CTP_RED_RGB:\
*.zst=38;2;$CTP_RED_RGB:\
*README=1;4;38;2;$CTP_YELLOW_RGB:\
*README.md=1;4;38;2;$CTP_YELLOW_RGB:\
*Makefile=1;4;38;2;$CTP_YELLOW_RGB:\
*Cargo.toml=1;4;38;2;$CTP_YELLOW_RGB:\
*package.json=1;4;38;2;$CTP_YELLOW_RGB:\
*Dockerfile=1;4;38;2;$CTP_YELLOW_RGB:\
*Brewfile=1;4;38;2;$CTP_YELLOW_RGB"

set -g fish_color_normal $CTP_TEXT
set -g fish_color_command $CTP_BLUE
set -g fish_color_keyword $CTP_MAUVE
set -g fish_color_quote $CTP_GREEN
set -g fish_color_redirection $CTP_TEAL
set -g fish_color_end $CTP_PEACH
set -g fish_color_error $CTP_RED
set -g fish_color_param $CTP_TEXT
set -g fish_color_comment $CTP_OVERLAY1
set -g fish_color_selection "--background=$CTP_SURFACE0"
set -g fish_color_search_match "--background=$CTP_SURFACE1" "--foreground=$CTP_TEXT"
set -g fish_color_operator $CTP_SKY
set -g fish_color_escape $CTP_PINK
set -g fish_color_autosuggestion $CTP_OVERLAY0
set -g fish_color_valid_path $CTP_GREEN
set -g fish_color_cwd $CTP_BLUE
set -g fish_color_cwd_root $CTP_RED
set -g fish_color_user $CTP_LAVENDER
set -g fish_color_host $CTP_SAPPHIRE
set -g fish_color_host_remote $CTP_PEACH
set -g fish_color_cancel $CTP_RED
set -g fish_color_option $CTP_YELLOW

set -g fish_pager_color_background
set -g fish_pager_color_prefix $CTP_MAUVE
set -g fish_pager_color_progress $CTP_OVERLAY0
set -g fish_pager_color_completion $CTP_TEXT
set -g fish_pager_color_description $CTP_SUBTEXT0
set -g fish_pager_color_selected_background "--background=$CTP_SURFACE0"
set -g fish_pager_color_selected_prefix $CTP_BLUE
set -g fish_pager_color_selected_completion $CTP_TEXT
set -g fish_pager_color_selected_description $CTP_SUBTEXT1
