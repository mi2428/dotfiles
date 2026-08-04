import type { TuiPlugin, TuiRouteCurrent } from "@opencode-ai/plugin/tui";
import { buildTodoView, type TodoLine, type TodoItem } from "./lib/todo-overlay";

type Theme = {
  backgroundPanel: unknown;
  borderSubtle: unknown;
  info: unknown;
  success: unknown;
  warning: unknown;
  text: unknown;
  textMuted: unknown;
};

type RenderNode = {
  kind: "box" | "text";
  props: Record<string, unknown>;
  text?: string;
  children?: RenderNode[];
};

type SolidAdapter = {
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

function lineColor(line: TodoLine, theme: Theme): unknown {
  if (line.kind === "in_progress") return theme.success;
  if (line.kind === "pending") return theme.warning;
  if (line.kind === "summary") return theme.textMuted;
  return theme.text;
}

export function buildTodoOverlayNodes(todos: readonly TodoItem[], theme: Theme): RenderNode | null {
  const view = buildTodoView(todos);
  if (!view) return null;

  const header = `Todo · ${view.active} active${view.completed ? ` · ${view.completed} done` : ""}${view.cancelled ? ` · ${view.cancelled} cancelled` : ""}`;
  return box(
    {
      position: "absolute",
      top: 0,
      left: 0,
      width: "100%",
      maxHeight: 8,
      overflow: "hidden",
      zIndex: 900,
      flexDirection: "column",
      backgroundColor: theme.backgroundPanel,
      border: true,
      borderStyle: "single",
      borderColor: theme.borderSubtle,
      paddingLeft: 1,
      paddingRight: 1,
    },
    [
      text({ fg: theme.info, wrapMode: "none", truncate: true }, header),
      ...view.lines.map((line) => text({ fg: lineColor(line, theme), wrapMode: "none", truncate: true }, line.text)),
    ],
  );
}

function materialize(node: RenderNode, solid: SolidAdapter) {
  const element = solid.createElement(node.kind);
  for (const [name, value] of Object.entries(node.props)) solid.setProp(element, name, value);
  if (node.kind === "text") solid.insert(element, node.text ?? "");
  for (const child of node.children ?? []) solid.insert(element, materialize(child, solid));
  return element;
}

export function sessionIDFromRoute(route: TuiRouteCurrent): string | undefined {
  if (!route || typeof route !== "object" || route.name !== "session") return undefined;
  const params = "params" in route ? route.params : undefined;
  if (!params || typeof params !== "object") return undefined;
  const sessionID = (params as Record<string, unknown>).sessionID;
  return typeof sessionID === "string" && sessionID.length > 0 ? sessionID : undefined;
}

export function registerTodoOverlay(api: Parameters<TuiPlugin>[0], solid: SolidAdapter): void {
  const unsubscribe = api.event.on("todo.updated", () => api.renderer.requestRender());
  api.lifecycle.onDispose(unsubscribe);

  api.slots.register({
    order: 900,
    slots: {
      app: () => {
        const sessionID = sessionIDFromRoute(api.route.current);
        if (!sessionID) return null;
        // OpenCode may hydrate an existing session after the first slot render.
        // Read its authoritative state every render rather than caching that
        // potentially empty first snapshot indefinitely.
        const nodes = buildTodoOverlayNodes(api.state.session.todo(sessionID), api.theme.current);
        return nodes ? materialize(nodes, solid) : null;
      },
    },
  });
}

export const tui: TuiPlugin = async (api) => {
  const solid = await import("@opentui/solid");
  registerTodoOverlay(api, solid);
};

export default { id: "opencode-todo-overlay:tui", tui };
