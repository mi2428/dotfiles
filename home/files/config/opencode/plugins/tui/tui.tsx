/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui";
import type { Context } from "@opencode/plugin/tui/context";
import type { ScrollBoxRenderable } from "@opentui/core";
import { For, Show, createEffect, createMemo, createSignal, onCleanup } from "solid-js";
import { buildTodoView, type TodoItem, type TodoLine } from "./lib/todo-overlay";

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

function TodoOverlay(props: { context: Context }) {
  const context = props.context;
  const [columns, setColumns] = createSignal(context.renderer.width);
  const [recent, setRecent] = createSignal<{ sessionID: string; messageID?: string; todos: TodoItem[] }>();
  const started = new Map<string, string>();
  let generation = 0;
  const resize = () => setColumns(context.renderer.width);
  context.renderer.on("resize", resize);
  const sessionID = createMemo(() => {
    const route = context.ui.router.current();
    return route.type === "session" ? route.sessionID : undefined;
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
  onCleanup(() => { generation++; stopStarted(); stopSuccess(); stopFailed(); stopRevert(); context.renderer.off("resize", resize); });
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
  let scrollbox: ScrollBoxRenderable | undefined;
  let scrolled = "";
  createEffect(() => {
    const current = view();
    const key = `${sessionID()}:${current?.completed}:${current?.windowStart}`;
    if (!current) { scrolled = ""; return; }
    if (key === scrolled) return;
    scrolled = key;
    void context.renderer.idle().then(() => {
      if (!scrollbox || scrollbox.isDestroyed) return;
      const start = scrollbox.content?.findDescendantById(`todo-line-${current.windowStart}`);
      if (start && scrollbox.content) scrollbox.scrollTop = Math.max(0, start.y - scrollbox.content.y);
    });
  });
  return (
    <Show when={view()}>
      {(current) => (
        <box id="todo-panel" position="absolute" top={0} right={PANEL_MARGIN} width={width()} zIndex={900}
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
    return context.ui.slot({ append: "app", render: () => <TodoOverlay context={context} /> });
  },
});
