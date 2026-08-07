import type { TuiPlugin, TuiRouteCurrent } from "@opencode-ai/plugin/tui";
import { buildTodoView, type TodoLine, type TodoItem } from "./lib/todo-overlay";

type Theme = {
  backgroundPanel: unknown;
  borderSubtle: unknown;
  info: unknown;
  primary: unknown;
  selectedListItemText: unknown;
  success: unknown;
  warning: unknown;
  text: unknown;
  textMuted: unknown;
};

type RenderNode = {
  kind: "box" | "scrollbox" | "text";
  props: Record<string, unknown>;
  text?: string;
  children?: RenderNode[];
  scrollWindow?: {
    startID: string;
    endID: string;
    key: string;
  };
};

type RenderableAdapter = {
  y: number;
  height: number;
};

type ScrollBoxAdapter = {
  scrollTop: number;
  height: number;
  isDestroyed?: boolean;
  content?: RenderableAdapter & {
    findDescendantById: (id: string) => RenderableAdapter | undefined;
  };
};

type TextNodeAdapter = {
  children?: Array<string | TextNodeAdapter>;
  bg?: unknown;
  fg?: unknown;
};

type RenderTreeAdapter = {
  getChildren?: () => RenderTreeAdapter[];
  getTextChildren?: () => TextNodeAdapter[];
};

export const MAX_PANEL_WIDTH = 94;
export const MIN_PANEL_WIDTH = 36;
export const MAX_BODY_HEIGHT = 12;
const BOLD_TEXT_ATTRIBUTES = 1;
const PANEL_WIDTH_RATIO = 0.85;
const PANEL_MARGIN = 2;
const TODO_LINE_ID_PREFIX = "opencode-todo-line";

const SPLIT_BORDER_CHARS = {
  topLeft: "",
  bottomLeft: "",
  vertical: "┃",
  topRight: "",
  bottomRight: "",
  horizontal: " ",
  bottomT: "",
  topT: "",
  cross: "",
  leftT: "",
  rightT: "",
};

type SolidAdapter = {
  createSignal: <T>(initial: T) => readonly [
    get: () => T,
    set: (next: T | ((previous: T) => T)) => unknown,
  ];
  createElement: (kind: string) => any;
  setProp: (node: any, name: string, value: unknown) => void;
  insert: (parent: any, child: any) => void;
};

function box(props: Record<string, unknown>, children: RenderNode[] = []): RenderNode {
  return { kind: "box", props, children };
}

function text(props: Record<string, unknown>, value: string): RenderNode {
  return { kind: "text", props, text: value };
}

function scrollbox(props: Record<string, unknown>, children: RenderNode[] = []): RenderNode {
  return { kind: "scrollbox", props, children };
}

function lineColor(line: TodoLine, theme: Theme): unknown {
  if (line.kind === "in_progress") return theme.success;
  if (line.kind === "pending") return theme.warning;
  return theme.textMuted;
}

function sameColor(current: unknown, target: unknown): boolean {
  if (current === target) return true;
  if (!current || typeof current !== "object" || !("equals" in current)) return false;
  const equals = (current as { equals?: (color: unknown) => boolean }).equals;
  return typeof equals === "function" && equals.call(current, target);
}

function recolorAttachmentLabels(root: RenderTreeAdapter, foreground: unknown, background: unknown): void {
  const visitTextNode = (node: TextNodeAdapter): string => {
    const value = (node.children ?? [])
      .map((child) => (typeof child === "string" ? child : visitTextNode(child)))
      .join("");
    if ([" File ", " Directory "].includes(value)) {
      if (!sameColor(node.fg, foreground)) node.fg = foreground;
      if (!sameColor(node.bg, background)) node.bg = background;
    }
    return value;
  };
  const visitRenderable = (node: RenderTreeAdapter) => {
    for (const textNode of node.getTextChildren?.() ?? []) visitTextNode(textNode);
    for (const child of node.getChildren?.() ?? []) visitRenderable(child);
  };
  visitRenderable(root);
}

export function registerMessageLabelColors(api: Parameters<TuiPlugin>[0]): void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const recolor = () => {
    timer = undefined;
    recolorAttachmentLabels(api.renderer.root, api.theme.current.selectedListItemText, api.theme.current.primary);
  };
  const schedule = () => {
    if (timer !== undefined) return;
    api.renderer.requestRender();
    timer = setTimeout(recolor, 0);
  };

  const unsubscribePart = api.event.on("message.part.updated", schedule);
  const unsubscribeMessage = api.event.on("message.updated", schedule);
  api.lifecycle.onDispose(() => {
    if (timer !== undefined) clearTimeout(timer);
    unsubscribePart();
    unsubscribeMessage();
  });
  schedule();
}

