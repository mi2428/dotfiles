/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui";
import type { Context } from "@opencode/plugin/tui/context";
import { Show, createEffect, createMemo, createSignal, onCleanup } from "solid-js";
import { HudStack } from "./hud/layout";
import { TodoHud } from "./hud/todo";
import { closeViewer, createAdapter, createViews, nameTabs, run, type View } from "./lib/herdr-views";

function GitStatus(props: { context: Context }) {
  const context = props.context;
  const [counts, setCounts] = createSignal<{ additions: number; deletions: number }>();
  const [failed, setFailed] = createSignal(false);
  const directory = createMemo(() => {
    const route = context.ui.router.current();
    const location = route.type === "session" ? context.data.session.get(route.sessionID)?.location
      : context.location ?? context.data.location.default();
    return location && context.data.location.vcs.info(location)?.provider === "git" ? location.directory : undefined;
  });
  createEffect(() => {
    const cwd = directory();
    setCounts(undefined);
    setFailed(false);
    if (!cwd) return;
    let disposed = false;
    let reading = false;
    const refresh = async () => {
      if (reading) return;
      reading = true;
      try {
        const { data } = await context.client.vcs.status({ location: { directory: cwd } });
        const next = data.reduce((total, file) => ({
          additions: total.additions + file.additions, deletions: total.deletions + file.deletions,
        }), { additions: 0, deletions: 0 });
        if (!disposed) { setCounts(next); setFailed(false); }
      } catch (error) {
        if (!disposed) {
          console.error("Could not read Git status", error);
          setCounts(undefined);
          setFailed(true);
        }
      } finally { reading = false; }
    };
    void refresh();
    const timer = setInterval(refresh, 3000);
    onCleanup(() => { disposed = true; clearInterval(timer); });
  });
  const dirty = () => {
    const current = counts();
    return current && (current.additions > 0 || current.deletions > 0);
  };
  return <>
    <Show when={failed()}><text fg={context.theme.text.feedback.error.base}>Git !</text></Show>
    <Show when={dirty()}>
      <text id="git-status" wrapMode="none" flexShrink={0} fg={context.theme.text.muted}>
        <span style={{ fg: context.theme.diff.text.added }}>{`+${counts()!.additions}`}</span>
        {" "}
        <span style={{ fg: context.theme.diff.text.removed }}>{`-${counts()!.deletions}`}</span>
      </text>
    </Show>
  </>;
}

