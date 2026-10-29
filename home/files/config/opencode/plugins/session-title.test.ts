import { strict as assert } from "node:assert";
import { afterEach, beforeEach, describe, it, mock } from "bun:test";

let selected = "ses_worker";
const calls: Array<{ command: string; args: string[] }> = [];
mock.module("node:child_process", () => ({
  execFile: (command: string, args: string[], _options: unknown, callback: (error: Error | null, stdout: string) => void) => {
    calls.push({ command, args });
    callback(null, command === "herdr"
      ? JSON.stringify({ result: { pane: { agent_session: { source: "herdr:opencode", value: selected } } } }) : "");
  },
}));

mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));

const { SessionTitle } = await import("./session-title.js");

const keys = ["HERDR_AGENT_LAYOUT_WORKER", "HERDR_HAPPIER_WORKER", "HERDR_ENV", "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "HAPPIER_SESSION_ID"];
const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
beforeEach(() => { for (const key of keys) delete process.env[key]; });
afterEach(() => {
  calls.length = 0;
  selected = "ses_worker";
  for (const key of keys) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

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

  it("pins the first verified Herdr root and never sends another session title to Happier", async () => {
    Object.assign(process.env, {
      HERDR_AGENT_LAYOUT_WORKER: "1", HERDR_HAPPIER_WORKER: "1", HERDR_ENV: "1",
      HERDR_PANE_ID: "worker:pane", HERDR_SOCKET_PATH: "worker.sock", HAPPIER_SESSION_ID: "happier_worker",
    });
    const titles = new Map<string, string>([["ses_worker", "New session"], ["ses_other", "Private title"]]);
    const updates: unknown[] = [];
    const { tools } = await setup(SessionTitle, {
      get: async ({ sessionID }: { sessionID: string }) => ({ title: titles.get(sessionID) }),
      update: async ({ sessionID, title }: { sessionID: string; title: string }) => {
        updates.push({ sessionID, title });
        titles.set(sessionID, title);
      },
    });
    const tool = tools.session_title;
    assert.deepEqual(await tool.execute({ title: "Review" }, { sessionID: "ses_worker" }), { content: "Session title updated" });
    selected = "ses_other";
    assert.deepEqual(await tool.execute({ title: "Private root" }, { sessionID: "ses_other" }), { content: "Other worker session title unchanged" });
    assert.deepEqual(updates, [{ sessionID: "ses_worker", title: "[Subagent] Review" }]);
    assert.deepEqual(calls.filter(({ command }) => command === "happier").map(({ args }) => args), [
      ["session", "set-title", "happier_worker", "[Subagent] Review"],
    ]);
  });

  it("fails visibly on an unverified first pane selection and can retry the same title", async () => {
    process.env.HERDR_AGENT_LAYOUT_WORKER = "1";
    process.env.HERDR_ENV = "1";
    process.env.HERDR_PANE_ID = "worker:pane";
    process.env.HERDR_SOCKET_PATH = "worker.sock";
    selected = "ses_other";
    const updates: unknown[] = [];
    const { tools } = await setup(SessionTitle, {
      get: async () => ({ title: "New session" }),
      update: async (request: unknown) => { updates.push(request); },
    });
    await assert.rejects(tools.session_title.execute({ title: "Review" }, { sessionID: "ses_worker" }), /not selected/);
    assert.deepEqual(updates, []);
    selected = "ses_worker";
    await tools.session_title.execute({ title: "Review" }, { sessionID: "ses_worker" });
    assert.deepEqual(updates, [{ sessionID: "ses_worker", title: "[Subagent] Review" }]);
  });
});
