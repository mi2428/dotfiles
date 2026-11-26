---
name: omo-watch
description: >
  Watch omo terminals hosted by herdr-core (hc) and recover one that died,
  froze, hit a provider/compaction stall, shows a fatal message at the prompt,
  or parks its goal loop with `Goal blocked ... waiting_human`. Timer triggers
  are gated by pane context (Now/Next/Thought, scheduled wakes, running DAG
  waves and monitors) so active work is given time before declaring death.
  Recovery keeps the pane's shell alive, kills only the omo process tree,
  restarts omo with the previous thinking level, and submits a mass-ulw
  handoff prompt naming the predecessor's error, session file, and last
  intention. A companion reporter prints one progress summary per interval,
  because a watcher that only logs heartbeats goes silent in chat. Use when
  asked to babysit, watch, supervise, or auto-recover omo, or when a long omo
  run must survive provider stalls and crashes.
argument-hint: "[--pane ADDR] [--name NAME] [--project DIR] [--launch-pane ADDR=CMD]"
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
budget, thinking level, and restart command: a recovered target is relaunched
as `cd <its project> && omo --thinking <its footer level>`, so one watcher can
supervise panes from different projects. A custom `--launch` (or a per-pane
`--launch-pane ADDR=CMD`) applies only to panes the caller named with
`--pane`/`--name` and never leaks onto a dynamically discovered pane in another
project. Pane claims (`$XDG_RUNTIME_DIR/omo-watch/claims/<addr>.claim`, flock)
are shared across runtime roots: a second watcher logs
`watched by another omo-watch (pid N); skipping` and leaves the pane alone, so
start one watcher without `--pane`/`--launch` and it owns every omo on the
machine. Each target also claims a different session file while the project has
more than one; a same-project pair is still ambiguous when files run out, so
give each pane a stable `hc run --name` (or use different projects) if you need
the handoff to name the exact predecessor session.

## Detection

| Signal | Trigger |
|---|---|
| omo foreground gone, shell remains | `--absent-grace` seconds (default 30) |
| `status=working` with no progress | `--stall` seconds (default 900) |
| fatal provider/compaction text at the prompt | persists `--fatal-grace` seconds (default 300) |
| `Working (Ns` visible while status is not working | persists `--frozen-grace` seconds (default 600) |
| `Goal blocked: … waiting_human` in the footer | persists `--blocked-grace` seconds (default 600) |

Progress is the captured session JSONL's size/mtime plus CPU of the omo
process tree (streaming model or a tool build). The herdr turn number is
reported in the trigger evidence but is not a progress signal. TUI animation
alone must not count: root CPU below 2% and no log growth is not progress.

## Context gate

A fired timer does not recover immediately. The watcher reads the last 80 pane
lines, including `Now:`, `Next:`, `Thought:`, the footer, and the background
work panel, then decides whether to defer or recover:

- **defer** when the pane names a future wake (`Stall backstop ready …`,
  `goal continues in …`, `Cache-warm wait` with a wake source), shows active
  work (compaction, a running DAG wave or subagent, a `mon_` monitor, a CI/PR
  watch), or CPU/session progress happened within `--context-grace`
  (default 180s)
- **recover** when none of those hold

Each deferral is logged as
`DEFER <pane> <mode>: <reason> | now=…; next=…; recheck in Ns`; the timer is
re-checked after the named wake time or `--context-grace`. Every trigger mode
gets `--context-max-defers` deferrals (default 3), and a single deferral is
capped at `--context-max-wait` (default 1800s). A `Goal achieved` footer
always defers, because a finished session has nothing to hand off.

This is local reasoning over the TUI and session signals, not a model call: a
watchdog must keep working while the provider path it watches is stalled. The
intent lines, wake time, and active work are copied into the trigger evidence
and the handoff prompt, so the successor knows what the predecessor was doing.

## Known provider issues

### Sakura AI: compaction stalls

With `sakura` as the LLM provider (observed with `preview/GLM-5.3-Flash`),
context compaction often hangs without any provider events:

- `Compaction rejected: compaction generator failed: Summarization stream
  stalled: no provider events for 300000ms; treating the request as dead`
- `Provider stream start timed out after 300000ms`
- followed by `System operation aborted`, then another
  `Compacting context...` retry

The failure looks provider-side, not local. omo's stall backstop wakes the goal,
compaction retries, and the same 5-minute silence can repeat while the session
sits at high context (observed at ~76%, 766k tokens). The context gate sees
`Compacting context...` and `Cache-warm wait` and therefore defers; that is the
correct default for a transient provider hiccup, but it cannot fix a compaction
path that fails every time.

