# Ghostty can outlive the Herdr process that launched it. New windows then
# inherit stale HERDR_* values even though they are not inside Herdr.
function __dotfiles_is_inside_herdr
    set -l pid $fish_pid

    while string match -qr '^[0-9]+$' -- "$pid"; and test "$pid" -gt 1
        set pid (command ps -p "$pid" -o ppid= 2>/dev/null | string trim)
        string match -qr '^[0-9]+$' -- "$pid"; or return 1

        set -l executable (command ps -p "$pid" -o comm= 2>/dev/null | string trim)
        if test -n "$executable"
            switch (path basename -- "$executable")
                case herdr
                    return 0
                case ghostty
                    # HERDR_* inherited by the terminal itself is stale for a
                    # new regular window, even if Herdr launched the app.
                    return 1
            end
        end
    end

    return 1
end

set -l __dotfiles_herdr_variables (set --names | string match 'HERDR_*')
if test (count $__dotfiles_herdr_variables) -gt 0; and not __dotfiles_is_inside_herdr
    for variable in $__dotfiles_herdr_variables
        set -e $variable
    end
end
functions -e __dotfiles_is_inside_herdr

set -gx NOTES_DIR $HOME/notes
set -gx NOTES_DIRECTORY $HOME/notes
set -gx LANG en_US.UTF-8
set -gx LANGUAGE $LANG
set -gx LC_CTYPE $LANG
set -gx LC_ALL $LANG
set -gx VIRTUAL_ENV_DISABLE_PROMPT 1
set -gx HGENCODING utf-8
set -gx PAGER less
set -gx LESS '-g -i -M -R -S -W -z-4 -x4'
set -gx EDITOR vim
set -gx PROMPT_SEVERITY 0
set -gx TRASHBIN $HOME/.trash
set -g fish_cursor_default block blink

if test -t 0
    set -gx GPG_TTY (tty)
end

function __dotfiles_set_path
    set -l merged

    for dir in $argv
        if test -n "$dir"; and not contains -- $dir $merged
            set -a merged $dir
        end
    end

    for dir in $PATH
        if test -n "$dir"; and not contains -- $dir $merged
            set -a merged $dir
        end
    end

    set -gx PATH $merged
end

function __dotfiles_import_posix_exports --argument-names envfile
    test -f "$envfile"; or return 0

    while read -l line
        set line (string trim -- $line)

        if test -z "$line"
            continue
        end
        if string match -qr '^#' -- $line
            continue
        end

        set line (string replace -r ';+\s*$' '' -- $line)
        set line (string replace -r '^\s*export\s+' '' -- $line)

        if not string match -qr '=' -- $line
            continue
        end

        set -l parts (string split -m 1 '=' -- $line)
        set -l key (string trim -- $parts[1])
        set -l value (string trim -- $parts[2])

        set value (string replace -r '^"(.*)"$' '$1' -- $value)
        set value (string replace -r "^'(.*)'\$" '$1' -- $value)

        set -gx $key $value
    end < "$envfile"
end

function __dotfiles_eza
    if not set -q __dotfiles_eza_hyperlink_mode
        if env -u LS_COLORS -u EXA_COLORS -u EZA_COLORS eza --help 2>/dev/null | string match -rq -- '--hyperlink \[<WHEN>\]'
            set -g __dotfiles_eza_hyperlink_mode when
        else
            set -g __dotfiles_eza_hyperlink_mode bare
        end
    end

    set -l args
    for arg in $argv
        if test "$arg" = '--hyperlink=auto'
            if test "$__dotfiles_eza_hyperlink_mode" = when
                set -a args $arg
            else if isatty stdout
                set -a args --hyperlink
            end
        else
            set -a args $arg
        end
    end

    env -u LS_COLORS -u EXA_COLORS -u EZA_COLORS eza $args
end

function __dotfiles_list_dir
    if command -sq eza
        __dotfiles_eza --icons=auto --group-directories-first --hyperlink=auto .
    else if command -sq exa
        exa --icons .
    else
        ls --color=auto .
    end
end
