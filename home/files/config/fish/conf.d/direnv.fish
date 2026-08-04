# Resolve direnv through PATH so the hook keeps the stable profile symlink across Nix GC.
command direnv hook fish | source
