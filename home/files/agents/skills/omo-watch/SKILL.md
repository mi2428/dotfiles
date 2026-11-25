---
name: omo-watch
description: >
  Watch omo terminals hosted by herdr-core (hc) and recover one that died,
  froze, hit a provider/compaction stall, or shows a fatal message at the
  prompt. Recovery keeps the pane's shell alive, kills only the omo process
  tree, restarts omo with the previous thinking level, and submits a mass-ulw
  handoff prompt naming the predecessor's error and session file. Use when
  asked to babysit, watch, supervise, or auto-recover omo, or when a long omo
  run must survive provider stalls and crashes.
argument-hint: "[--pane ADDR] [--name NAME] [--project DIR]"
---

# omo-watch

The watcher is a skill, not a system daemon. Run it from this agent as an omp
background service (or a foreground shell) so it lives with the session that
owns it. Runtime state and logs go under `$XDG_RUNTIME_DIR/omo-watch`; nothing
is installed into `~/.local` or systemd.

## What it watches

`hc` is herdr-core's CLI, not `herdr`'s workspace CLI. An omo pane is a live
herdr-core terminal whose status reports `app: omo` (`status.app` in
`hc ls --json`; the older `agent` spelling is also accepted). The shell in
that terminal survives when omo exits, and the terminal then reports no
status.

Each poll it asks:

- `hc ls --json` for live terminals whose `status.app` is `omo` (filter with
  `--name` / `--project`), plus any `--pane` fallback address and previously
  seen addresses.
- `hc get <addr> --json` for the foreground pid, cwd, and status.
- `hc read <addr> --lines 120` for the TUI footer and fatal messages.

Discovery is dynamic, so a new omo terminal is picked up without restarting
the watcher. The address of a recreated terminal changes; a pane that omo
crashed out of is remembered by address while its shell is still alive, and
omo is restarted there. If the whole terminal disappears, the watcher cannot
know where to recreate it; pass `--pane` for the pane that must be recovered.

Multiple omos are monitored independently, with per-target timers, recovery
budget, and thinking level. Each target claims a different session file while
the project has more than one; a same-project pair is still ambiguous when
files run out, so give each pane a stable `hc run --name` (or use different
projects) if you need the handoff to name the exact predecessor session.

## Detection

| Signal | Trigger |
|---|---|
| omo foreground gone, shell remains | `--absent-grace` seconds (default 30) |
| `status=working` with no progress | `--stall` seconds (default 900) |
| fatal provider/compaction text at the prompt | persists `--fatal-grace` seconds (default 30) |
| `Working (Ns` visible while status is not working | persists `--frozen-grace` seconds (default 60) |
| `Goal blocked: … waiting_human` in the footer | persists `--blocked-grace` seconds (default 600) |

Progress is the captured session JSONL's size/mtime plus CPU of the omo
process tree (streaming model or a tool build). The herdr turn number is
reported in the trigger evidence but is not a progress signal. TUI animation
alone must not count: root CPU below 2% and no log growth is not progress.

## Recovery

1. Capture the pane tail, session path, last event, and recent error lines.
2. Write the evidence and prompt to
   `$XDG_RUNTIME_DIR/omo-watch/handoffs/handoff-*.md`.
3. SIGTERM then SIGKILL the foreground omo process tree. The pane's fish
   process is not a descendant and survives.
4. Wait for the shell, run `omo --thinking <level>`: the level comes from the
   footer in the pane tail, else the last level captured while that omo was
   alive, else plain `omo`. A custom `--launch` is used as-is. Wait for the
   TUI, and submit:

   ```text
   mass ulw で作業を引き継いでください。前任者は以下のエラーで停止していました
   <error>
   - 検出: ...
   - 端末/旧PID: ...
   - 旧セッション: ...
   - 最後のイベント: ...
   - 作業ディレクトリ: ...
   - 詳細ログ: ...
   ```

5. Verify the prompt is visible and the new turn is working. Recovery is
   capped at `--max-recoveries` per target per hour.

## Run it

Dry run first:

```bash
pane=<address>  # from `hc ls --json`: .terminals[].address
python3 ~/.agents/skills/omo-watch/watch.py --pane "$pane" --once --dry-run
python3 ~/.agents/skills/omo-watch/watch.py --once --dry-run   # discover all omos
```

As an omp background service (this is the normal mode):

```bash
# bash tool: name=omo-watch, pty=false, ready log="watchdog start",
# notify regex="TRIGGER|RECOVER|recover error"
python3 ~/.agents/skills/omo-watch/watch.py --pane "$pane" --poll 15 --stall 900
```

Useful flags: `--name`, `--project`, `--launch`, `--force`, `--once`,
`--dry-run`, `--poll`, `--stall`, `--absent-grace`, `--fatal-grace`,
`--frozen-grace`, `--blocked-grace`, `--busy-pct`, `--max-recoveries`,
`--ready-timeout`.

`--force` needs `--pane` or `--name` and touches only those targets (the
intersection when both are given); it never recovers every discovered omo.
Add `--once` for a one-shot forced handoff, otherwise the normal watch loop
continues after it. `--dry-run` writes the handoff and logs the launch it
would use without killing or sending.

## Operate

- State root: `$XDG_RUNTIME_DIR/omo-watch` (`OMO_WATCH_RUNTIME` overrides
  it). It must be owned by your uid; the watcher refuses to start otherwise.
- `hc` is resolved from `PATH`; `OMO_WATCH_HC` pins an explicit binary.
- Locks: `lock` for a real run, `lock-dry` for `--dry-run`, so a rehearsal
  never blocks the service (or vice versa). The lock file records the pid.
- Log: `.../watch.log` (heartbeat every 10 minutes).
- Pause recovery but keep polling: `touch .../paused`; remove the file to
  resume. Every target is re-armed on resume, so a long pause cannot look
  like a stall or a crash.
- Force a handoff now: `--force --pane <addr>` or `--force --name <name>`
  (omit `--dry-run` to act).
- The service dies with the owning omp session. That is deliberate: the
  watcher is the agent's job, not a machine-wide daemon. Restart it from the
  skill when a new session takes over.
