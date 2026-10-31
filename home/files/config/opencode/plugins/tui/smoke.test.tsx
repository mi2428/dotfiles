/** @jsxImportSource @opentui/solid */
import { strict as assert } from "node:assert";
import { it } from "bun:test";
import { createTestRenderer } from "@opentui/core/testing";
import { BoxRenderable, ScrollBoxRenderable, TextRenderable } from "@opentui/core";
import { render } from "@opentui/solid";
import { createSignal } from "solid-js";
import { parseThemeDocument, resolveThemeDocument } from "@opencode/theme/tui";
import plugin from "./tui";
import theme from "../../themes/catppuccin-mocha-mauve.json";

it("renders the v2 HUD with actual OpenTUI 0.7 renderables", async () => {
  const test = await createTestRenderer({ width: 80, height: 20 });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  assert.equal(resolved.background.base.a, 0);
  const chat = new ScrollBoxRenderable(test.renderer, { width: "100%", height: "100%", scrollY: true });
  for (let index = 0; index < 30; index++) {
    chat.add(new TextRenderable(test.renderer, { content: `message ${index}`, width: "100%" }));
  }
  test.renderer.root.add(chat);
  let slot: (() => unknown) | undefined;
  const [route, setRoute] = createSignal("ses_1");
  const scrollMemory = { offsets: {} as Record<string, { windowKey: string; scrollTop: number }> };
  const handlers = new Map<string, (event: any) => void>();
  let invalidations = 0;
  const cleanup = plugin.setup({
    renderer: test.renderer,
    theme: resolved,
    storage: { memory: () => [scrollMemory, (mutate: (draft: typeof scrollMemory) => void) => mutate(scrollMemory)] },
    ui: {
      router: { current: () => ({ type: "session", sessionID: route() }) },
      slot: (claim: { render: () => unknown }) => { slot = claim.render; return () => {}; },
    },
    data: {
      on: (name: string, handler: (event: any) => void) => {
        handlers.set(name, handler);
        return () => { handlers.delete(name); };
      },
      session: { get: () => undefined, message: {
        sync: async () => {},
        invalidate: () => { invalidations++; },
        get: () => undefined,
        list: () => [{ type: "assistant", content: [{
          type: "tool", name: "todowrite", state: { status: "completed", input: { todos: [
            { content: "oldest", status: "completed" },
            { content: "older", status: "completed" },
            { content: "recent", status: "completed" },
            { content: "previous", status: "completed" },
            { content: "current work", status: "in_progress" },
            { content: "next", status: "pending" },
            { content: "later", status: "pending" },
            { content: "last visible", status: "pending" },
            { content: "hidden future", status: "pending" },
          ] } },
        }] }],
      } },
    },
    client: { session: { message: { get: async ({ sessionID, messageID }: { sessionID: string; messageID: string }) => {
      assert.equal(sessionID, "ses_1");
      if (messageID === "msg_other") return { type: "assistant", content: [{
        type: "tool", id: "tool_other", name: "other", state: { status: "completed", input: {} },
      }] };
      assert.equal(messageID, "msg_fallback");
      return { type: "assistant", content: [{ type: "tool", id: "tool_fallback", name: "todowrite",
        state: { status: "completed", input: { todos: [{ content: "restored progress", status: "completed" }] } } }] };
    } } } },
  } as never);
  assert(slot);
  try {
    await render(() => slot!() as never, test.renderer);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    const frame = test.captureCharFrame();
    assert.match(frame, /Todo · 5 of 9/);
    assert.match(frame, /previous/);
    assert.match(frame, /current work/);
    assert.match(frame, /next/);
    assert.doesNotMatch(frame, /oldest|older/);
    const panel = test.renderer.root.findDescendantById("todo-panel") as BoxRenderable;
    assert(panel);
    assert.equal(panel.width, 68);
    assert(panel.backgroundColor.equals(resolved.background.raised.base));
    assert.equal(panel.backgroundColor.a, 1);
    assert((test.renderer.root.findDescendantById("todo-line-0") as TextRenderable).fg.equals(resolved.text.muted));
    assert((test.renderer.root.findDescendantById("todo-line-4") as TextRenderable).fg.equals(resolved.text.feedback.success.base));
    assert((test.renderer.root.findDescendantById("todo-line-5") as TextRenderable).fg.equals(resolved.text.feedback.warning.base));
    const todos = test.renderer.root.findDescendantById("todo-scroll") as ScrollBoxRenderable;
    assert(todos);
    assert.equal(todos.scrollTop, 3);
    await test.mockMouse.scroll(5, 12, "down", { delayMs: 0 });
    await test.renderOnce();
    assert(chat.scrollTop > 0, "chat receives wheel events outside the HUD");
    await test.mockMouse.scroll(todos.x + 1, todos.y + 1, "up", { delayMs: 0 });
    await test.renderOnce();
    assert(todos.scrollTop < 3, "HUD retains its own scrollback");
    const savedScrollTop = todos.scrollTop;
    setRoute("ses_2");
    await test.renderOnce();
    await test.renderer.idle();
    setRoute("ses_1");
    await test.renderOnce();
    await test.renderer.idle();
    assert.equal(todos.scrollTop, savedScrollTop, "HUD restores manual scroll after a session switch");
    assert.deepEqual(scrollMemory.offsets.ses_1, {
      windowKey: "ses_1:4:3",
      scrollTop: savedScrollTop,
    });
    assert(handlers.has("session.tool.input.started"));
    assert(handlers.has("session.tool.success"));
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_updated", id: "tool_updated", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: { sessionID: "ses_1", assistantMessageID: "msg_updated",
      id: "tool_updated", metadata: { todos: [
      ...Array.from({ length: 5 }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
      { content: "now active", status: "in_progress" },
      { content: "later", status: "pending" },
    ] } } });
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Todo · 6 of 7/);
    assert.match(test.captureCharFrame(), /now active/);
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_fallback", id: "tool_fallback", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_fallback", id: "tool_fallback",
    } });
    await Bun.sleep(0);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.equal(invalidations, 1);
    assert.match(test.captureCharFrame(), /Todo · 1 of 1/);
    assert.match(test.captureCharFrame(), /restored progress/);
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other", name: "other",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other",
      metadata: { todos: [{ content: "spoofed", status: "pending" }] },
    } });
    assert.equal(invalidations, 1);
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other",
      metadata: { todos: [{ content: "spoofed", status: "pending" }] },
    } });
    await Bun.sleep(0);
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /spoofed/);
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_clear", id: "tool_clear", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_clear", id: "tool_clear", metadata: { todos: [] },
    } });
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /Todo ·/);
  } finally {
    if (typeof cleanup === "function") await cleanup();
    test.renderer.destroy();
  }
});

