# chezmoi

This directory is reserved for bootstrap and secret-adjacent state.

Ownership:

- bootstrap into Nix and Home Manager
- password-manager-backed templates
- private or machine-local files not yet managed by Home Manager
- private GnuPG state such as `private_dot_gnupg/`

Steady-state shell, editor, package, and service configuration lives under
`home/`.
