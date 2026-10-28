import { strict as assert } from "node:assert";
import { afterEach, describe, it, mock } from "bun:test";

const commands: Array<{ command: string; args: string[] }> = [];
mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));
mock.module("node:child_process", () => ({
  execFile: (
    command: string,
    args: string[],
    _options: unknown,
    callback: (error: Error | null, stdout: string) => void,
  ) => {
    commands.push({ command, args });
    callback(null, "");
  },
}));

const { HerdrWorkerTitle } = await import("./herdr-worker-title.js");

const variables = ["HERDR_AGENT_LAYOUT_WORKER", "HERDR_HAPPIER_WORKER", "HAPPIER_SESSION_ID"] as const;
const originals = Object.fromEntries(variables.map((variable) => [variable, process.env[variable]]));

afterEach(() => {
  commands.length = 0;
  for (const variable of variables) {
    if (originals[variable] === undefined) delete process.env[variable];
    else process.env[variable] = originals[variable];
  }
});

function context(events: unknown[] = []) {
  const hooks: Record<string, (event: any) => unknown> = {};
  const updates: unknown[] = [];
  const subscriptions: unknown[] = [];
  return {
    hooks,
    updates,
    subscriptions,
    value: {
      session: {
        update: async (input: unknown) => { updates.push(input); },
      },
      shell: {
        hook: async (name: string, callback: (event: any) => unknown) => { hooks[name] = callback; },
      },
      event: {
        subscribe: (options: unknown) => {
          subscriptions.push(options);
          return (async function* () {
            for (const event of events) yield event;
          })();
        },
      },
    },
  };
}

async function settle(predicate: () => boolean) {
  for (let attempt = 0; attempt < 20 && !predicate(); attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  assert.equal(predicate(), true);
}

describe("Herdr worker session title", () => {
  it("prefixes V2 rename events and syncs Happier once", async () => {
    process.env.HERDR_AGENT_LAYOUT_WORKER = "1";
    process.env.HERDR_HAPPIER_WORKER = "1";
    process.env.HAPPIER_SESSION_ID = "happier_worker";
    const ctx = context([
      { type: "session.renamed", data: { sessionID: "ses_worker", title: "New session - 2026-08-10T00:00:00.000Z" } },
      { type: "session.renamed", data: { sessionID: "ses_worker", title: "Review the change" } },
      { type: "session.renamed", data: { sessionID: "ses_worker", title: "[Subagent] Review the change" } },
    ]);

    const cleanup = await HerdrWorkerTitle.setup(ctx.value);
    await settle(() => commands.length === 1);

    assert.equal(HerdrWorkerTitle.id, "dotfiles.herdr-worker-title");
    assert.deepEqual(ctx.updates, [
      { sessionID: "ses_worker", title: "[Subagent] Review the change" },
    ]);
    assert.deepEqual(commands, [{
      command: "happier",
      args: ["session", "set-title", "happier_worker", "[Subagent] Review the change"],
    }]);
    assert.deepEqual(ctx.subscriptions.map(({ types }: any) => types), [["session.renamed"]]);
    const workerShell = { env: { HERDR_ENV: "1", HERDR_PANE_ID: "worker:pane" } };
    await ctx.hooks["create.before"](workerShell);
    assert.deepEqual(workerShell.env, { HERDR_ENV: "1", HERDR_PANE_ID: "worker:pane" });
    await cleanup?.();
  });

  it("removes pane credentials when a shared V2 server cannot identify the shell session", async () => {
    delete process.env.HERDR_AGENT_LAYOUT_WORKER;
    const ctx = context();
    await HerdrWorkerTitle.setup(ctx.value);

    const shell = { env: {
      HERDR_ENV: "1",
      HERDR_PANE_ID: "wrong:pane",
      HERDR_TAB_ID: "wrong:tab",
      HERDR_WORKSPACE_ID: "wrong",
      PATH: "/bin",
    } };
    await ctx.hooks["create.before"](shell);

    assert.deepEqual(shell.env, { PATH: "/bin" });
    assert.deepEqual(commands, []);
    assert.deepEqual(ctx.subscriptions, []);
  });
});
