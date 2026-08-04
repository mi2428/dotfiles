import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import { buildTodoView } from "./tui/lib/todo-overlay";
import {
  buildTodoOverlayNodes,
  MAX_BODY_HEIGHT,
  MAX_PANEL_WIDTH,
  popupWidth,
  registerTodoOverlay,
  sessionIDFromRoute,
} from "./tui/tui";

const todos = [
  { content: "finish report", status: "completed" },
  { content: "wire overlay", status: "pending" },
  { content: "run tests", status: "in_progress" },
  { content: "old task", status: "cancelled" },
];

describe("todo overlay state", () => {
  it("orders every active item before archived statuses and excludes archived rows", () => {
    const view = buildTodoView(todos);
    assert(view);
    assert.deepEqual(view.lines.map((line) => line.text), ["▶ run tests", "· wire overlay"]);
    assert.equal(view.active, 2);
    assert.equal(view.completed, 1);
    assert.equal(view.cancelled, 1);
  });

  it("returns no overlay data for an empty todo list", () => {
    assert.equal(buildTodoView([]), null);
    assert.equal(buildTodoView([{ content: "done", status: "completed" }]), null);
  });

  it("keeps the overlay session-only and styles it as a responsive top-right toast", () => {
    assert.equal(sessionIDFromRoute({ name: "home" }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: "ses_1" } }), "ses_1");
    assert.equal(sessionIDFromRoute({ name: "session", params: {} }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: 42 } } as never), undefined);
    assert.equal(sessionIDFromRoute({ name: "other", params: { sessionID: "ses_1" } }), undefined);
    assert.equal(buildTodoOverlayNodes([], {} as never), null);

    const nodes = buildTodoOverlayNodes(
      [{ content: "work", status: "pending" }],
      {
        backgroundPanel: "panel",
        borderSubtle: "border",
        info: "info",
        success: "success",
        warning: "warning",
        text: "text",
        textMuted: "muted",
      },
      200,
    );
    assert(nodes);
    assert.equal(nodes.props.position, "absolute");
    assert.equal(nodes.props.top, 2);
    assert.equal(nodes.props.right, 2);
    assert.equal(nodes.props.width, MAX_PANEL_WIDTH);
    assert.deepEqual(nodes.props.border, ["left", "right"]);
    assert.equal(nodes.props.borderStyle, undefined);
    assert.equal("focusable" in nodes.props, false);
    assert.equal(nodes.children?.[1]?.kind, "scrollbox");
    assert.equal(popupWidth(80), 36);
    assert.equal(popupWidth(200), MAX_PANEL_WIDTH);
  });

  it("keeps all active items in the scrollbox without truncating their content", () => {
    const longContent = "x".repeat(140);
    const view = buildTodoView([
      { content: longContent, status: "in_progress" },
      { content: "second", status: "pending" },
      { content: "third", status: "pending" },
      { content: "fourth", status: "pending" },
      { content: "fifth", status: "pending" },
      { content: "archived", status: "completed" },
    ]);

    assert(view);
    assert.equal(view.lines.length, 5);
    assert.equal(view.lines[0]?.text, `▶ ${longContent}`);
    assert.equal(view.lines.some((line) => line.text.includes("more active")), false);

    const nodes = buildTodoOverlayNodes(view.lines.map((line, index) => ({
      content: line.text.slice(2),
      status: index === 0 ? "in_progress" : "pending",
    })), {} as never);
    const body = nodes?.children?.[1];
    assert(body);
    assert.equal(body.kind, "scrollbox");
    assert.equal(body.props.height, MAX_BODY_HEIGHT);
    assert.equal(body.children?.length, 5);
    assert.equal(body.children?.[0]?.props.wrapMode, "word");

    const many = buildTodoOverlayNodes(
      Array.from({ length: 12 }, (_, index) => ({ content: `task ${index}`, status: "pending" })),
      {} as never,
    );
    assert.equal(many?.children?.[1]?.props.height, MAX_BODY_HEIGHT);
  });

  it("reads authoritative state on every render and cleans up its event subscription", () => {
    let eventHandler: (() => void) | undefined;
    let dispose: (() => void) | undefined;
    let appSlot: (() => unknown) | undefined;
    let reads = 0;
    let renders = 0;
    let unsubscribes = 0;

    const api = {
      state: {
        session: {
          todo: (sessionID: string) => {
            assert.equal(sessionID, "ses_1");
            reads += 1;
            return [{ content: "live state", status: "pending" }];
          },
        },
      },
      event: {
        on: (name: string, handler: () => void) => {
          assert.equal(name, "todo.updated");
          eventHandler = handler;
          return () => {
            unsubscribes += 1;
          };
        },
      },
      renderer: { width: 120, requestRender: () => (renders += 1) },
      lifecycle: { onDispose: (handler: () => void) => (dispose = handler) },
      slots: {
        register: (registration: { slots: { app: () => unknown } }) => {
          appSlot = registration.slots.app;
        },
      },
      route: { current: { name: "session", params: { sessionID: "ses_1" } } },
      theme: {
        current: {
          backgroundPanel: "panel",
          borderSubtle: "border",
          info: "info",
          success: "success",
          warning: "warning",
          text: "text",
          textMuted: "muted",
        },
      },
    };
    type FakeNode = {
      kind: string;
      props: Record<string, unknown>;
      children: unknown[];
      scrollTop: number;
      isDestroyed: boolean;
      [key: string]: unknown;
    };
    const solid = {
      createElement: (kind: string): FakeNode => ({
        kind,
        props: {},
        children: [],
        scrollTop: 0,
        isDestroyed: false,
      }),
      setProp: (node: FakeNode, name: string, value: unknown) => {
        node.props[name] = value;
        node[name] = value;
      },
      insert: (node: FakeNode, child: unknown) => {
        node.children.push(child);
      },
    };

    registerTodoOverlay(api as never, solid);
    assert(eventHandler);
    assert(dispose);
    assert(appSlot);
    const first = appSlot() as FakeNode;
    const firstScrollBox = first.children.find((child) => (child as FakeNode).kind === "scrollbox") as FakeNode;
    assert(firstScrollBox);
    firstScrollBox.scrollTop = 3;

    const second = appSlot() as FakeNode;
    const secondScrollBox = second.children.find((child) => (child as FakeNode).kind === "scrollbox") as FakeNode;
    assert(secondScrollBox);
    assert.equal(reads, 2);
    const restore = secondScrollBox.props.onSizeChange as ((this: FakeNode) => void) | undefined;
    assert(restore);
    restore.call(secondScrollBox);
    assert.equal(secondScrollBox.scrollTop, 3);
    eventHandler();
    assert.equal(renders, 1);
    dispose();
    assert.equal(unsubscribes, 1);
  });
});