export function popupWidth(terminalWidth: number): number {
  const columns = Number.isFinite(terminalWidth) ? Math.max(1, Math.floor(terminalWidth)) : MAX_PANEL_WIDTH;
  const available = Math.max(1, columns - PANEL_MARGIN * 2);
  const responsive = Math.max(MIN_PANEL_WIDTH, Math.floor(columns * PANEL_WIDTH_RATIO));
  return Math.min(MAX_PANEL_WIDTH, available, responsive);
}

export function buildTodoOverlayNodes(
  todos: readonly TodoItem[],
  theme: Theme,
  terminalWidth = MAX_PANEL_WIDTH * 2,
): RenderNode | null {
  const view = buildTodoView(todos);
  if (!view) return null;

  const header = `Todo · ${view.completed} of ${view.total}`;
  const startID = `${TODO_LINE_ID_PREFIX}-${view.windowStart}`;
  const endID = `${TODO_LINE_ID_PREFIX}-${view.windowEnd}`;
  const body = scrollbox(
    {
      width: "100%",
      // Give wrapped task text room without letting the HUD grow indefinitely.
      // The ScrollBox still handles unusually long content and larger lists.
      height: Math.min(MAX_BODY_HEIGHT, Math.max(1, view.lines.length * 2)),
      scrollX: false,
      scrollY: true,
      viewportCulling: true,
      verticalScrollbarOptions: { visible: false, showArrows: false },
      contentOptions: { flexDirection: "column" },
    },
    view.lines.map((line, index) =>
      text(
        {
          id: `${TODO_LINE_ID_PREFIX}-${index}`,
          fg: lineColor(line, theme),
          width: "100%",
          wrapMode: "char",
        },
        line.text,
      ),
    ),
  );
  body.scrollWindow = {
    startID,
    endID,
    key: `${view.completed}:${view.active}:${startID}:${endID}`,
  };

  return box(
    {
      position: "absolute",
      top: PANEL_MARGIN,
      right: PANEL_MARGIN,
      width: popupWidth(terminalWidth),
      zIndex: 900,
      flexDirection: "column",
      backgroundColor: theme.backgroundPanel,
      border: ["left", "right"],
      borderColor: theme.info,
      customBorderChars: SPLIT_BORDER_CHARS,
      paddingLeft: 2,
      paddingRight: 2,
      paddingTop: 1,
      paddingBottom: 1,
    },
    [
      box(
        {
          alignSelf: "flex-start",
          flexDirection: "row",
          backgroundColor: theme.info,
          paddingLeft: 1,
          paddingRight: 1,
          marginBottom: 1,
        },
        [
          text(
            {
              fg: theme.backgroundPanel,
              attributes: BOLD_TEXT_ATTRIBUTES,
              wrapMode: "none",
              truncate: true,
            },
            header,
          ),
        ],
      ),
      body,
    ],
  );
}

function materialize(
  node: RenderNode,
  solid: SolidAdapter,
  onScrollBox?: (node: ScrollBoxAdapter, window: RenderNode["scrollWindow"]) => void,
) {
  const element = solid.createElement(node.kind);
  for (const [name, value] of Object.entries(node.props)) solid.setProp(element, name, value);
  if (node.kind === "text") solid.insert(element, node.text ?? "");
  for (const child of node.children ?? []) solid.insert(element, materialize(child, solid, onScrollBox));
  if (node.kind === "scrollbox") onScrollBox?.(element as ScrollBoxAdapter, node.scrollWindow);
  return element;
}

export function sessionIDFromRoute(route: TuiRouteCurrent): string | undefined {
  if (!route || typeof route !== "object" || route.name !== "session") return undefined;
  const params = "params" in route ? route.params : undefined;
  if (!params || typeof params !== "object") return undefined;
  const sessionID = (params as Record<string, unknown>).sessionID;
  return typeof sessionID === "string" && sessionID.length > 0 ? sessionID : undefined;
}

function todoFingerprint(todos: readonly TodoItem[]): string {
  return JSON.stringify(
    todos.map((todo) => ({
      content: todo.content,
      status: todo.status,
    })),
  );
}

function latestUserMessageID(messages: readonly { id: string; role: string }[]): string | undefined {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message?.role === "user") return message.id;
  }
  return undefined;
}