function ViewerStatus(props: { context: Context; sessionID: string }) {
  const context = props.context;
  const [now, setNow] = createSignal(Date.now());
  const [received, setReceived] = createSignal<number>();
  const timer = setInterval(() => setNow(Date.now()), 1000);
  const stop = context.data.listen(({ details }) => {
    if (/^session\.(execution|step|text|reasoning|tool|retry|compaction)\./.test(details.type)
      && "sessionID" in details.data && details.data.sessionID === props.sessionID) setReceived(Date.now());
  });
  onCleanup(() => { clearInterval(timer); stop(); });
  const session = createMemo(() => context.data.session.get(props.sessionID));
  const running = createMemo(() => context.data.session.status(props.sessionID) === "running");
  const started = createMemo(() => {
    const time = session()?.time;
    // The server publishes this field, but the generated client types omit it.
    if (!time || !("busy" in time)) return undefined;
    if (typeof time.busy !== "number" || !Number.isFinite(time.busy)) throw new Error("Invalid session execution timestamp");
    return time.busy;
  });
  const state = createMemo(() => {
    if (running()) {
      if (context.data.session.permission.list(props.sessionID)?.length) return "WAITING FOR APPROVAL";
      if (context.data.session.form.list(props.sessionID)?.length) return "WAITING FOR ANSWER";
      return "RUNNING";
    }
    const outcome = session()?.outcome;
    return outcome ? { succeeded: "DONE", failed: "FAILED", interrupted: "INTERRUPTED" }[outcome] : "IDLE";
  });
  const color = () => state() === "FAILED" ? context.theme.text.feedback.error.base
    : state().startsWith("WAITING") || state() === "INTERRUPTED" ? context.theme.text.feedback.warning.base
    : state() === "IDLE" ? context.theme.text.muted : context.theme.text.feedback.success.base;
  const tools = createMemo(() => {
    const start = started();
    if (!running() || start === undefined) return [];
    return context.data.session.message.list(props.sessionID).flatMap((message) => message.type === "assistant"
      ? message.content.filter((part) => part.type === "tool") : [])
      .filter((part) => part.time.created >= start && (part.state.status === "running" || part.state.status === "streaming"));
  });
  const model = () => {
    const current = session();
    const ref = current?.model;
    return ref ? context.data.location.model.list(current!.location)
      ?.find((item) => item.providerID === ref.providerID && item.id === ref.id)?.name ?? ref.id : "--";
  };
  const provider = () => {
    const current = session();
    const ref = current?.model;
    return ref ? context.data.location.provider.list(current!.location)
      ?.find((item) => item.id === ref.providerID)?.name ?? ref.providerID : "--";
  };
  const elapsed = () => {
    const start = started();
    const end = running() ? now() : session()?.time.idle;
    if (start === undefined || end === undefined || end < start) return "--";
    const seconds = Math.floor((end - start) / 1000);
    return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  };
  const activity = () => received() === undefined ? "-" : `${Math.max(0, Math.floor((now() - received()!) / 1000))}s ago`;
  return <Show when={session()?.parentID}>
    {/* Use the session's bottom padding for this row, keeping the normal footer gap below it. */}
    <box id="viewer-status" height={1} flexShrink={0} paddingLeft={2} paddingRight={2}
      marginTop={-1} marginBottom={1} flexDirection="row" justifyContent="space-between" gap={2}
      backgroundColor={context.theme.background.base}>
      <text id="viewer-identity" flexShrink={1} minWidth={0} wrapMode="none" truncate fg={context.theme.text.base}>
        {`${model()} ${provider()}  Elapsed ${elapsed()}`}
      </text>
      <text id="viewer-metrics" flexShrink={0} minWidth={0} maxWidth="65%" wrapMode="none" truncate fg={context.theme.text.muted}>
        <span style={{ fg: color() }}><b>{state()}</b></span>
        <span style={{ fg: context.theme.hue.accent[200] }}>{`  ${session()?.agent ?? "--"}`}</span>
        {`  Tool ${tools().at(-1)?.name ?? "-"}${tools().length > 1 ? ` (+${tools().length - 1})` : ""}  Last activity ${activity()}`}
      </text>
    </box>
  </Show>;
}

