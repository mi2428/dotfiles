import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { tool } from "@opencode-ai/plugin";

const DEFAULT_DIRECTORY = join(homedir(), "obsidian", "OpenCode");

function responseData(response, label) {
  if (response?.error) {
    throw new Error(`${label}: ${response.error.message ?? String(response.error)}`);
  }
  const data = response?.data ?? response;
  if (data == null) throw new Error(`${label}: empty response`);
  return data;
}

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

function visibleTurns(messages, currentMessageID) {
  const ordered = [...messages].sort(
    (left, right) => (left.info?.time?.created ?? 0) - (right.info?.time?.created ?? 0),
  );
  const currentIndex = ordered.findIndex(({ info }) => info?.id === currentMessageID);
  const current = currentIndex >= 0 ? ordered[currentIndex] : undefined;
  const parentIndex = current?.info?.parentID
    ? ordered.findIndex(({ info }) => info?.id === current.info.parentID)
    : -1;
  const prior = ordered.slice(0, parentIndex >= 0 ? parentIndex : currentIndex >= 0 ? currentIndex : ordered.length);

  return prior.flatMap(({ info, parts }) => {
    if (!info || !["user", "assistant"].includes(info.role) || info.summary === true) return [];

    const text = (parts ?? [])
      .filter((part) => part.type === "text" && !part.synthetic && !part.ignored && part.text.trim())
      .map((part) => part.text)
      .join("\n\n")
      .trim();
    const attachments = (parts ?? [])
      .filter((part) => part.type === "file" && part.filename)
      .map((part) => `_Attachment: \`${part.filename.replaceAll("`", "\\`")}\`_`);
    const content = [text, ...attachments].filter(Boolean).join("\n\n");
    return content ? [{ role: info.role, content }] : [];
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

export const ObsidianExport = async ({ client, directory }) => ({
  tool: {
    obsidian_export: tool({
      description: "Export the current visible OpenCode conversation and a flexible summary to an Obsidian note.",
      args: {
        title: tool.schema.string().trim().min(1).max(200).describe("A concise note title"),
        summary: tool.schema.string().trim().min(1).describe("A one-to-three sentence reusable summary"),
        body: tool.schema
          .string()
          .optional()
          .describe("Optional Markdown organized with only the headings useful for this conversation"),
        tags: tool.schema.array(tool.schema.string()).max(5).optional().describe("Optional topic tags"),
      },
      async execute(args, context) {
        const [sessionResponse, messagesResponse] = await Promise.all([
          client.session.get({ path: { id: context.sessionID }, query: { directory } }),
          client.session.messages({ path: { id: context.sessionID }, query: { directory } }),
        ]);
        const session = responseData(sessionResponse, "Failed to read the OpenCode session");
        const messages = responseData(messagesResponse, "Failed to read the OpenCode conversation");
        const turns = visibleTurns(messages, context.messageID);
        if (turns.length === 0) throw new Error("The session has no visible conversation to export");

        const destinationDirectory = outputDirectory();
        await context.ask({
          permission: "external_directory",
          patterns: [destinationDirectory],
          always: [join(destinationDirectory, "**")],
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
          title: "Obsidian note exported",
          output: `Saved ${turns.length} visible turns to ${destination}`,
          metadata: { destination, turns: turns.length },
        };
      },
    }),
  },
});

export default ObsidianExport;
