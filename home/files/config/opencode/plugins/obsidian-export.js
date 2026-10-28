import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { Plugin } from "@opencode/plugin";

const DEFAULT_DIRECTORY = join(homedir(), "obsidian", "OpenCode");

function outputDirectory() {
  const configured = process.env.OPENCODE_OBSIDIAN_DIR?.trim();
  if (!configured) return DEFAULT_DIRECTORY;
  if (configured === "~") return homedir();
  if (configured.startsWith("~/")) return join(homedir(), configured.slice(2));
  return resolve(configured);
}

function safeFileName(title) {
  const normalized = title
    .replace(/[\u0000-\u001f/\\:*?"<>|]/g, "-")
    .replace(/\s+/g, " ")
    .replace(/[. ]+$/g, "")
    .trim();
  return [...(normalized || "OpenCode conversation")].slice(0, 80).join("");
}

function timestamp(date) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
    `${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`,
  ].join(" ");
}

function normalizeTags(tags) {
  return [...new Set(["opencode", ...(tags ?? [])])]
    .map((tag) => tag.trim().replace(/^#+/, "").replace(/\s+/g, "-"))
    .filter(Boolean)
    .slice(0, 6);
}

async function allMessages(session, sessionID) {
  const messages = [];
  let cursor;
  do {
    const page = await session.message.list(
      cursor ? { sessionID, cursor } : { sessionID, order: "asc" },
    );
    messages.push(...page.data);
    cursor = page.cursor.next ?? undefined;
  } while (cursor);
  return messages;
}

function visibleTurns(messages, currentMessageID) {
  const ordered = [...messages].sort(
    (left, right) => (left.time?.created ?? 0) - (right.time?.created ?? 0),
  );
  const currentIndex = ordered.findIndex(({ id }) => id === currentMessageID);
  const boundary = currentIndex >= 0 ? currentIndex : ordered.length;
  let cutoff = -1;
  for (let index = boundary - 1; index >= 0; index -= 1) {
    if (ordered[index].type === "user") {
      cutoff = index;
      break;
    }
  }
  if (cutoff < 0) throw new Error("Could not identify the current /obsidian turn");

  return ordered.slice(0, cutoff).flatMap((message) => {
    if (!["user", "assistant"].includes(message.type)) return [];

    const text = message.type === "user"
      ? message.text.trim()
      : (message.content ?? [])
        .filter((part) => part.type === "text" && part.text.trim())
        .map((part) => part.text)
        .join("\n\n")
        .trim();
    const attachments = message.type === "user"
      ? (message.files ?? [])
        .filter(({ name }) => name)
        .map(({ name }) => `_Attachment: \`${name.replaceAll("`", "\\`")}\`_`)
      : [];
    const content = [text, ...attachments].filter(Boolean).join("\n\n");
    return content ? [{ role: message.type, content }] : [];
  });
}

function renderNote({ title, summary, body, tags, session, exportedAt, turns }) {
  const summaryCallout = summary
    .trim()
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
  const conversation = turns
    .map(({ role, content }) => `### ${role === "user" ? "User" : "Assistant"}\n\n${content}`)
    .join("\n\n");

  return [
    "---",
    `title: ${JSON.stringify(title)}`,
    `created: ${new Date(session.time.created).toISOString()}`,
    `exported: ${exportedAt.toISOString()}`,
    "source: opencode",
    `session: ${JSON.stringify(session.id)}`,
    "tags:",
    ...normalizeTags(tags).map((tag) => `  - ${JSON.stringify(tag)}`),
    "---",
    "",
    `# ${title}`,
    "",
    "> [!summary]",
    summaryCallout,
    body?.trim() ? `\n${body.trim()}` : "",
    "",
    "## Conversation",
    "",
    conversation,
    "",
  ].join("\n");
}

async function writeNewNote(directory, baseName, contents) {
  await mkdir(directory, { recursive: true });
  for (let attempt = 1; attempt <= 100; attempt += 1) {
    const suffix = attempt === 1 ? "" : `-${attempt}`;
    const destination = join(directory, `${baseName}${suffix}.md`);
    try {
      await writeFile(destination, contents, { encoding: "utf8", flag: "wx" });
      return destination;
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
    }
  }
  throw new Error("Could not choose a unique Obsidian note name");
}

export const ObsidianExport = Plugin.define({
  id: "dotfiles.obsidian-export",
  async setup(ctx) {
    await ctx.tool.transform((editor) => {
      editor.add({
        name: "obsidian_export",
        description: "Export the current visible OpenCode conversation and a flexible summary to an Obsidian note.",
        input: {
          type: "object",
          properties: {
            title: { type: "string", minLength: 1, maxLength: 200, description: "A concise note title" },
            summary: { type: "string", minLength: 1, description: "A one-to-three sentence reusable summary" },
            body: {
              type: "string",
              description: "Optional Markdown organized with only the headings useful for this conversation",
            },
            tags: {
              type: "array",
              items: { type: "string" },
              maxItems: 5,
              description: "Optional topic tags",
            },
          },
          required: ["title", "summary"],
          additionalProperties: false,
        },
        async execute(args, context) {
          const [session, messages] = await Promise.all([
            ctx.session.get({ sessionID: context.sessionID }),
            allMessages(ctx.session, context.sessionID),
          ]);
          const turns = visibleTurns(messages, context.messageID);
          if (turns.length === 0) throw new Error("The session has no visible conversation to export");

          const destinationDirectory = outputDirectory();
          const resource = join(destinationDirectory, "*");
          await ctx.permission.assert({
            sessionID: context.sessionID,
            agent: context.agent,
            source: { type: "tool", messageID: context.messageID, id: context.id },
            action: "external_directory",
            resources: [resource],
            save: [resource],
            metadata: { destination: destinationDirectory },
          });

          const exportedAt = new Date();
          const title = args.title.replace(/\s+/g, " ").trim();
          const note = renderNote({ ...args, title, session, exportedAt, turns });
          const destination = await writeNewNote(
            destinationDirectory,
            `${timestamp(exportedAt)} - ${safeFileName(title)}`,
            note,
          );
          return {
            content: `Saved ${turns.length} visible turns to ${destination}`,
            metadata: { destination, turns: turns.length },
          };
        },
      });
    });
  },
});

export default ObsidianExport;
