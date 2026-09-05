import { strict as assert } from "node:assert";
import { afterEach, describe, it } from "bun:test";
import { HerdrWorkerTitle } from "./herdr-worker-title.js";

const variable = "HERDR_AGENT_LAYOUT_WORKER";
const original = process.env[variable];
afterEach(() => {
  if (original === undefined) delete process.env[variable];
  else process.env[variable] = original;
});

describe("Herdr worker session title", () => {
  it("prefixes worker titles", async () => {
    const updates: unknown[] = [];
    const client = { session: { update: async (input: unknown) => updates.push(input) } };
    const event = (title: string) => ({
      event: {
        type: "session.updated",
        properties: { info: { id: "ses_worker", title } },
      },
    });

    delete process.env[variable];
    assert.equal((await HerdrWorkerTitle({ client, directory: "/repo" })).event, undefined);

    process.env[variable] = "1";
    const hooks = await HerdrWorkerTitle({ client, directory: "/repo" });
    await hooks.event(event("New session - 2026-08-10T00:00:00.000Z"));
    await hooks.event(event("Review the change"));
    await hooks.event(event("[Subagent] Review the change"));

    assert.deepEqual(updates, [
      {
        path: { id: "ses_worker" },
        query: { directory: "/repo" },
        body: { title: "[Subagent] Review the change" },
      },
    ]);
  });

  it("restores the Herdr pane environment for supervisor sessions", async () => {
    delete process.env[variable];
    const shell = () => ({
      json: async () => ({
        result: {
          panes: [
            {
              pane_id: "workspace:pane",
              tab_id: "workspace:tab",
              workspace_id: "workspace",
              agent_session: {
                source: "herdr:opencode",
                value: "ses_supervisor",
              },
            },
          ],
        },
      }),
    });
    const hooks = await HerdrWorkerTitle({ client: {}, directory: "/repo", $: shell });

    await hooks["chat.message"]({
      sessionID: "ses_supervisor",
      agent: "Herdr Supervisor",
    });
    await hooks["chat.message"]({
      sessionID: "ses_supervisor",
      agent: "build",
    });
    const output = { env: {} };
    await hooks["shell.env"]({ sessionID: "ses_supervisor" }, output);

    assert.deepEqual(output.env, {
      HERDR_ENV: "1",
      HERDR_PANE_ID: "workspace:pane",
      HERDR_TAB_ID: "workspace:tab",
      HERDR_WORKSPACE_ID: "workspace",
    });
  });
});
