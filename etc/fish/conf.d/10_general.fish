set -gx PATH_BOOKMARK $HOME/.zsh_pathbook
set -gx NOTES_DIR $HOME/notes
set -gx NOTES_DIRECTORY $HOME/notes
set -gx TERM xterm-256color
set -gx LANG en_US.UTF-8
set -gx LANGUAGE $LANG
set -gx LC_CTYPE $LANG
set -gx LC_ALL $LANG
set -gx VIRTUAL_ENV_DISABLE_PROMPT 1
set -gx LS_COLORS 'di=1;34:ln=0;36:pi=0;33:bd=1;33:cd=1;33:so=1;31:ex=1;32:*README=1;4;33:*README.txt=1;4;33:*README.md=1;4;33:*readme.txt=1;4;33:*readme.md=1;4;33:*.ninja=1;4;33:*Makefile=1;4;33:*Cargo.toml=1;4;33:*SConstruct=1;4;33:*CMakeLists.txt=1;4;33:*build.gradle=1;4;33:*pom.xml=1;4;33:*Rakefile=1;4;33:*package.json=1;4;33:*Gruntfile.js=1;4;33:*Gruntfile.coffee=1;4;33:*BUILD=1;4;33:*BUILD.bazel=1;4;33:*WORKSPACE=1;4;33:*build.xml=1;4;33:*Podfile=1;4;33:*webpack.config.js=1;4;33:*meson.build=1;4;33:*composer.json=1;4;33:*RoboFile.php=1;4;33:*PKGBUILD=1;4;33:*Justfile=1;4;33:*Procfile=1;4;33:*Dockerfile=1;4;33:*Containerfile=1;4;33:*Vagrantfile=1;4;33:*Brewfile=1;4;33:*Gemfile=1;4;33:*Pipfile=1;4;33:*build.sbt=1;4;33:*mix.exs=1;4;33:*bsconfig.json=1;4;33:*tsconfig.json=1;4;33:*.zip=0;31:*.tar=0;31:*.Z=0;31:*.z=0;31:*.gz=0;31:*.bz2=0;31:*.a=0;31:*.ar=0;31:*.7z=0;31:*.iso=0;31:*.dmg=0;31:*.tc=0;31:*.rar=0;31:*.par=0;31:*.tgz=0;31:*.xz=0;31:*.txz=0;31:*.lz=0;31:*.tlz=0;31:*.lzma=0;31:*.deb=0;31:*.rpm=0;31:*.zst=0;31:*.lz4=0;31'
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
        eza --icons=auto .
    else if command -sq exa
        exa --icons .
    else
        ls --color=auto .
    end
end
