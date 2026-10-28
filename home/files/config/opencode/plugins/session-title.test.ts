import { strict as assert } from "node:assert";
import { describe, it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));

const { ChatSystem } = await import("./chat-system.js");
const { FirstThingsFirst } = await import("./first-things-first.js");
const { SessionTitle } = await import("./session-title.js");

async function setup(plugin: { setup: (context: unknown) => unknown }, session = {}) {
  const hooks: Record<string, (event: any) => unknown> = {};
  const tools: Record<string, any> = {};
  await plugin.setup({
    session: {
      ...session,
      hook: async (name: string, callback: (event: any) => unknown) => {
        hooks[name] = callback;
      },
    },
    tool: {
      transform: async (transform: (editor: unknown) => void) => transform({
        add: (tool: { name: string }) => { tools[tool.name] = tool; },
      }),
    },
  });
  return { hooks, tools };
}

describe("V2 system context plugins", () => {
  it("keeps the title instruction with either Chat profile plugin order", async () => {
    const title = await setup(SessionTitle);
    const chat = await setup(ChatSystem);
    for (const hooks of [
      [title.hooks.context, chat.hooks.context],
      [chat.hooks.context, title.hooks.context],
    ]) {
      const event = { system: [
        { type: "text", text: "<chat-agent>Conversation policy</chat-agent>" },
        { type: "text", text: "Other instructions" },
      ] };
      for (const hook of hooks) await hook(event);
      const system = event.system.map(({ text }) => text).join("\n");
      assert.match(system, /Call session_title with that summary/);
      assert.doesNotMatch(system, /Other instructions/);
    }
  });

  it("appends first-things-first as a V2 text system part", async () => {
    const { hooks } = await setup(FirstThingsFirst);
    const event = { system: [{ type: "text", text: "Base policy" }] };
    await hooks.context(event);
    assert.equal(FirstThingsFirst.id, "dotfiles.first-things-first");
    assert.match(event.system.at(-1)?.text ?? "", /<first-things-first>/);
  });
});

describe("conversation-based session titles", () => {
  it("registers a strict V2 tool and updates top-level sessions only when needed", async () => {
    const updates: unknown[] = [];
    const session = { title: "New session - 2026-09-25T00:00:00.000Z" };
    const { tools } = await setup(SessionTitle, {
      get: async () => session,
      update: async (request: { title: string }) => {
        updates.push(request);
        session.title = request.title;
      },
    });
    const tool = tools.session_title;
    const context = { sessionID: "ses_1" };
    const execute = (title: string) => tool.execute({ title }, context);

    assert.equal(SessionTitle.id, "dotfiles.session-title");
    assert.equal(tool.input.additionalProperties, false);
    assert.deepEqual(await execute("  Build   dotfiles  "), { content: "Session title updated" });
    assert.deepEqual(await execute("Build dotfiles"), { content: "Session title unchanged" });
    assert.deepEqual(await execute("Investigate deployment"), { content: "Session title updated" });
    await assert.rejects(execute(" "), /Invalid session title/);
    await assert.rejects(execute("x".repeat(81)), /Invalid session title/);
    assert.deepEqual(updates, [
      { sessionID: "ses_1", title: "Build dotfiles" },
      { sessionID: "ses_1", title: "Investigate deployment" },
    ]);

    Object.assign(session, { parentID: "ses_parent" });
    assert.deepEqual(await execute("Child title"), { content: "Child session title unchanged" });
    assert.equal(updates.length, 2);
  });
});