export function registerTodoOverlay(api: Parameters<TuiPlugin>[0], solid: SolidAdapter): void {
  const scrollOffsets = new Map<string, { scrollTop: number; windowKey: string }>();
  const hiddenTodoSnapshots = new Map<string, string>();
  const latestUserMessages = new Map<string, string>();
  const [overlayRevision, setOverlayRevision] = solid.createSignal(0);
  let mounted: { sessionID: string; scrollbox: ScrollBoxAdapter; windowKey: string } | undefined;

  const invalidateOverlay = () => {
    setOverlayRevision((revision) => revision + 1);
    api.renderer.requestRender();
  };

  const rememberScroll = () => {
    if (!mounted || mounted.scrollbox.isDestroyed) return;
    if (Number.isFinite(mounted.scrollbox.scrollTop)) {
      scrollOffsets.set(mounted.sessionID, {
        scrollTop: mounted.scrollbox.scrollTop,
        windowKey: mounted.windowKey,
      });
    }
  };

  const unsubscribeTodo = api.event.on("todo.updated", (event) => {
    const staleFingerprint = hiddenTodoSnapshots.get(event.properties.sessionID);
    // A delayed repeat of the old Todo list must not reopen the stale popup.
    if (staleFingerprint !== undefined && todoFingerprint(event.properties.todos) !== staleFingerprint) {
      hiddenTodoSnapshots.delete(event.properties.sessionID);
    }
    invalidateOverlay();
  });
  api.lifecycle.onDispose(() => {
    rememberScroll();
    mounted = undefined;
    scrollOffsets.clear();
    hiddenTodoSnapshots.clear();
    latestUserMessages.clear();
    unsubscribeTodo();
  });

  const renderOverlay = () => {
    // Host state getters and requestRender do not invalidate a static slot
    // result. Keep the changing HUD inside a reactive insertion.
    overlayRevision();
    rememberScroll();
    const sessionID = sessionIDFromRoute(api.route.current);
    if (!sessionID) {
      mounted = undefined;
      return null;
    }
    const todos = api.state.session.todo(sessionID);
    const latestUser = latestUserMessageID(api.state.session.messages(sessionID));
    const previousUser = latestUserMessages.get(sessionID);
    if (latestUser !== undefined && previousUser === undefined) {
      latestUserMessages.set(sessionID, latestUser);
    } else if (latestUser !== undefined && latestUser !== previousUser) {
      latestUserMessages.set(sessionID, latestUser);
      hiddenTodoSnapshots.set(sessionID, todoFingerprint(todos));
      scrollOffsets.delete(sessionID);
    }
    if (hiddenTodoSnapshots.has(sessionID)) {
      mounted = undefined;
      return null;
    }
    const nodes = buildTodoOverlayNodes(todos, api.theme.current, api.renderer.width);
    if (!nodes) {
      mounted = undefined;
      return null;
    }

    let nextScrollBox: ScrollBoxAdapter | undefined;
    let nextScrollWindow: RenderNode["scrollWindow"];
    const result = materialize(nodes, solid, (node, window) => {
      nextScrollBox = node;
      nextScrollWindow = window;
    });
    if (nextScrollBox && nextScrollWindow) {
      const remembered = scrollOffsets.get(sessionID);
      const offset = remembered?.windowKey === nextScrollWindow.key ? remembered.scrollTop : undefined;
      const window = nextScrollWindow;
      let initialized = false;
      solid.setProp(nextScrollBox, "onSizeChange", function (this: ScrollBoxAdapter) {
        if (initialized || this.isDestroyed) return;

        const start = this.content?.findDescendantById(window.startID);
        const end = this.content?.findDescendantById(window.endID);
        if (start && end) {
          const windowHeight = Math.min(MAX_BODY_HEIGHT, Math.max(1, end.y + end.height - start.y));
          if (this.height !== windowHeight) {
            this.height = windowHeight;
            return;
          }
        }
        initialized = true;
        if (offset !== undefined) {
          this.scrollTop = offset;
        } else if (start && this.content) {
          this.scrollTop = Math.max(0, start.y - this.content.y);
        }
      });
      mounted = { sessionID, scrollbox: nextScrollBox, windowKey: nextScrollWindow.key };
    }
    return result;
  };

  api.slots.register({
    order: 900,
    slots: {
      app: () => {
        const root = solid.createElement("box");
        solid.setProp(root, "position", "absolute");
        solid.setProp(root, "top", 0);
        solid.setProp(root, "right", 0);
        solid.setProp(root, "bottom", 0);
        solid.setProp(root, "left", 0);
        solid.setProp(root, "zIndex", 900);
        solid.insert(root, renderOverlay);
        return root;
      },
    },
  });
}

export const tui: TuiPlugin = async (api) => {
  const [solid, { createSignal }] = await Promise.all([
    import("@opentui/solid"),
    import("solid-js/dist/solid.js"),
  ]);
  registerMessageLabelColors(api);
  registerTodoOverlay(api, { ...solid, createSignal });
};

export default { id: "opencode-todo-overlay:tui", tui };
