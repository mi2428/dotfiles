import { execFile } from "node:child_process";
import { Plugin } from "@opencode/plugin";

const PREFIX = "[Subagent] ";
function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { encoding: "utf8" }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout);
    });
  });
}

const POLICY = `<session-title>
On the first user request in a top-level session, use the model answering this conversation to summarize that first question as a short, specific title in the conversation's language. Call session_title with that summary during your normal response; do not quote or truncate the question, use a separate title-only model call, or mention the title to the user. After that, call session_title only if the main topic substantially changes and the old title becomes misleading, not for follow-ups or brief asides. Never include secrets or sensitive details. Do not call it in child sessions.
</session-title>`;

export const SessionTitle = Plugin.define({
  id: "dotfiles.session-title",
  async setup(ctx) {
    let workerSessionID;
    let happierTitle;
    await ctx.session.hook("context", (event) => {
      event.system.unshift({ type: "text", text: POLICY });
    });
    await ctx.tool.transform((editor) => {
      editor.add({
        name: "session_title",
        description: "Set the current conversation's title. Call once during the first response with an AI summary of the first user question; call again only when the main topic substantially changes.",
        options: { codemode: false },
        input: {
          type: "object",
          properties: {
            title: {
              type: "string",
              minLength: 1,
              maxLength: 80,
              description: "A short, descriptive title without secrets",
            },
          },
          required: ["title"],
          additionalProperties: false,
        },
        async execute({ title }, { sessionID }) {
          if (typeof title !== "string" || !title.trim() || title.length > 80) {
            throw new Error("Invalid session title");
          }
          const current = await ctx.session.get({ sessionID });
          if (current.parentID) return { content: "Child session title unchanged" };

          const normalized = title.replace(/\s+/g, " ").trim();
          const worker = process.env.HERDR_AGENT_LAYOUT_WORKER === "1";
          if (worker && !workerSessionID) {
            if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID || !process.env.HERDR_SOCKET_PATH) {
              throw new Error("Herdr worker pane identity is unavailable");
            }
            const pane = JSON.parse(await run("herdr", ["pane", "get", process.env.HERDR_PANE_ID]));
            const selected = pane?.result?.pane?.agent_session;
            if (selected?.source !== "herdr:opencode" || selected.value !== sessionID) {
              throw new Error("Herdr worker session is not selected in its pane");
            }
            workerSessionID = sessionID;
          }
          if (worker && workerSessionID !== sessionID) return { content: "Other worker session title unchanged" };
          const next = worker && !normalized.startsWith(PREFIX) ? `${PREFIX}${normalized}` : normalized;
          const happierSessionID = worker && process.env.HERDR_HAPPIER_WORKER === "1"
            ? process.env.HAPPIER_SESSION_ID : undefined;
          if (worker && process.env.HERDR_HAPPIER_WORKER === "1" && !happierSessionID) {
            throw new Error("Happier worker session is unavailable");
          }
          const changed = next !== current.title;
          if (changed) await ctx.session.update({ sessionID, title: next });
          if (happierSessionID && next !== happierTitle) {
            await run("happier", ["session", "set-title", happierSessionID, next]);
            happierTitle = next;
          }
          return { content: changed ? "Session title updated" : "Session title unchanged" };
        },
      });
    });
  },
});

export default SessionTitle;
