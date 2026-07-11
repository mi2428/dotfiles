set -gx DOTFILES_CATPPUCCIN_FLAVOUR mocha
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR latte
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR frappe
# set -gx DOTFILES_CATPPUCCIN_FLAVOUR macchiato

if not contains -- $DOTFILES_CATPPUCCIN_FLAVOUR latte frappe macchiato mocha
    set -gx DOTFILES_CATPPUCCIN_FLAVOUR mocha
end

switch $DOTFILES_CATPPUCCIN_FLAVOUR
    case latte
        set -gx DOTFILES_CATPPUCCIN_FISH_THEME catppuccin-mocha
        set -gx DOTFILES_CATPPUCCIN_FISH_COLOR_THEME light
        set -gx BAT_THEME "Catppuccin Latte"
        set -gx LSCOLORS "exfxcxdxbxegedabagacad"
        set -gx CTP_BLUE "#1e66f5"
        set -gx CTP_BLUE_RGB "30;102;245"
        set -gx CTP_GREEN "#40a02b"
        set -gx CTP_GREEN_RGB "64;160;43"
        set -gx CTP_LAVENDER "#7287fd"
        set -gx CTP_MAUVE "#8839ef"
        set -gx CTP_MAUVE_RGB "136;57;239"
        set -gx CTP_OVERLAY0 "#9ca0b0"
        set -gx CTP_OVERLAY1 "#8c8fa1"
        set -gx CTP_PEACH "#fe640b"
        set -gx CTP_PEACH_RGB "254;100;11"
        set -gx CTP_RED_RGB "210;15;57"
        set -gx CTP_ROSEWATER "#dc8a78"
        set -gx CTP_SAPPHIRE_RGB "32;159;181"
        set -gx CTP_SKY "#04a5e5"
        set -gx CTP_SUBTEXT1 "#5c5f77"
        set -gx CTP_SURFACE0 "#ccd0da"
        set -gx CTP_SURFACE0_RGB "204;208;218"
        set -gx CTP_TEAL "#179299"
        set -gx CTP_TEAL_RGB "23;146;153"
        set -gx CTP_TEXT "#4c4f69"
        set -gx CTP_TEXT_RGB "76;79;105"
        set -gx CTP_YELLOW "#df8e1d"
        set -gx CTP_YELLOW_RGB "223;142;29"
    case frappe
        set -gx DOTFILES_CATPPUCCIN_FISH_THEME catppuccin-frappe
        set -gx DOTFILES_CATPPUCCIN_FISH_COLOR_THEME dark
        set -gx BAT_THEME "Catppuccin Frappe"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
        set -gx CTP_BLUE "#8caaee"
        set -gx CTP_BLUE_RGB "140;170;238"
        set -gx CTP_GREEN "#a6d189"
        set -gx CTP_GREEN_RGB "166;209;137"
        set -gx CTP_LAVENDER "#babbf1"
        set -gx CTP_MAUVE "#ca9ee6"
        set -gx CTP_MAUVE_RGB "202;158;230"
        set -gx CTP_OVERLAY0 "#737994"
        set -gx CTP_OVERLAY1 "#838ba7"
        set -gx CTP_PEACH "#ef9f76"
        set -gx CTP_PEACH_RGB "239;159;118"
        set -gx CTP_RED_RGB "231;130;132"
        set -gx CTP_ROSEWATER "#f2d5cf"
        set -gx CTP_SAPPHIRE_RGB "133;193;220"
        set -gx CTP_SKY "#99d1db"
        set -gx CTP_SUBTEXT1 "#b5bfe2"
        set -gx CTP_SURFACE0 "#414559"
        set -gx CTP_SURFACE0_RGB "65;69;89"
        set -gx CTP_TEAL "#81c8be"
        set -gx CTP_TEAL_RGB "129;200;190"
        set -gx CTP_TEXT "#c6d0f5"
        set -gx CTP_TEXT_RGB "198;208;245"
        set -gx CTP_YELLOW "#e5c890"
        set -gx CTP_YELLOW_RGB "229;200;144"
    case macchiato
        set -gx DOTFILES_CATPPUCCIN_FISH_THEME catppuccin-macchiato
        set -gx DOTFILES_CATPPUCCIN_FISH_COLOR_THEME dark
        set -gx BAT_THEME "Catppuccin Macchiato"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
        set -gx CTP_BLUE "#8aadf4"
        set -gx CTP_BLUE_RGB "138;173;244"
        set -gx CTP_GREEN "#a6da95"
        set -gx CTP_GREEN_RGB "166;218;149"
        set -gx CTP_LAVENDER "#b7bdf8"
        set -gx CTP_MAUVE "#c6a0f6"
        set -gx CTP_MAUVE_RGB "198;160;246"
        set -gx CTP_OVERLAY0 "#6e738d"
        set -gx CTP_OVERLAY1 "#8087a2"
        set -gx CTP_PEACH "#f5a97f"
        set -gx CTP_PEACH_RGB "245;169;127"
        set -gx CTP_RED_RGB "237;135;150"
        set -gx CTP_ROSEWATER "#f4dbd6"
        set -gx CTP_SAPPHIRE_RGB "125;196;228"
        set -gx CTP_SKY "#91d7e3"
        set -gx CTP_SUBTEXT1 "#b8c0e0"
        set -gx CTP_SURFACE0 "#363a4f"
        set -gx CTP_SURFACE0_RGB "54;58;79"
        set -gx CTP_TEAL "#8bd5ca"
        set -gx CTP_TEAL_RGB "139;213;202"
        set -gx CTP_TEXT "#cad3f5"
        set -gx CTP_TEXT_RGB "202;211;245"
        set -gx CTP_YELLOW "#eed49f"
        set -gx CTP_YELLOW_RGB "238;212;159"
    case mocha
        set -gx DOTFILES_CATPPUCCIN_FISH_THEME catppuccin-mocha
        set -gx DOTFILES_CATPPUCCIN_FISH_COLOR_THEME dark
        set -gx BAT_THEME "Catppuccin Mocha"
        set -gx LSCOLORS "gxfxcxdxbxegedabagacad"
        set -gx CTP_BLUE "#89b4fa"
        set -gx CTP_BLUE_RGB "137;180;250"
        set -gx CTP_GREEN "#a6e3a1"
        set -gx CTP_GREEN_RGB "166;227;161"
        set -gx CTP_LAVENDER "#b4befe"
        set -gx CTP_MAUVE "#cba6f7"
        set -gx CTP_MAUVE_RGB "203;166;247"
        set -gx CTP_OVERLAY0 "#6c7086"
        set -gx CTP_OVERLAY1 "#7f849c"
        set -gx CTP_PEACH "#fab387"
        set -gx CTP_PEACH_RGB "250;179;135"
        set -gx CTP_RED_RGB "243;139;168"
        set -gx CTP_ROSEWATER "#f5e0dc"
        set -gx CTP_SAPPHIRE_RGB "116;199;236"
        set -gx CTP_SKY "#89dceb"
        set -gx CTP_SUBTEXT1 "#bac2de"
        set -gx CTP_SURFACE0 "#313244"
        set -gx CTP_SURFACE0_RGB "49;50;68"
        set -gx CTP_TEAL "#94e2d5"
        set -gx CTP_TEAL_RGB "148;226;213"
        set -gx CTP_TEXT "#cdd6f4"
        set -gx CTP_TEXT_RGB "205;214;244"
        set -gx CTP_YELLOW "#f9e2af"
        set -gx CTP_YELLOW_RGB "249;226;175"
end

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

set -l eza_config_dir "$HOME/.config/eza/$DOTFILES_CATPPUCCIN_FLAVOUR"
set -l source_file (path resolve (status filename))
set -l etc_root (path dirname (path dirname (path dirname $source_file)))
if not test -f "$eza_config_dir/theme.yml"
    set eza_config_dir "$etc_root/eza/$DOTFILES_CATPPUCCIN_FLAVOUR"
end
set -gx EZA_CONFIG_DIR $eza_config_dir

if not status is-interactive
    return
end

set -l theme_available 1
contains -- $DOTFILES_CATPPUCCIN_FISH_THEME (fish_config theme list) >/dev/null
or set theme_available 0

if test $theme_available -eq 1
    fish_config theme choose $DOTFILES_CATPPUCCIN_FISH_THEME --color-theme=$DOTFILES_CATPPUCCIN_FISH_COLOR_THEME >/dev/null 2>&1
end
