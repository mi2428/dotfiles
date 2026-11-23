import { strict as assert } from "node:assert";
import { describe, it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));

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

describe("conversation-based session titles", () => {
  it("adds its policy without removing the agent, model, or ambient instructions", async () => {
    const { hooks } = await setup(SessionTitle);
    const event = { system: [
      { type: "text", text: "Chat agent system" },
      { type: "text", text: "# Your Model\n- Model ID: test" },
      { type: "text", text: "Instructions from: AGENTS.md" },
    ] };
    await hooks.context(event);

    assert.match(event.system[0]?.text ?? "", /Call session_title with that summary/);
    assert.deepEqual(event.system.slice(1).map(({ text }) => text), [
      "Chat agent system",
      "# Your Model\n- Model ID: test",
      "Instructions from: AGENTS.md",
    ]);
  });

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
    assert.equal(tool.options.codemode, false);
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
