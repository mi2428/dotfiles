{ ... }: {
  home.sessionPath = [
    "/usr/local/bin"
    "/usr/local/sbin"
    "/snap/bin"
  ];

  home.file.".bash_profile".text = ''
    if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
      . "$HOME/.bashrc"
    fi

    for profile_script in \
      "$HOME/.nix-profile/etc/profile.d/nix.sh" \
      "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    do
      [ -r "$profile_script" ] && . "$profile_script"
    done

    if [ -d "$HOME/bin" ]; then
      PATH="$HOME/bin:$PATH"
    fi

    if [ -d "$HOME/.local/bin" ]; then
      PATH="$HOME/.local/bin:$PATH"
    fi

    export PATH
  '';
}
