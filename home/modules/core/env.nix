{ ... }: {
  home.sessionPath = [
    "$HOME/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "$HOME/bin"
    "$HOME/io/bin"
    "$HOME/.local/bin"
    "$HOME/.deno/bin"
    "$HOME/.cargo/bin"
    "$HOME/io/gocode/bin"
  ];

  home.sessionVariables = {
    CARGO_HOME = "$HOME/.cargo";
    DENO_INSTALL = "$HOME/.deno";
    EDITOR = "nvim";
    GOPATH = "$HOME/io/gocode";
    GOPRIVATE = "github.com/soracom";
    HGENCODING = "utf-8";
    LANG = "en_US.UTF-8";
    LANGUAGE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LESS = "-g -i -M -R -S -W -z-4 -x4";
    NOTES_DIR = "$HOME/notes";
    NOTES_DIRECTORY = "$HOME/notes";
    PAGER = "less";
    PROMPT_SEVERITY = "0";
    TRASHBIN = "$HOME/.trash";
    VIRTUAL_ENV_DISABLE_PROMPT = "1";
    VISUAL = "nvim";
  };
}
