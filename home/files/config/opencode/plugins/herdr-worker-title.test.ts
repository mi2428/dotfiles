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
  it("prefixes generated root-session titles only in worker panes", async () => {
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
    await hooks.event(event("[Subagent] Existing title"));
    await hooks.event(event("Review the change"));

    assert.deepEqual(updates, [
      {
        path: { id: "ses_worker" },
        query: { directory: "/repo" },
        body: { title: "[Subagent] Review the change" },
      },
    ]);
  });
});
