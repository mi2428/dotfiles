/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui";
import type { Context } from "@opencode/plugin/tui/context";
import type { ScrollBoxRenderable } from "@opentui/core";
import { For, Show, createEffect, createMemo, createSignal, onCleanup } from "solid-js";
import { buildTodoView, type TodoItem, type TodoLine } from "./lib/todo-overlay";
import { closeViewer, createAdapter, createViews, nameTabs, run, type View } from "./lib/herdr-views";

export const MAX_PANEL_WIDTH = 94;
export const MAX_BODY_HEIGHT = 12;
const PANEL_MARGIN = 2;
const BORDER_CHARS = {
  topLeft: "", bottomLeft: "", vertical: "┃", topRight: "", bottomRight: "",
  horizontal: " ", bottomT: "", topT: "", cross: "", leftT: "", rightT: "",
};

export function popupWidth(columns: number): number {
  const width = Number.isFinite(columns) ? Math.max(1, Math.floor(columns)) : MAX_PANEL_WIDTH;
  return Math.min(MAX_PANEL_WIDTH, Math.max(1, width - PANEL_MARGIN * 2), Math.max(36, Math.floor(width * 0.85)));
}

type Messages = ReturnType<Context["data"]["session"]["message"]["list"]>;
type TodoSnapshot = { messageID: string; todos: TodoItem[] };
type ScrollMemory = { offsets: Record<string, { windowKey: string; scrollTop: number }> };

function parseTodos(input: unknown): TodoItem[] | undefined {
  if (!Array.isArray(input)) return;
  if (!input.every((todo) => todo && typeof todo === "object" && !Array.isArray(todo)
    && typeof todo.content === "string" && ["pending", "in_progress", "completed", "cancelled"].includes(todo.status))) return;
  return input as TodoItem[];
}

export function latestTodos(messages: Messages, boundary?: string): TodoSnapshot | undefined {
  for (const message of messages.toReversed()) {
    if (message.type !== "assistant" || (boundary && message.id >= boundary)) continue;
    for (const part of message.content.toReversed()) {
      if (part.type !== "tool" || part.name !== "todowrite" || part.state.status !== "completed") continue;
      const input = parseTodos(part.state.input.todos);
      if (input === undefined) throw new Error("Malformed todowrite input");
      return { messageID: message.id, todos: input };
    }
  }
}

// The TUI cache initially loads only 20 messages; search older assistant pages on demand.
export async function recoverTodos(client: Context["client"], sessionID: string, boundary?: string): Promise<TodoSnapshot | undefined> {
  let cursor: string | undefined;
  do {
    const page = await client.message.list({ sessionID, type: "assistant", limit: 100,
      ...(cursor ? { cursor } : { order: "desc" }),
    });
    const todos = latestTodos(page.data.toReversed(), boundary);
    if (todos !== undefined) return todos;
    if (page.cursor.next && page.cursor.next === cursor) throw new Error("Todo history cursor did not advance");
    cursor = page.cursor.next ?? undefined;
  } while (cursor);
  return undefined;
}

function lineColor(line: TodoLine, context: Context) {
  if (line.kind === "in_progress") return context.theme.text.feedback.success.base;
  if (line.kind === "pending") return context.theme.text.feedback.warning.base;
  return context.theme.text.muted;
}

export function bodyHeight(lines: readonly TodoLine[], start: number, end: number, width: number): number {
  let rows = 0;
  const available = Math.max(1, width - 6);
  for (const line of lines.slice(start, end + 1)) {
    let columns = 0;
    rows++;
    for (const { segment } of new Intl.Segmenter().segment(line.text)) {
      const size = Bun.stringWidth(segment);
      if (columns > 0 && columns + size > available) {
        rows++;
        columns = 0;
      }
      columns += size;
    }
    if (rows >= MAX_BODY_HEIGHT) return MAX_BODY_HEIGHT;
  }
  return Math.max(1, rows);
}

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

