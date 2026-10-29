import { strict as assert } from "node:assert";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));

const { ObsidianExport } = await import("./obsidian-export.js");

const variable = "OPENCODE_OBSIDIAN_DIR";
const original = process.env[variable];
const temporaryDirectories: string[] = [];

afterEach(async () => {
  if (original === undefined) delete process.env[variable];
  else process.env[variable] = original;
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("Obsidian conversation export", () => {
  it("asks before writing a unique note with only visible V2 turns", async () => {
    const destination = await mkdtemp(join(tmpdir(), "opencode-obsidian-"));
    temporaryDirectories.push(destination);
    process.env[variable] = destination;

    const messages = [
      {
        id: "user-1",
        type: "user",
        time: { created: 1 },
        text: "Compare both approaches.",
        files: [{ name: "design.md", data: "", mime: "text/markdown", source: { type: "file" } }],
      },
      {
        id: "assistant-1",
        type: "assistant",
        time: { created: 2 },
        agent: "build",
        model: { providerID: "test", id: "test" },
        content: [
          { type: "reasoning", text: "private reasoning" },
          { type: "tool", id: "tool-1", name: "read", state: { status: "completed" }, time: { created: 2 } },
          { type: "text", text: "Approach A is smaller." },
        ],
      },
      { id: "system-1", type: "system", time: { created: 2.5 }, text: "synthetic context" },
      { id: "trigger", type: "user", time: { created: 3 }, text: "Expanded /obsidian command" },
      {
        id: "current",
        type: "assistant",
        time: { created: 4 },
        agent: "build",
        model: { providerID: "test", id: "test" },
        content: [{ type: "tool", id: "tool-2", name: "obsidian_export", state: { status: "running" }, time: { created: 4 } }],
      },
    ];
    const permissions: unknown[] = [];
    let allow = false;
    const tools: Record<string, any> = {};
    const ctx = {
      session: {
        get: async () => ({
          id: "ses_test",
          title: "Session title",
          time: { created: Date.parse("2026-08-10T00:00:00Z") },
        }),
        message: { list: async () => ({ data: messages, cursor: {} }) },
      },
      permission: {
        assert: async (request: unknown) => {
          permissions.push(request);
          if (!allow) throw new Error("Permission denied");
        },
      },
      tool: {
        transform: async (transform: (editor: unknown) => void) => transform({
          add: (tool: { name: string }) => { tools[tool.name] = tool; },
        }),
      },
    };
    await ObsidianExport.setup(ctx);
    assert.equal(tools.obsidian_export.options.codemode, false);
    const args = {
      title: "A/B: comparison",
      summary: "Compared two possible approaches.",
      body: "## Recommendation\n\nPrefer A.",
      tags: ["comparison", "design notes"],
    };
    const context = {
      sessionID: "ses_test",
      messageID: "current",
      agent: "build",
      id: "call_1",
    };

    assert.equal(ObsidianExport.id, "dotfiles.obsidian-export");
    assert.equal(tools.obsidian_export.input.additionalProperties, false);
    await assert.rejects(tools.obsidian_export.execute(args, context), /Permission denied/);
    assert.deepEqual(await readdir(destination), []);

    allow = true;
    const first = await tools.obsidian_export.execute(args, context);
    await tools.obsidian_export.execute(args, context);

    const files = (await readdir(destination)).sort();
    assert.equal(files.length, 2);
    assert.match(files[0], /^\d{4}-\d{2}-\d{2} \d{6} - A-B- comparison(?:-2)?\.md$/);
    assert.notEqual(files[0], files[1]);
    assert.match(first.content, /Saved 2 visible turns to /);
    const note = await readFile(join(destination, files[0]), "utf8");
    assert.match(note, /title: "A\/B: comparison"/);
    assert.match(note, /> \[!summary\]\n> Compared two possible approaches\./);
    assert.match(note, /## Recommendation\n\nPrefer A\./);
    assert.match(note, /### User\n\nCompare both approaches\./);
    assert.match(note, /_Attachment: `design\.md`_/);
    assert.match(note, /### Assistant\n\nApproach A is smaller\./);
    assert.doesNotMatch(note, /private reasoning|private tool output|synthetic context|Expanded \/obsidian/);
    assert.equal(permissions.length, 3);
    assert.deepEqual(permissions[0], {
      sessionID: "ses_test",
      agent: "build",
      source: { type: "tool", messageID: "current", id: "call_1" },
      action: "external_directory",
      resources: [join(destination, "*")],
      save: [join(destination, "*")],
      metadata: { destination },
    });
  });

  it("paginates the full history across a compaction checkpoint", async () => {
    const destination = await mkdtemp(join(tmpdir(), "opencode-obsidian-pages-"));
    temporaryDirectories.push(destination);
    process.env[variable] = destination;
    const messages = [
      { id: "before-user", type: "user", time: { created: 1 }, text: "Before checkpoint" },
      {
        id: "before-assistant",
        type: "assistant",
        time: { created: 2 },
        agent: "build",
        model: { providerID: "test", id: "test" },
        content: [{ type: "text", text: "Still visible before checkpoint" }],
      },
      {
        id: "checkpoint",
        type: "compaction",
        status: "completed",
        time: { created: 3 },
        summary: "Checkpoint summary must stay hidden",
      },
      ...Array.from({ length: 101 }, (_, index) => ({
        id: `after-${index}`,
        type: "user",
        time: { created: index + 4 },
        text: `After checkpoint ${index}`,
      })),
      { id: "trigger", type: "user", time: { created: 105 }, text: "Expanded /obsidian command" },
      {
        id: "current",
        type: "assistant",
        time: { created: 106 },
        agent: "build",
        model: { providerID: "test", id: "test" },
        content: [{ type: "tool", id: "tool", name: "obsidian_export", state: { status: "running" }, time: { created: 106 } }],
      },
    ];
    const requests: unknown[] = [];
    const tools: Record<string, any> = {};
    await ObsidianExport.setup({
      session: {
        get: async () => ({ id: "ses_long", time: { created: Date.parse("2026-08-10T00:00:00Z") } }),
        message: {
          list: async (input: { cursor?: string }) => {
            requests.push(input);
            return input.cursor
              ? { data: messages.slice(100), cursor: { previous: "page-1" } }
              : { data: messages.slice(0, 100), cursor: { next: "page-2" } };
          },
        },
      },
      permission: { assert: async () => {} },
      tool: {
        transform: async (transform: (editor: unknown) => void) => transform({
          add: (tool: { name: string }) => { tools[tool.name] = tool; },
        }),
      },
    });

    const result = await tools.obsidian_export.execute(
      { title: "Long conversation", summary: "Full history." },
      { sessionID: "ses_long", messageID: "current", agent: "build", id: "call_long" },
    );

    assert.deepEqual(requests, [
      { sessionID: "ses_long", order: "asc" },
      { sessionID: "ses_long", cursor: "page-2" },
    ]);
    assert.match(result.content, /Saved 103 visible turns to /);
    const [file] = await readdir(destination);
    const note = await readFile(join(destination, file), "utf8");
    assert.match(note, /Before checkpoint/);
    assert.match(note, /After checkpoint 100/);
    assert.doesNotMatch(note, /Checkpoint summary must stay hidden|Expanded \/obsidian command/);
  });

  it("cuts at the latest user turn when the current assistant message is missing", async () => {
    const destination = await mkdtemp(join(tmpdir(), "opencode-obsidian-boundary-"));
    temporaryDirectories.push(destination);
    process.env[variable] = destination;
    let messages = [
      { id: "prior-user", type: "user", time: { created: 1 }, text: "Prior question" },
      {
        id: "prior-assistant",
        type: "assistant",
        time: { created: 2 },
        agent: "build",
        model: { providerID: "test", id: "test" },
        content: [{ type: "text", text: "Prior answer" }],
      },
      { id: "trigger", type: "user", time: { created: 3 }, text: "Expanded /obsidian command" },
    ];
    let permissionChecks = 0;
    const tools: Record<string, any> = {};
    await ObsidianExport.setup({
      session: {
        get: async () => ({ id: "ses_boundary", time: { created: Date.parse("2026-08-10T00:00:00Z") } }),
        message: { list: async () => ({ data: messages, cursor: {} }) },
      },
      permission: { assert: async () => { permissionChecks += 1; } },
      tool: {
        transform: async (transform: (editor: unknown) => void) => transform({
          add: (tool: { name: string }) => { tools[tool.name] = tool; },
        }),
      },
    });
    const args = { title: "Boundary", summary: "Safe boundary." };
    const context = {
      sessionID: "ses_boundary",
      messageID: "missing-current-assistant",
      agent: "build",
      id: "call_boundary",
    };

    const result = await tools.obsidian_export.execute(args, context);
    assert.match(result.content, /Saved 2 visible turns to /);
    const [file] = await readdir(destination);
    const note = await readFile(join(destination, file), "utf8");
    assert.match(note, /Prior question/);
    assert.match(note, /Prior answer/);
    assert.doesNotMatch(note, /Expanded \/obsidian command/);

    messages = [{
      id: "assistant-only",
      type: "assistant",
      time: { created: 1 },
      agent: "build",
      model: { providerID: "test", id: "test" },
      content: [{ type: "text", text: "No user boundary" }],
    }];
    await assert.rejects(
      tools.obsidian_export.execute(args, context),
      /Could not identify the current \/obsidian turn/,
    );
    assert.equal(permissionChecks, 1);
  });
});