it("restores an old Todo on cold start when the TUI message cache has no Todo", async () => {
  const test = await createTestRenderer({ width: 80, height: 20 });
  let slot: (() => unknown) | undefined;
  const requests: string[] = [];
  plugin.setup({
    renderer: test.renderer,
    theme: resolveThemeDocument(parseThemeDocument(theme), "dark"),
    storage: { memory: (_key: string, options: { initial: object }) => [options.initial, () => {}] },
    ui: {
      router: { current: () => ({ type: "session", sessionID: "ses_old" }) },
      slot: (claim: { render: () => unknown }) => { slot = claim.render; return () => {}; },
    },
    data: { on: () => () => {}, session: { get: () => undefined, message: {
      sync: async () => {}, list: () => [],
    } } },
    client: { message: { list: async (input: { sessionID: string; cursor?: string; order?: string; type: string }) => {
      if (input.cursor && "order" in input) throw new Error("Cursor cannot be combined with order");
      assert.deepEqual([input.sessionID, input.type], ["ses_old", "assistant"]);
      if (!input.cursor) assert.equal(input.order, "desc");
      else assert.equal("order" in input, false);
      requests.push(input.cursor ?? "first");
      if (!input.cursor) return { data: [], cursor: { next: "older" } };
      return { data: [{ id: "msg_old", type: "assistant", content: [{
        type: "tool", name: "todowrite", state: { status: "completed", input: { todos: [
          { content: "old task still visible", status: "in_progress" },
        ] } },
      }] }], cursor: {} };
    } } },
  } as never);
  assert(slot);
  try {
    await render(() => slot!() as never, test.renderer);
    await Bun.sleep(0);
    await test.renderOnce();
    assert.deepEqual(requests, ["first", "older"]);
    assert.match(test.captureCharFrame(), /Todo · 1 of 1/);
    assert.match(test.captureCharFrame(), /old task still visible/);
  } finally {
    test.renderer.destroy();
  }
});