function TodoOverlay(props: { context: Context }) {
  const context = props.context;
  const [columns, setColumns] = createSignal(context.renderer.width);
  const [recent, setRecent] = createSignal<{ sessionID: string; messageID?: string; todos: TodoItem[] }>();
  const [scrollMemory, updateScrollMemory] = context.storage.memory<ScrollMemory>("scroll-offsets", {
    initial: { offsets: {} },
  });
  const started = new Map<string, string>();
  let scrollbox: ScrollBoxRenderable | undefined;
  let scrolled = "";
  let generation = 0;
  const rememberScroll = (id: string | undefined) => {
    if (!id || !scrolled || !scrollbox || scrollbox.isDestroyed) return;
    const value = { windowKey: scrolled, scrollTop: scrollbox.scrollTop };
    updateScrollMemory((draft) => { draft.offsets[id] = value; });
  };
  const resize = () => setColumns(context.renderer.width);
  context.renderer.on("resize", resize);
  const sessionID = createMemo<string | undefined>((previous) => {
    const route = context.ui.router.current();
    const id = route.type === "session" ? route.sessionID : undefined;
    if (previous !== id) rememberScroll(previous);
    return id;
  });
  const restore = (id: string) => {
    const current = ++generation;
    setRecent(undefined);
    void (async () => {
      await context.data.session.message.sync(id);
      const boundary = context.data.session.get(id)?.revert?.messageID;
      const snapshot = latestTodos(context.data.session.message.list(id), boundary)
        ?? await recoverTodos(context.client, id, boundary);
      if (current === generation) setRecent({ sessionID: id, messageID: snapshot?.messageID, todos: snapshot?.todos ?? [] });
    })().catch((error) => console.error("Failed to restore Todo HUD", error));
  };
  const toolKey = (id: string, messageID: string, toolID: string) => `${id}:${messageID}:${toolID}`;
  const stopStarted = context.data.on("session.tool.input.started", (event) => {
    if (event.data.sessionID === sessionID())
      started.set(toolKey(event.data.sessionID, event.data.assistantMessageID, event.data.id), event.data.name);
  });
  const stopSuccess = context.data.on("session.tool.success", (event) => {
    const { sessionID: id, assistantMessageID: messageID, id: toolID } = event.data;
    if (id !== sessionID()) return;
    const key = toolKey(id, messageID, toolID);
    const name = started.get(key);
    started.delete(key);
    if (name && name !== "todowrite") return;
    const known = name === "todowrite";
    const todos = known ? parseTodos(event.data.metadata?.todos) : undefined;
    const current = known ? ++generation : generation;
    if (todos !== undefined) {
      setRecent({ sessionID: id, messageID, todos });
      return;
    }
    // Metadata is optional in the public event type. Verify the exact tool before accepting its input.
    void (async () => {
      context.data.session.message.invalidate(id);
      await context.data.session.message.sync(id);
      const cached = context.data.session.message.get(id, messageID);
      const match = cached?.type === "assistant" && cached.content.some(
        (item) => item.type === "tool" && item.id === toolID && item.state.status === "completed",
      );
      const message = match ? cached : await context.client.session.message.get({ sessionID: id, messageID });
      if (message.type !== "assistant") return;
      const part = message.content.find((item) => item.type === "tool" && item.id === toolID);
      if (part?.type !== "tool" || part.name !== "todowrite" || part.state.status !== "completed") {
        if (known) throw new Error("Completed todowrite result not found");
        return;
      }
      const fallback = parseTodos(part.state.input.todos);
      if (fallback === undefined) throw new Error("Malformed todowrite input");
      if (current === generation) {
        generation++;
        setRecent({ sessionID: id, messageID, todos: fallback });
      }
    })().catch((error) => console.error("Failed to refresh Todo HUD", error));
  });
  const stopFailed = context.data.on("session.tool.failed", (event) => {
    started.delete(toolKey(event.data.sessionID, event.data.assistantMessageID, event.data.id));
  });
  const stopRevert = context.data.on("session.revert.committed", (event) => {
    if (event.data.sessionID !== sessionID()) return;
    context.data.session.message.invalidate(event.data.sessionID);
    restore(event.data.sessionID);
  });
  onCleanup(() => {
    rememberScroll(sessionID());
    generation++;
    stopStarted();
    stopSuccess();
    stopFailed();
    stopRevert();
    context.renderer.off("resize", resize);
  });
  createEffect(() => {
    const id = sessionID();
    started.clear();
    if (id) restore(id);
    else { generation++; setRecent(undefined); }
  });
  const view = createMemo(() => {
    const id = sessionID();
    if (!id) return null;
    const boundary = context.data.session.get(id)?.revert?.messageID;
    const snapshot = recent();
    const live = snapshot?.sessionID === id && (!boundary || !snapshot.messageID || snapshot.messageID < boundary)
      ? snapshot.todos : undefined;
    return buildTodoView(live ?? latestTodos(context.data.session.message.list(id), boundary)?.todos);
  });
  const width = createMemo(() => popupWidth(columns()));
  const visible = createMemo(() => columns() >= 80);
  createEffect(() => {
    if (!visible()) return;
    const id = sessionID();
    const current = view();
    const key = `${id}:${current?.completed}:${current?.windowStart}`;
    if (!current) { scrolled = ""; return; }
    if (key === scrolled) return;
    scrolled = key;
    void context.renderer.idle().then(() => {
      if (!id || !scrollbox || scrollbox.isDestroyed || sessionID() !== id) return;
      const remembered = scrollMemory.offsets[id];
      if (remembered?.windowKey === key) {
        scrollbox.scrollTop = remembered.scrollTop;
        return;
      }
      const start = scrollbox.content?.findDescendantById(`todo-line-${current.windowStart}`);
      if (start && scrollbox.content) scrollbox.scrollTop = Math.max(0, start.y - scrollbox.content.y);
    });
  });
  return (
    <Show when={view()}>
      {(current) => (
        <box id="todo-panel" visible={visible()} position="absolute" top={0} right={PANEL_MARGIN} width={width()} zIndex={900}
          flexDirection="column" backgroundColor={context.theme.background.raised.base}
          border={["left", "right"]} borderColor={context.theme.text.feedback.info.base}
          customBorderChars={BORDER_CHARS} paddingLeft={2} paddingRight={2} paddingBottom={1}>
          <box alignSelf="flex-start" flexDirection="row" backgroundColor={context.theme.text.feedback.info.base}
            paddingLeft={1} paddingRight={1} marginBottom={1}>
            <text fg={context.theme.background.raised.base} wrapMode="none" truncate>
              {`Todo · ${current().completed + Number(current().lines.some((line) => line.kind === "in_progress"))} of ${current().total}`}
            </text>
          </box>
          <scrollbox id="todo-scroll" ref={(node) => { scrollbox = node; }} width="100%" height={bodyHeight(current().lines, current().windowStart, current().windowEnd, width())}
            scrollX={false} scrollY={true} viewportCulling={true}
            verticalScrollbarOptions={{ visible: false, showArrows: false, width: 0 }}
            contentOptions={{ flexDirection: "column" }}>
            <For each={current().lines}>{(line, index) =>
              <text id={`todo-line-${index()}`} fg={lineColor(line, context)} width="100%" wrapMode="char">{line.text}</text>
            }</For>
          </scrollbox>
        </box>
      )}
    </Show>
  );
}

export default Plugin.define({
  id: "opencode-todo-overlay.tui",
  setup(context) {
    const cleanups = [context.ui.slot({ append: "app", render: () => <TodoOverlay context={context} /> })];
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
