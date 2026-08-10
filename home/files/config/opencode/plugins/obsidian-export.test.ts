import { strict as assert } from "node:assert";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it } from "bun:test";
import { ObsidianExport } from "./obsidian-export.js";

const variable = "OPENCODE_OBSIDIAN_DIR";
const original = process.env[variable];
const temporaryDirectories: string[] = [];

afterEach(async () => {
  if (original === undefined) delete process.env[variable];
  else process.env[variable] = original;
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("Obsidian conversation export", () => {
  it("writes a flexible note with visible prior turns and never overwrites it", async () => {
    const destination = await mkdtemp(join(tmpdir(), "opencode-obsidian-"));
    temporaryDirectories.push(destination);
    process.env[variable] = destination;

    const messages = [
      {
        info: { id: "user-1", role: "user", time: { created: 1 } },
        parts: [
          { type: "text", text: "Compare both approaches." },
          { type: "file", filename: "design.md" },
        ],
      },
      {
        info: { id: "assistant-1", role: "assistant", parentID: "user-1", time: { created: 2 } },
        parts: [
          { type: "reasoning", text: "private reasoning" },
          { type: "tool", state: { output: "private tool output" } },
          { type: "text", text: "Approach A is smaller." },
          { type: "text", text: "synthetic context", synthetic: true },
        ],
      },
      {
        info: { id: "trigger", role: "user", time: { created: 3 } },
        parts: [{ type: "text", text: "Expanded /obsidian command" }],
      },
      {
        info: { id: "current", role: "assistant", parentID: "trigger", time: { created: 4 } },
        parts: [{ type: "tool", state: { status: "running" } }],
      },
    ];
    const client = {
      session: {
        get: async () => ({
          data: {
            id: "ses_test",
            title: "Session title",
            time: { created: Date.parse("2026-08-10T00:00:00Z") },
          },
        }),
        messages: async () => ({ data: messages }),
      },
    };
    const permissions: unknown[] = [];
    const context = {
      sessionID: "ses_test",
      messageID: "current",
      ask: async (request: unknown) => permissions.push(request),
    };
    const plugin = await ObsidianExport({ client, directory: "/repo" } as never);
    const args = {
      title: "A/B: comparison",
      summary: "Compared two possible approaches.",
      body: "## Recommendation\n\nPrefer A.",
      tags: ["comparison", "design notes"],
    };

    await plugin.tool.obsidian_export.execute(args, context as never);
    await plugin.tool.obsidian_export.execute(args, context as never);

    const files = (await readdir(destination)).sort();
    assert.equal(files.length, 2);
    assert.match(files[0], /^\d{4}-\d{2}-\d{2} \d{6} - A-B- comparison(?:-2)?\.md$/);
    assert.notEqual(files[0], files[1]);
    const note = await readFile(join(destination, files[0]), "utf8");
    assert.match(note, /title: "A\/B: comparison"/);
    assert.match(note, /> \[!summary\]\n> Compared two possible approaches\./);
    assert.match(note, /## Recommendation\n\nPrefer A\./);
    assert.match(note, /### User\n\nCompare both approaches\./);
    assert.match(note, /_Attachment: `design\.md`_/);
    assert.match(note, /### Assistant\n\nApproach A is smaller\./);
    assert.doesNotMatch(note, /private reasoning|private tool output|synthetic context|Expanded \/obsidian/);
    assert.equal(permissions.length, 2);
  });
});
