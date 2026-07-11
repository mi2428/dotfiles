set -gx PATH_BOOKMARK $HOME/.zsh_pathbook
set -gx NOTES_DIR $HOME/notes
set -gx NOTES_DIRECTORY $HOME/notes
set -gx TERM xterm-256color
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

if test -t 0
    set -gx GPG_TTY (tty)
end

test -f $PATH_BOOKMARK; or touch $PATH_BOOKMARK

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
    test -f $envfile; or return 0

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
    end < $envfile
end

function __dotfiles_remove_path_bookmark --argument-names bookmark
    test -n "$bookmark"; or return 0
    test -f $PATH_BOOKMARK; or touch $PATH_BOOKMARK

    set -l tmpfile (mktemp)
    grep -Fvx -- "$bookmark" $PATH_BOOKMARK >$tmpfile 2>/dev/null
    mv $tmpfile $PATH_BOOKMARK
end

function __dotfiles_list_dir
    if command -sq eza
        eza --icons=auto --group-directories-first --hyperlink=auto .
    else if command -sq exa
        exa --icons .
    else
        ls --color=auto .
    end
end
