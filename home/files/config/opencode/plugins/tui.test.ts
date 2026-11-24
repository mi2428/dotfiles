import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import { buildTodoView } from "./tui/lib/todo-overlay";
import { popupWidth, MAX_PANEL_WIDTH, HUD_MAX_ROWS } from "./tui/hud/layout";
import { latestTodos, recoverTodos } from "./tui/hud/todo";

const todos = [
  { content: "finish report", status: "completed" },
  { content: "run tests", status: "in_progress" },
  { content: "wire overlay", status: "pending" },
  { content: "old task", status: "cancelled" },
];

describe("OpenCode v2 Todo HUD", () => {
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

  it("shows current and upcoming tasks with progress only when rows are omitted", () => {
    const view = buildTodoView(todos, HUD_MAX_ROWS);
    assert(view);
    assert.deepEqual(view.lines, [
      { kind: "completed", text: "✓ finish report" },
      { kind: "in_progress", text: "▶ run tests" },
      { kind: "pending", text: "○ wire overlay" },
    ]);
    assert.equal(view.total, 3);
    assert.equal(view.completed, 1);
    assert.equal(view.active, 2);
    assert.equal(view.summary, false, "completed tasks share spare rows without a summary when everything fits");
    assert.equal(buildTodoView([{ content: "cancelled", status: "cancelled" }], 7), null);
    assert.equal(buildTodoView([{ content: "finished", status: "completed" }], 7), null);
    const many = buildTodoView([
      ...Array.from({ length: 10 }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
      { content: "current", status: "in_progress" },
      ...Array.from({ length: 6 }, (_, index) => ({ content: `next ${index}`, status: "pending" })),
    ], HUD_MAX_ROWS);
    assert(many);
    assert.equal(many.lines.length, 7);
    assert.deepEqual(many.lines.map((line) => line.text), [
      "▶ current", ...Array.from({ length: 6 }, (_, index) => `○ next ${index}`),
    ]);
    assert.deepEqual([many.completed, many.active, many.total], [10, 7, 17]);
    const pending = buildTodoView([
      { content: "done", status: "completed" },
      { content: "first", status: "pending" },
      { content: "later", status: "pending" },
    ], HUD_MAX_ROWS);
    assert.deepEqual(pending?.lines.map((line) => line.text), ["✓ done", "○ first", "○ later"]);
    for (const count of [1, 8, 9]) {
      const unfinished = buildTodoView(Array.from({ length: count }, (_, index) => ({
        content: `future ${index}`, status: "pending",
      })), HUD_MAX_ROWS)!;
      assert.equal(unfinished.summary, count > 8);
      assert.equal(unfinished.lines.length, count > 8 ? 7 : count);
      assert.equal(unfinished.active, count);
    }
    const reordered = buildTodoView([
      { content: "next", status: "pending" }, { content: "current", status: "in_progress" },
      { content: "cancelled", status: "cancelled" },
    ], HUD_MAX_ROWS)!;
    assert.deepEqual(reordered.lines.map((line) => line.text), ["▶ current", "○ next"]);
    assert.equal(reordered.summary, false);
    assert.equal(popupWidth(80), 68);
    assert.equal(popupWidth(120), MAX_PANEL_WIDTH);
    assert.equal(popupWidth(30), 26);
    assert.equal(popupWidth(NaN), 72);
  });

  it("fills spare rows with the nearest completed tasks without displacing upcoming work", () => {
    for (const [done, active] of [[6, 2], [7, 2], [12, 3], [3, 7], [3, 8], [0, 9]]) {
      const view = buildTodoView([
        ...Array.from({ length: done }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
        { content: "current", status: "in_progress" },
        ...Array.from({ length: active - 1 }, (_, index) => ({ content: `next ${index}`, status: "pending" })),
      ], HUD_MAX_ROWS)!;
      const summary = done + active > HUD_MAX_ROWS;
      const capacity = HUD_MAX_ROWS - Number(summary);
      const visibleDone = Math.max(0, Math.min(done, capacity - active));
      assert.equal(view.summary, summary, `${done} done, ${active} active`);
      assert.deepEqual(view.lines.map((line) => line.text), [
        ...Array.from({ length: visibleDone }, (_, index) => `✓ done ${done - visibleDone + index}`),
        "▶ current",
        ...Array.from({ length: Math.min(active, capacity) - 1 }, (_, index) => `○ next ${index}`),
      ]);
      assert(view.lines.length + Number(view.summary) <= HUD_MAX_ROWS);
      assert.deepEqual([view.completed, view.active], [done, active]);
    }
  });
});
