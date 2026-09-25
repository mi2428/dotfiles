import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import { ChatSystem } from "./chat-system.js";
import { HerdrWorkerTitle } from "./herdr-worker-title.js";
import { SessionTitle } from "./session-title.js";

describe("conversation-based session titles", () => {
  it("keeps the title instruction with either Chat profile plugin order", async () => {
    const title = await SessionTitle({ client: {} } as never);
    assert.equal("chat.message" in title, false);
    const chat = await ChatSystem();
    for (const hooks of [[title, chat], [chat, title]]) {
      const output = { system: ["<chat-agent>Conversation policy</chat-agent>", "Other instructions"] };
      for (const hook of hooks) await hook["experimental.chat.system.transform"]({ sessionID: "ses_1" } as never, output);
      assert.match(output.system.join("\n"), /Call session_title with that summary/);
      assert.doesNotMatch(output.system.join("\n"), /Other instructions/);
    }
  });

  it("updates the active top-level session only when the title changes", async () => {
    const updates: unknown[] = [];
    const session = { title: "New session - 2026-09-25T00:00:00.000Z" };
    const client = {
      session: {
        get: async () => ({ data: session }),
        update: async (request: { body: { title: string } }) => {
          updates.push(request);
          session.title = request.body.title;
          return { data: session };
        },
      },
    };
    const plugin = await SessionTitle({ client } as never);
    const context = { sessionID: "ses_1", directory: "/repo" };
    const execute = (title: string) => plugin.tool.session_title.execute({ title }, context as never);

    assert.equal(await execute("  Build   dotfiles  "), "Session title updated");
    assert.equal(await execute("Build dotfiles"), "Session title unchanged");
    assert.equal(await execute("Investigate deployment"), "Session title updated");
    await assert.rejects(execute(" "), /Invalid session title/);
    await assert.rejects(execute("x".repeat(81)), /Invalid session title/);
    assert.deepEqual(updates, ["Build dotfiles", "Investigate deployment"].map((title) => ({
      path: { id: "ses_1" }, query: { directory: "/repo" }, body: { title },
    })));

    Object.assign(session, { parentID: "ses_parent" });
    assert.equal(await execute("Child title"), "Child session title unchanged");
    assert.equal(updates.length, 2);
  });

  it("preserves the existing [Subagent] prefix on initial and revised titles", async () => {
    const original = process.env.HERDR_AGENT_LAYOUT_WORKER;
    const originalHappier = process.env.HERDR_HAPPIER_WORKER;
    try {
      process.env.HERDR_AGENT_LAYOUT_WORKER = "1";
      delete process.env.HERDR_HAPPIER_WORKER;
      const session = { id: "ses_worker", title: "New session - 2026-09-25T00:00:00.000Z" };
      let worker: Awaited<ReturnType<typeof HerdrWorkerTitle>>;
      const client = { session: {
        get: async () => ({ data: session }),
        update: async ({ body }: { body: { title: string } }) => {
          session.title = body.title;
          await worker.event?.({ event: { type: "session.updated", properties: { info: { ...session } } } } as never);
          return { data: session };
        },
      } };
      worker = await HerdrWorkerTitle({ client, directory: "/repo" } as never);
      const title = await SessionTitle({ client, directory: "/repo" } as never);
      await title.tool.session_title.execute({ title: "Review changes" }, { sessionID: session.id, directory: "/repo" } as never);
      assert.equal(session.title, "[Subagent] Review changes");
      await title.tool.session_title.execute({ title: "Investigate deployment" }, { sessionID: session.id, directory: "/repo" } as never);
      assert.equal(session.title, "[Subagent] Investigate deployment");
    } finally {
      if (original === undefined) delete process.env.HERDR_AGENT_LAYOUT_WORKER;
      else process.env.HERDR_AGENT_LAYOUT_WORKER = original;
      if (originalHappier === undefined) delete process.env.HERDR_HAPPIER_WORKER;
      else process.env.HERDR_HAPPIER_WORKER = originalHappier;
    }
  });
});
