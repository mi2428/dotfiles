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
  intention. The skill also documents a periodic progress reporter (bash +
  hc + jq) so the agent can summarize what is moving in chat, because a
  watcher that only logs heartbeats goes silent. For an operator who is away
  it also defines a viewport-based approval proxy: detect `Permission
  required:`, press `Allow once` only while the `→` selection is on it, and
  hold anything that touches another session. Use when asked to babysit,
  watch, supervise, or auto-recover omo, or when a long omo run must survive
  provider stalls and crashes.
argument-hint: "[--pane ADDR] [--name NAME] [--project DIR] [--launch-pane ADDR=CMD]"
---

# omo-watch

The watcher is a skill, not a system daemon. Run it from this agent as an omp
background service (or a foreground shell) so it lives with the session that
owns it. Runtime state and logs go under `$XDG_RUNTIME_DIR/omo-watch`; nothing
is installed into `~/.local` or systemd.

## Fast path: arm first, analyze later

Arm detection in about 90 seconds. Everything the first live event can teach
you is learned there, not here.

1. Resolve the pane. Filter `hc ls --json` by the herdr space (`.where` prefix
   plus the app name; see Field shapes) and keep the address.
2. Operator away? Start the approval detector as a second service: read the
   viewport every ~5s, notify on `Permission required:` + `Allow once`, one
   notify per dialog hash (see Approval proxy).
3. Start the recovery watcher with `--pane <addr> --project <dir>`, and a
   runtime root of its own when the default lock is busy (see Run it).

Before step 3 is running, do not read omo's bundle or permission-system
source, inspect `settings.json` or preset names, enumerate `herdr
workspace`/`herdr tab`, read session JSONL or shell history, or run
`--once --dry-run` (that only debugs `watch.py`). The screen is the contract:
the first real dialog defines its own layout, and the detection strings above
are all the watcher needs.

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

## Field shapes (do not rediscover)

`hc ls --json` and `hc get <addr> --json` do not share a shape, and getting
this wrong costs a watcher restart:

- `hc ls --json`: `.status` is a string (`"working"`), `.agent` names the app,
  `.where` is `"<space> / <tab>"`, `.labels["herdr.space"]` is the space id.
- `hc get <addr> --json`: `.status` is `{"app":"omo","state":"working"}`,
  `.foreground.pid` and `.foreground.cwd` are the live process.
- A space filter is a `.where` prefix match. Never enumerate `herdr workspace`
  or `herdr tab` to find a monitored pane.

## Detection

| Signal | Trigger |
|---|---|
| omo foreground gone, shell remains | `--absent-grace` seconds (default 30) |
| `status=working` with no progress | `--stall` seconds (default 900) |
| fatal provider/compaction text at the prompt | persists `--fatal-grace` seconds (default 300) |
| `Working (Ns` visible while status is not working | persists `--frozen-grace` seconds (default 600) |
| `Goal blocked: … waiting_human` in the footer | persists `--blocked-grace` seconds (default 600) |

A visible `Permission required:` dialog is user-wait, not a death signal:
timers must not count it as a stall, and recovery must never touch it.

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
  watch), shows a `Permission required:` dialog (a human wait, never a
  recovery), or CPU/session progress happened within `--context-grace`
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

## Approval proxy (operator away)

When the operator leaves and asks for approvals to be proxied, run a second
background service next to the recovery watcher. It is a string detector, not
a model: poll the **viewport** (`hc read <addr>` without `--lines`; history
still holds dialogs that were already answered) every ~5s and emit one notify
line when the text contains both `Permission required:` and `Allow once`. Hash
the dialog block so one dialog notifies once, and reset the hash when those
strings disappear.

The dialog is a TUI select: title `Permission required: <permission>`, body
`Description:` / `Command:` / `File:` / `Path:` / `Directory:`, options in
order `Allow once`, `Allow always`, [`Allow <tool> on <origin> always in this
project`], `Deny`, `Deny with feedback`. The selected row is prefixed `→ `,
and the default selection is `Allow once`, so approval is one `enter`.

Invariants:

- Read the dialog before pressing anything. Press `enter` only while the
  viewport shows `→ Allow once`; re-read after the keypress.
- Reply per request, not per notification: a second dialog after a fast
  answer is a new hash.
- Approval never substitutes for recovery. A dialog is a human wait; if the
  operator is unreachable, report it instead of guessing.

Standing policy unless the operator overrides:

