{ config, lib, ... }:
let
  source = ../../files/config/omp;
in
{
  home.file = {
    ".omp/agent/models.yml".source = source + /models.yml;
    ".omp/agent/AGENTS.md".source = source + /AGENTS.md;
    ".omp/agent/RULES.md".source = source + /RULES.md;
    ".omp/agent/themes/catppuccin-mocha-mauve.json".source =
      source + /themes/catppuccin-mocha-mauve.json;
  };

  # OMP locks and atomically rewrites config.yml. Keep it writable, not a store link.
  # Declarative defaults replace interactive changes on each activation.
  home.activation.installOmpConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    agent_dir="${config.home.homeDirectory}/.omp/agent"
    config_tmp=$(mktemp "$agent_dir/config.yml.XXXXXX")
    install -m 0600 ${source}/config.yml "$config_tmp"
    mv -f "$config_tmp" "$agent_dir/config.yml"
  '';
}
