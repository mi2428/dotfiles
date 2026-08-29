# dotfiles

Shell environment since 2016. Currently:

- Daily stack: [Ghostty](https://ghostty.org/), fish, [OpenCode](https://opencode.ai/), [herdr](https://herdr.dev/) (for AI agents), tmux (for humans), and Neovim.
- Primary font: [Summer Ghost](https://github.com/mi2428/font-summer-ghost), a custom Japanese monospace font blend for Ghostty. Install it separately before applying these dotfiles; Nerd Font glyphs come from Ghostty's built-in fallback.
- Terminal theme: [Catppuccin](https://github.com/catppuccin/catppuccin), usually [Mocha](https://catppuccin.com/palette/).
- Managed state is split between [Nix](https://github.com/nix-community/home-manager) and [chezmoi](https://github.com/twpayne/chezmoi): `flake.nix` and `home/` define the steady state, while `chezmoi/` handles bootstrap and encrypted secrets.

Catppuccin can shift expected color names a bit, so cyan or light blue may look slightly green in CLI output.
This mostly affects apps that use ANSI color slots, which the terminal maps through the active theme palette.

>[!TIP]
> **TL;DR** This one-liner clones or updates the repo in `~/dotfiles` and then runs [`bootstrap/bootstrap.sh`](bootstrap/bootstrap.sh).
> ```console
> bash -c "$(curl -fsLS https://raw.githubusercontent.com/mi2428/dotfiles/refs/heads/master/scripts/setup.sh)"
> ```

## Bootstrap Guide

If you already have the repo checked out and want to run bootstrap directly, use [`bootstrap/bootstrap.sh`](bootstrap/bootstrap.sh).

```console
$ brew install --cask ghostty
```

```console
$ cd ~/dotfiles
$ ./bootstrap/bootstrap.sh --host macos  # macOS
$ ./bootstrap/bootstrap.sh --host linux  # Linux
```

What bootstrap does:

- [`scripts/setup.sh`](scripts/setup.sh) clones or fast-forwards the repo in `~/dotfiles`, then runs [`bootstrap/bootstrap.sh`](bootstrap/bootstrap.sh).
- [`bootstrap/bootstrap.sh`](bootstrap/bootstrap.sh) applies chezmoi state first, then runs the host-specific Nix activation.
- On macOS, host auto-detection resolves from the machine serial number.
- On Linux, host auto-detection resolves from container markers first and then `/etc/machine-id`.
- Secret template data lives in [`chezmoi/.chezmoidata/`](chezmoi/.chezmoidata/).

After bootstrap, `task` shows the common maintenance commands:

```console
$ task

Tasks
  hm.build           Build the current host activation without switching
  hm.switch          Apply the current host activation and refresh managed symlinks
  hm.link            Re-apply the current host activation to re-create managed symlinks
  hm.update          Update Nix inputs in flake.lock and apply the current host activation
  hm.gc              Delete old generations and collect Nix garbage (run without sudo)
  brew.check         Check the repo-managed Brewfile against the local Homebrew state
  brew.sync          Update and upgrade Homebrew, then apply the repo-managed Brewfile
  ai.check           Check AI harness versions, Herdr integrations, and pinned OpenCode config
  ai.upgrade         Upgrade AI harnesses and refresh exact OmO and Slim plugin pins
  ai.webui.up        Start Open WebUI and cptr with Docker
  ai.webui.down      Stop Open WebUI and cptr without deleting their data
  ai.webui.logs      Follow Open WebUI and cptr logs
  secrets.encrypt    Encrypt ssh and/or gnupg into chezmoi source state
  secrets.decrypt    Decrypt ssh and/or gnupg into a target directory
  secrets.backup     Backup ssh and gnupg into encrypted chezmoi source state
  secrets.clear      Remove local staging and decrypted secret work directories
  docker.build       Build Dockerfile locally as ghcr.io/OWNER/IMAGE:TAG
  docker.login       Login to ghcr.io with GHCR_TOKEN, GITHUB_TOKEN, or gh auth token
  docker.push        Build and push Dockerfile to ghcr.io as ghcr.io/OWNER/IMAGE:TAG
  docker.run         Run the MCP workspace container on 127.0.0.1:3000

Defaults
  GHCR_OWNER         mi2428
  GHCR_IMAGE_NAME    dotfiles
  TAG                latest
  DOCKER_RUNTIME     docker
  PORT               3000
  WORKSPACE_DIR      repository root
  CONTAINER_NAME     dotfiles-mcp
  PLATFORMS          linux/amd64,linux/arm64
  HOST               auto-detected from the current machine
  IMPORT_GPG         0
  DECRYPT_HOME       $HOME/.cache/dotfiles/secrets/decrypted-home

Examples
  task hm.update HOST=macos
  task hm.switch HOST=docker
  task hm.gc
  task secrets.encrypt
  task secrets.encrypt BUNDLE=ssh
  task secrets.encrypt BUNDLE=gnupg GPG_KEY_IDS='E8D3009C6341BDEAF038009685AB6867E2147DDA'
  task secrets.decrypt IMPORT_GPG=1 DECRYPT_HOME=$HOME
  task secrets.backup
  task docker.build TAG=latest
  task docker.push TAG=latest
```

On macOS, Homebrew is intentionally decoupled from `darwin-rebuild`.
Use the repo-root `Brewfile` with `task brew.check` and `task brew.sync` for Homebrew state, then use `task hm.switch HOST=macos` for Nix-managed changes.

Run `task hm.gc` as the login user, never as `sudo task hm.gc`; it elevates only
the system garbage-collection pass. macOS SIP protects `com.apple.macl`, so a
path blocked by that attribute cannot be removed from a normally booted system;
delete it only from macOS Recovery or a separately booted volume.

For quick config checks, you do not need to run `hm.switch` for every small change.
Use [`bin/dotfiles-dev`](bin/dotfiles-dev), which builds a writable projected `XDG_CONFIG_HOME` per app from the repo tree:

```console
$ ./bin/dotfiles-dev xdg fish  # or ./bin/fish.dev
$ ./bin/dotfiles-dev ghostty   # or ./bin/ghostty.dev
```

Each app gets its own projected config root under `~/.local/share/dotfiles-dev/config/`, so runtime files stay out of the tracked repo while the app still reads the in-progress config from `home/files/config`.
Some commands also have `*.dev` wrappers under `/bin`, such as `fish.dev` and `tmux.dev`.

> [!WARNING]
> `age.init` and `age.unlock` are maintenance commands.
> Create a new age identity only on the very first machine setup:
> 
> ```console
> $ task age.init
> ```
> 
> If `~/.config/chezmoi/key.txt`, [`chezmoi/key.txt.age`](chezmoi/key.txt.age), or [`chezmoi/.chezmoidata/secrets.yaml`](chezmoi/.chezmoidata/secrets.yaml) already exists, `task age.init` refuses to run.
> Rekey only when you intentionally want to rotate the repo recipient and re-encrypt every bundle:
> 
> ```console
> $ task age.init FORCE=1
> $ task secrets.backup
> ```
> 
> Use `age.unlock` on a machine that should reuse the existing committed repo identity:
> 
> ```console
> $ task age.unlock
> ```

> [!TIP]
> The repo includes a local MCP coding workspace with Streamable HTTP at `http://127.0.0.1:3000/mcp` and `/healthz` for readiness.
> 
> ```console
> $ task docker.build
> $ task docker.run PORT=3000 WORKSPACE_DIR=$PWD
> $ task mcp.test
> $ task mcp.test-container
> $ docker exec -it dotfiles-mcp sudo -H -u teo /etc/skel/.nix-profile/bin/zsh --login
> $ docker stop dotfiles-mcp
> ```
> 
> The Go server in [`mcp/`](mcp/) uses the official MCP Go SDK and exposes `read_path`, `search_files`, `apply_patch`, and `run_command`. File operations are confined to `/work`; commands start there and remain isolated inside the container.
> 
> If you already have `gh` auth on the host, `task docker.run` forwards `GH_TOKEN` automatically.
> You can override the container name with `CONTAINER_NAME=`.
> 
> OpenCode or any MCP client can point at:
> 
> ```json
> {
>   "$schema": "https://opencode.ai/config.json",
>   "mcp": {
>     "dotfiles": {
>       "type": "remote",
>       "url": "http://127.0.0.1:3000/mcp",
>       "enabled": true
>     }
>   }
> }
> ```

### Open WebUI and Computer

[Open WebUI](https://openwebui.com/) and [Open WebUI Computer](https://openwebui.com/computer) run together under Docker. Computer has read-write access to `CPTR_WORKSPACE_DIR`, so mount only a trusted workspace. Persistent data lives in named volumes and `<workspace>/.cptr`; manage Open WebUI Admin UI configuration in Compose because UI changes do not survive a restart.

```console
$ cp containers/open-webui/.env.example containers/open-webui/.env
$ openssl rand -hex 32  # use this for WEBUI_SECRET_KEY, then set the remaining required values
$ task ai.webui.up
$ task ai.webui.logs    # follow service logs
$ task ai.webui.down    # stops containers without deleting persistent data
```

## Random Notes

#### PAM

Touch ID and Apple Watch sudo are managed by nix-darwin via `security.pam.services.sudo_local`.
On a new macOS machine, apply the flake and keep manual PAM edits out of `/etc/pam.d`.
If Apple Watch sudo does not appear after activation, re-check the toggle in `System Settings > Touch ID & Password`.

#### sudoers

Use `visudo` only for machine-local exceptions that are intentionally outside the flake.
Do not copy the stock `root` or `%admin` entries into local notes unless they actually need to change.

```console
$ sudo visudo

# local exceptions only
mi      ALL = NOPASSWD: /usr/sbin/tcpdump,/usr/sbin/purge
```

#### 1Password

Remember to enable CLI integration in 1Password or it will keep asking for the vault password.
The path was `Settings > Developer > Command-Line Interface (CLI) > Integrate with 1Password CLI`.

#### iTerm2 Preferences

Old iTerm2 preferences worth remembering:

- Under `General / Selection`, keep "Applications in terminal may access clipboard" enabled.
- Under `Appearance / General`, use the **Minimal** theme, put the tab bar at the top, and the status bar at the bottom.
- Under `Appearance / Tabs`, keep "Show tab bar even when there is only one tab" enabled.
- Under `Appearance / Dimming`, keep inactive split dimming disabled.
- Under `Advanced / Hotkey`, set the hotkey window animation duration to `0`.
- Under `Advanced / Session`, keep "Allow sessions to survive logging out and back in" set to `No`.

## References

- https://rycee.net/posts/2017-07-02-manage-your-home-with-nix.html