| Request | Action |
|---|---|
| `read`/`list`/`glob`/`grep`, `websearch`/`codesearch` | `Allow once` |
| `edit`/`bash` inside the watched project or its `/tmp` workdir | `Allow once` |
| read-only device probes (ssh, EDID, ddcutil, package metadata) | `Allow once` |
| any other pane or process (`hc`, `herdr`, `kill`, `pkill`) | hold and report |
| another project's worktree, another session's `~/.omo` data, global config or services | hold and report |

The default permission preset is `full-access`, so a healthy session usually
shows no dialog at all. Do not audit the preset or read omo's permission
source to predict prompts; the screen is the contract.

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

### Adoption guard

If the foreground pid and session file change without a `TRIGGER`/`RECOVER`
line, the pane was restarted by something else (herdr keep, `hc run`, or the
operator typing `omo`). Adopt the new session and do not hand off. Before any
forced handoff, check `hc get` status/turn and the new session's first user
message: a fresh session that already has user input or is running belongs to
the operator, not to a corpse.

## Run it

Dry run only while changing `watch.py`: it rehearses recovery, and is not a
prerequisite for watching.

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

One watcher per runtime root: the default root's `lock` is single-owner. When
another pane's watcher already holds it, give this pane its own root
(`OMO_WATCH_RUNTIME=$XDG_RUNTIME_DIR/omo-watch-<addr>`); claims stay shared in
`.../omo-watch/claims`, so the split cannot double-recover a pane.

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
hours. The owning agent reports progress, but the notification layer disables
`notify` for a job that matches too often — so emit on change and cap the
cadence instead of printing unconditionally every 10 minutes. Run this snippet
as a second background service:

```bash
# bash tool: name=omo-report, pty=false, ready log="REPORT ", notify regex="REPORT "
addr=<pane address>
sess_dir=~/.omo/agent/sessions/--<project path with / as ->--
prev_size= last_emit=0 last_sig=
FLOOR=300        # seconds between transition-driven reports
ACTIVE_GAP=1200  # progress summary while the session grows
IDLE_GAP=3600    # liveness line when nothing changes
while :; do
  now=$(date +%s)
  st=$(hc get "$addr" --json | jq -r 'if (.status|type)=="string" then .status else (.status.state // "?") end')
  tail=$(hc read "$addr" --lines 40)
  ctx=$(printf '%s\n' "$tail" | grep -oE '[0-9]+K/1M \([0-9.]+%\)' | tail -1)
  dag=$(printf '%s\n' "$tail" | grep -oE '[0-9]+/[0-9]+ done, *[0-9]+ running' | tail -1)
  act=$(printf '%s\n' "$tail" | grep -E '^ *▶ ' | tail -1 | sed -E 's/^ *▶ ([^ ]+).*/\1/')
  goal=$(printf '%s\n' "$tail" | grep -oE 'goal continues in [0-9]+m? ?[0-9]*s?' | tail -1)
  sess=$(stat -c %s "$(ls -t "$sess_dir"/*.jsonl | head -1)")
  grow=0; [ -n "$prev_size" ] && grow=$((sess - prev_size)); prev_size=$sess
  sig="$st|$dag|$act"; emit=0
  if [ "$sig" != "$last_sig" ] && [ $((now - last_emit)) -ge $FLOOR ]; then emit=1; fi
  if [ "$grow" -ne 0 ] && [ $((now - last_emit)) -ge $ACTIVE_GAP ]; then emit=1; fi
  if [ $((now - last_emit)) -ge $IDLE_GAP ]; then emit=1; fi
  if [ $emit -eq 1 ]; then
    printf 'REPORT %s | state=%s | ctx=%s | dag=%s | active=%s | %s | session=%+dB\n' \
      "$(date +%H:%M)" "$st" "$ctx" "$dag" "$act" "$goal" "$grow"
    last_emit=$now; last_sig=$sig
  fi
  sleep 60
done
```

Each line is delivered by the notify regex; post a short chat summary from it,
adding `Now:`/`Next:` or the watcher's last log line when they matter. Report
`TRIGGER`/`DEFER`/`RECOVER` immediately instead of waiting for the next tick,
and keep the progress gap at or below `--stall` (900s) so a stall is visible in
chat while it matters. Bash + `hc` + `jq` are enough: the pane text and
`hc get --json` are the whole interface, so extra fields or filters stay a
one-line edit.

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
- No test suite ships with the skill: after changing `watch.py`, verify with
  `--once --dry-run` plus a live `--once` probe instead of unit tests.
- The service dies with the owning omp session. That is deliberate: the
  watcher is the agent's job, not a machine-wide daemon. Restart it from the
  skill when a new session takes over.
