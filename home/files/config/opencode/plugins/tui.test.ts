import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import { buildTodoView } from "./tui/lib/todo-overlay";
import plugin, { bodyHeight, latestTodos, popupWidth, recoverTodos, MAX_BODY_HEIGHT, MAX_PANEL_WIDTH } from "./tui/tui";
import theme from "../themes/catppuccin-mocha-mauve.json";

const todos = [
  { content: "finish report", status: "completed" },
  { content: "run tests", status: "in_progress" },
  { content: "wire overlay", status: "pending" },
  { content: "old task", status: "cancelled" },
];

describe("OpenCode v2 Todo HUD", () => {
  it("registers a non-replacing app slot", () => {
    let claim: { append?: string; render: () => unknown } | undefined;
    const cleanup = () => {};
    assert.equal(plugin.id, "opencode-todo-overlay.tui");
    const result = plugin.setup({ ui: { slot: (value: typeof claim) => { claim = value; return cleanup; } } } as never);
    assert.equal(result, cleanup);
    assert.equal(claim?.append, "app");
    assert.equal(typeof claim?.render, "function");
  });

  it("reads the latest successful todowrite input before a revert boundary", () => {
    const message = (id: string, name: string, input: unknown, status = "completed") => ({
      id, type: "assistant", content: [{ type: "tool", name, state: { status, input } }],
    });
    assert.deepEqual(latestTodos([
      message("msg_01", "todowrite", { todos }),
      { type: "user", text: "next request" },
      message("msg_02", "bash", { todos: [{ content: "wrong", status: "pending" }] }),
    ] as never), { messageID: "msg_01", todos });
    assert.deepEqual(latestTodos([message("msg_01", "todowrite", { todos: [] })] as never), { messageID: "msg_01", todos: [] });
    assert.equal(latestTodos([message("msg_01", "todowrite", { todos }, "running")] as never), undefined);
    assert.equal(latestTodos([message("msg_01", "todowrite", { todos }, "error")] as never), undefined);
    assert.throws(() => latestTodos([message("msg_01", "todowrite", { todos: [{ status: "pending" }] })] as never), /Malformed/);
    assert.deepEqual(latestTodos([
      message("msg_01", "todowrite", { todos }),
      message("msg_02", "todowrite", { todos: [] }),
    ] as never, "msg_02"), { messageID: "msg_01", todos });
  });

  it("recovers the newest historical Todo across server pages and stops at an explicit clear", async () => {
    const requests: string[] = [];
    const message = (id: string, list: unknown) => ({ id, type: "assistant", content: [{
      type: "tool", name: "todowrite", state: { status: "completed", input: { todos: list } },
    }] });
    const client = { message: { list: async (input: { sessionID: string; order?: string; type: string; cursor?: string }) => {
      if (input.cursor && "order" in input) throw new Error("Cursor cannot be combined with order");
      assert.deepEqual([input.sessionID, input.type], ["ses_1", "assistant"]);
      if (!input.cursor) assert.equal(input.order, "desc");
      else assert.equal("order" in input, false);
      requests.push(input.cursor ?? "first");
      if (!input.cursor) return { data: [{ id: "msg_03", type: "assistant", content: [] }], cursor: { next: "older" } };
      return { data: [message("msg_02", []), message("msg_01", todos)], cursor: {} };
    } } };
    assert.deepEqual(await recoverTodos(client as never, "ses_1"), { messageID: "msg_02", todos: [] });
    assert.deepEqual(requests, ["first", "older"]);
    assert.deepEqual(await recoverTodos(client as never, "ses_1", "msg_02"), { messageID: "msg_01", todos });
  });

  it("keeps the original progress, ordering and scroll window", () => {
    const view = buildTodoView(todos);
    assert(view);
    assert.deepEqual(view.lines, [
      { kind: "completed", text: "▸ finish report" },
      { kind: "in_progress", text: "▸ run tests" },
      { kind: "pending", text: "▸ wire overlay" },
    ]);
    assert.equal(view.total, 3);
    assert.equal(view.completed, 1);
    assert.equal(buildTodoView([{ content: "cancelled", status: "cancelled" }]), null);
    const many = buildTodoView([
      ...Array.from({ length: 4 }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
      { content: "current", status: "in_progress" },
      ...Array.from({ length: 6 }, (_, index) => ({ content: `next ${index}`, status: "pending" })),
    ]);
    assert(many);
    assert.deepEqual([many.windowStart, many.windowEnd], [3, 7]);
    assert.equal(many.lines.length, 11);
    assert.equal(popupWidth(80), 68);
    assert.equal(popupWidth(120), MAX_PANEL_WIDTH);
    assert.equal(popupWidth(30), 26);
    assert.equal(popupWidth(NaN), 79);
    assert.equal(MAX_BODY_HEIGHT, 12);
    assert.equal(bodyHeight([{ kind: "pending", text: `▸ ${"x".repeat(140)}` }], 0, 0, 68), 3);
    assert.equal(bodyHeight([{ kind: "pending", text: `▸ ${"日本語".repeat(50)}` }], 0, 0, 68), 5);
    assert.equal(bodyHeight(Array.from({ length: 20 }, () => ({ kind: "pending", text: "task" })), 0, 19, 68), 12);
  });

  it("keeps the Mocha palette and transparent canvas in the v2 theme", () => {
    assert.equal(theme.background, undefined);
    assert.equal(theme.base.background.base, "transparent");
    assert.equal(theme.base.background.raised.base, "#242436");
    assert.equal(theme.base.text.feedback.success.base, "#a6e3a1");
    assert.equal(theme.base.text.feedback.warning.base, "#f9e2af");
    assert.equal(theme.dark.hue.purple[200], "#cba6f7");
    for (const hue of ["gray", "red", "orange", "yellow", "green", "cyan", "blue", "purple"] as const) {
      assert.equal(Object.keys(theme.dark.hue[hue]).length, 9);
    }
  });
});
