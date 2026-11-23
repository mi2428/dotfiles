{ config, lib, ... }:
let
  source = ../../files/config/omo;
in
{
  # mise owns the omo-ai package on both Omarchy and macOS.
  xdg.configFile."mise/conf.d/50-dotfiles-ai.toml".source =
    ../../files/config/mise/conf.d/50-dotfiles-ai.toml;

  home.file.".omo/agent/themes/catppuccin-mocha.json".source =
    source + /themes/catppuccin-mocha.json;

  # OmO rewrites settings.json and models.json (model discovery, /model), and
  # the migration engine can touch omo.jsonc. Keep them writable and atomically
  # replace the declared defaults on each activation, like OMP config.yml.
  home.activation.installOmoConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    omo_dir="${config.home.homeDirectory}/.omo"
    agent_dir="$omo_dir/agent"
    install -d -m 0700 "$omo_dir" "$agent_dir"

    install_omo_file() {
      target=$1
      mode=$2
      tmp=$(mktemp "$target.XXXXXX")
      install -m "$mode" ${source}/"$3" "$tmp"
      mv -f "$tmp" "$target"
    }

    install_omo_file "$omo_dir/omo.jsonc" 0600 omo.jsonc
    install_omo_file "$agent_dir/models.json" 0600 models.json
    install_omo_file "$agent_dir/settings.json" 0600 settings.json
  '';
}