Operational guidance: once the same session logs a compaction stall twice,
prefer an explicit forced handoff (`--force --pane <addr>`) over waiting for
`--stall`. A fresh session starts well below the compaction threshold, and the
handoff prompt already carries the predecessor's session path so the successor
can read only the last todo and `git status/diff`. Recording the exact error
lines above in the handoff makes the successor avoid re-entering the same
compaction attempt.

## Recovery

1. Capture the pane tail, session path, last event, and recent error lines.
2. Verify the launch target: a `cd` path in `--launch` must exist, and for an
   absent omo the foreground is re-checked so an omo the operator just started
   is not killed. After the TUI returns, the new omo's cwd must match the launch
   `cd` target (or the target project); otherwise the handoff is aborted instead
   of being typed into a different workspace.
3. Write the evidence and prompt to
   `$XDG_RUNTIME_DIR/omo-watch/handoffs/handoff-*.md`.
4. SIGTERM then SIGKILL the foreground omo process tree. The pane's fish
   process is not a descendant and survives.
5. Wait for the shell and start the target's launch command: by default
   `cd <project> && omo --thinking <level>`, where the level comes from the
   footer in the pane tail, else the last level captured while that omo was
   alive, else plain `omo`. A custom `--launch` is used as-is for the panes
   named by `--pane`/`--name`; `--launch-pane ADDR=CMD` overrides one address.
   Wait for the TUI, and submit:

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

6. Verify the prompt is visible and the new turn is working. Recovery is
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
# notify regex="TRIGGER|DEFER|RECOVER|recover error"
python3 ~/.agents/skills/omo-watch/watch.py --poll 15 --stall 900 --blocked-grace 600
```

No `--pane` and no `--launch`: discovery follows every live omo, and each
recovery restarts in that pane's own project. Add `--pane "$pane"` only when a
terminal must be recreated after it disappears; a custom `--launch` belongs
with it.

Useful flags: `--name`, `--project`, `--launch`, `--launch-pane`, `--force`,
`--once`,
`--dry-run`, `--poll`, `--stall`, `--absent-grace`, `--fatal-grace`,
`--frozen-grace`, `--blocked-grace`, `--context-grace`,
`--context-max-wait`, `--context-max-defers`, `--busy-pct`,
`--max-recoveries`, `--ready-timeout`.

`--force` needs `--pane` or `--name` and touches only those targets (the
intersection when both are given); it never recovers every discovered omo.
Add `--once` for a one-shot forced handoff, otherwise the normal watch loop
continues after it. `--dry-run` writes the handoff and logs the launch it
would use without killing or sending.

## Periodic reporting

A watcher that only writes heartbeats to `watch.log` leaves the chat silent for
hours. The owning agent reports progress on a cadence, so run `report.py` as a
second background service next to the watcher:

```bash
# bash tool: name=omo-report, pty=false, ready log="REPORT", notify regex="REPORT "
python3 ~/.agents/skills/omo-watch/report.py --pane "$pane" --interval 600
```

Each interval it prints one `REPORT` line: herdr state and pid, footer context
and effort, session JSONL growth since the previous report, running DAG wave,
active item and age, goal state, `Now:`/`Next:` intent, and the watcher's last
log line. The notify regex delivers that line to the agent, which posts a short
chat summary; `--once` prints a single snapshot. Pass `--runtime` when the
watcher uses an `OMO_WATCH_RUNTIME` other than the default so `watch=` reads the
right log.

Report immediately on `TRIGGER`, `DEFER`, and `RECOVER`, and keep the interval
at or below `--stall` (900s) so a stall is visible in chat before recovery
fires.

## Operate

- State root: `$XDG_RUNTIME_DIR/omo-watch` (`OMO_WATCH_RUNTIME` overrides
  it). It must be owned by your uid; the watcher refuses to start otherwise.
- `hc` is resolved from `PATH`; `OMO_WATCH_HC` pins an explicit binary.
- Locks: `lock` for a real run, `lock-dry` for `--dry-run`, so a rehearsal
  never blocks the service (or vice versa). The lock file records the pid.
- Claims: `.../omo-watch/claims/<addr>.claim` is flocked per pane and lives
  outside `OMO_WATCH_RUNTIME`, so split runtime roots still cannot
  double-recover one terminal.
- Log: `.../watch.log` (heartbeat every 10 minutes).
- Pause recovery but keep polling: `touch .../paused`; remove the file to
  resume. Every target is re-armed on resume, so a long pause cannot look
  like a stall or a crash.
- Force a handoff now: `--force --pane <addr>` or `--force --name <name>`
  (omit `--dry-run` to act).
- The service dies with the owning omp session. That is deliberate: the
  watcher is the agent's job, not a machine-wide daemon. Restart it from the
  skill when a new session takes over.