export default Plugin.define({
  id: "opencode-todo-overlay.tui",
  setup(context) {
    const cleanups = [context.ui.slot({ append: "app", render: () => (
      <HudStack context={context}>{(layout) => <TodoHud context={context} />}</HudStack>
    ) })];
    const inHerdr = process.env.HERDR_ENV === "1" || !!process.env.HC_TERMINAL_ID;
    const viewer = process.env.OPENCODE_HERDR_VIEWER === "1";
    // Labels are presentation only: Slim owns its pane manager but shares this footer.
    // Keep the host's editor context and interrupt confirmation intact.
    if (inHerdr && !viewer) {
      for (const slot of ["prompt.footer.status", "home.footer.status"] as const) {
        cleanups.push(context.ui.slot({ append: slot, render: () => (
          <box flexDirection="row" gap={2} flexShrink={0}>
            <text fg={context.theme.hue.accent[200]} wrapMode="none" flexShrink={0}><b>Main</b></text>
            <GitStatus context={context} />
          </box>
        ) }));
      }
    }
    if (inHerdr && context.options?.herdrViews !== false) {
      if (!viewer) {
        // Browsing a native child hides the prompt/footer, but this remains the human-facing window.
        cleanups.push(context.ui.slot({ append: "app", render: () => {
          const child = createMemo(() => {
            const route = context.ui.router.current();
            return route.type === "session" && context.data.session.get(route.sessionID)?.parentID;
          });
          return <Show when={child()}>
            <box position="absolute" bottom={0} right={2} zIndex={901}
              backgroundColor={context.theme.background.raised.base} paddingLeft={1} paddingRight={1}>
              <text fg={context.theme.hue.accent[200]}><b>Main</b></text>
            </box>
          </Show>;
        } }));
      }
      if (viewer) {
        const sessionID = process.env.OPENCODE_HERDR_SESSION;
        if (!sessionID) throw new Error("Herdr viewer session is missing");
        const active = () => {
          const route = context.ui.router.current();
          return route.type === "session" && route.sessionID === sessionID
            && !!context.data.session.get(sessionID)?.parentID;
        };
        let pending = false;
        // Stop or close this viewer even when a dialog or form owns input.
        context.keymap.layer(() => ({
          mode: "global", priority: 10, enabled: active,
          commands: [
            { bind: "ctrl+c", title: "Stop subagent or close viewer", run: async () => {
              if (pending || !active()) return;
              pending = true;
              const running = context.data.session.status(sessionID) === "running";
              try {
                if (running) await context.client.session.interrupt({ sessionID });
                else await closeViewer(process.env, () => active() && context.data.session.status(sessionID) === "idle");
              }
              catch (error) {
                context.ui.toast.show({ message: `Could not ${running ? "interrupt subagent" : "close viewer"}: ${String(error)}`, variant: "error" });
              }
              finally { pending = false; }
            } },
            { bind: "escape", run: () => {} },
          ],
        }));
        for (const mode of ["base", "modal"]) {
          context.keymap.layer(() => ({
            mode, priority: 10, enabled: active,
            commands: mode === "modal"
              ? [{ bind: "ctrl+g", title: "Close dialog", run: () => context.ui.dialog.clear() }]
              : [{ id: "session.parent", title: "Parent navigation disabled", run: () => {} }],
          }));
        }
        cleanups.push(context.ui.slot({ after: "app", render: () => (
          <Show when={active()}><ViewerStatus context={context} sessionID={sessionID} /></Show>
        ) }));
        // Navigating away releases the view so reconnecting parents do not reuse a person's tab.
        cleanups.push(context.ui.slot({ append: "app", render: () => {
          const [released, setReleased] = createSignal(false);
          let selected = false;
          createEffect(() => {
            const route = context.ui.router.current();
            if (route.type === "session" && route.sessionID === process.env.OPENCODE_HERDR_SESSION) { selected = true; return; }
            if (released() || !selected) return;
            setReleased(true);
            const release = process.env.HC_TERMINAL_ID
              ? run("hc", ["label", process.env.HC_TERMINAL_ID, "oc2.view="])
              : run("herdr", ["pane", "report-metadata", process.env.HERDR_PANE_ID!,
                "--source", "dotfiles.oc2-views", "--clear-token", "oc2_view"]);
            void release.catch(() => console.error("Could not release Herdr viewer ownership"));
          });
          return <Show when={released()}>
            <box position="absolute" bottom={0} right={2} zIndex={901}
              backgroundColor={context.theme.background.raised.base} paddingLeft={1} paddingRight={1}>
              <text fg={context.theme.text.feedback.info.base}>Viewer</text>
            </box>
          </Show>;
        } }));
      }
      if (!viewer) {
        let warned = false;
        const warn = (message: string) => {
          console.error(message);
          if (!warned) context.ui.toast.show({ message, variant: "warning" });
          warned = true;
        };
        void nameTabs(process.env).catch(() => warn("Herdr のタブ名を更新できませんでした。子の実行は継続します。"));
        if (process.argv.some((arg) => arg === "--standalone" || arg === "--server" || arg.startsWith("--server="))) {
          warn("子の可視画面は共有サービス起動時に利用できます。子の実行は継続します。");
        } else {
          try {
            const adapter = createAdapter(process.env);
            if (adapter) {
              const [registry, updateRegistry] = context.storage.memory<{ views: Record<string, View | null> }>("herdr-views", {
                initial: { views: {} },
              });
              const views = createViews({ adapter, warn,
                registry: {
                  has: (id) => Object.hasOwn(registry.views, id),
                  set: (id, view) => updateRegistry((draft) => { draft.views[id] = view; }),
                },
                current: () => {
                  const route = context.ui.router.current();
                  return route.type === "session" ? route.sessionID : undefined;
                },
                get: (sessionID) => context.client.session.get({ sessionID }),
              });
              for (const type of ["session.created", "session.execution.started"] as const) {
                cleanups.push(context.data.on(type, (event) => { void views.show(event.data.sessionID); }));
              }
              cleanups.push(context.data.on("session.deleted", (event) => { void views.remove(event.data.sessionID); }));
              // Reattach running descendants after opening an existing parent or reconnecting.
              cleanups.push(context.ui.slot({ append: "app", render: () => {
                createEffect(() => {
                  const route = context.ui.router.current();
                  if (route.type !== "session") return;
                  for (const session of context.data.session.list()) {
                    if (session.parentID && context.data.session.status(session.id) === "running") void views.show(session.id);
                  }
                });
                return null;
              } }));
              cleanups.push(() => { void views.dispose(); });
            }
          } catch { warn("Herdr の端末識別を確認できません。子の実行は継続します。"); }
        }
      }
    }
    return () => { for (const cleanup of cleanups.toReversed()) cleanup(); };
  },
});
