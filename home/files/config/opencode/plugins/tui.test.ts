import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import { buildTodoView, MAX_CONTENT_LENGTH } from "./tui/lib/todo-overlay";
import { buildTodoOverlayNodes, registerTodoOverlay, sessionIDFromRoute } from "./tui/tui";

const todos = [
  { content: "finish report", status: "completed" },
  { content: "wire overlay", status: "pending" },
  { content: "run tests", status: "in_progress" },
  { content: "old task", status: "cancelled" },
];

describe("todo overlay state", () => {
  it("orders in-progress before pending and compresses archived statuses", () => {
    const view = buildTodoView(todos);
    assert(view);
    assert.deepEqual(view.lines.map((line) => line.text), ["▶ run tests", "· wire overlay", "✓ 1 completed  ·  × 1 cancelled"]);
    assert.equal(view.active, 2);
    assert.equal(view.completed, 1);
    assert.equal(view.cancelled, 1);
  });

  it("returns no overlay data for an empty todo list", () => {
    assert.equal(buildTodoView([]), null);
  });

  it("keeps the overlay session-only and positions it as a non-focusable top panel", () => {
    assert.equal(sessionIDFromRoute({ name: "home" }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: "ses_1" } }), "ses_1");
    assert.equal(sessionIDFromRoute({ name: "session", params: {} }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: 42 } } as never), undefined);
    assert.equal(sessionIDFromRoute({ name: "other", params: { sessionID: "ses_1" } }), undefined);
    assert.equal(buildTodoOverlayNodes([], {} as never), null);

    const nodes = buildTodoOverlayNodes([{ content: "work", status: "pending" }], {
      backgroundPanel: "panel",
      borderSubtle: "border",
      info: "info",
      success: "success",
      warning: "warning",
      text: "text",
      textMuted: "muted",
    });
    assert(nodes);
    assert.equal(nodes.props.position, "absolute");
    assert.equal(nodes.props.top, 0);
    assert.equal("focusable" in nodes.props, false);
  });

  it("caps visible active items and truncates long content", () => {
    const view = buildTodoView([
      { content: "x".repeat(MAX_CONTENT_LENGTH + 20), status: "in_progress" },
      { content: "second", status: "pending" },
      { content: "third", status: "pending" },
      { content: "fourth", status: "pending" },
    ]);

    assert(view);
    assert.equal(view.lines.length, 4);
    assert.equal(view.hiddenActive, 1);
    assert.equal(view.lines[0]?.text.length, MAX_CONTENT_LENGTH + 2);
    assert.equal(view.lines[0]?.text.endsWith("…"), true);
    assert.equal(view.lines[3]?.text, "… 1 more active");
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
      renderer: { requestRender: () => (renders += 1) },
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
    const solid = {
      createElement: (kind: string) => ({ kind, props: {}, children: [] as unknown[] }),
      setProp: (node: { props: Record<string, unknown> }, name: string, value: unknown) => {
        node.props[name] = value;
      },
      insert: (node: { children: unknown[] }, child: unknown) => {
        node.children.push(child);
      },
    };

    registerTodoOverlay(api as never, solid);
    assert(eventHandler);
    assert(dispose);
    assert(appSlot);
    assert(appSlot());
    assert(appSlot());
    assert.equal(reads, 2);
    eventHandler();
    assert.equal(renders, 1);
    dispose();
    assert.equal(unsubscribes, 1);
  });
});
