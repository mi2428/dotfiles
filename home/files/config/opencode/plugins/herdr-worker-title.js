import { execFile } from "node:child_process";
import { Plugin } from "@opencode/plugin";

const PREFIX = "[Subagent] ";
const HERDR_ENVIRONMENT = ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID"];

function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { encoding: "utf8" }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout);
    });
  });
}

export const HerdrWorkerTitle = Plugin.define({
  id: "dotfiles.herdr-worker-title",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      if (process.env.HERDR_AGENT_LAYOUT_WORKER === "1") return;
      // V2 shell hooks do not identify sessions, so shared servers must not reuse pane credentials.
      for (const variable of HERDR_ENVIRONMENT) delete event.env[variable];
    });

    if (process.env.HERDR_AGENT_LAYOUT_WORKER !== "1") return;

    const happierSessionId = process.env.HERDR_HAPPIER_WORKER === "1"
      ? process.env.HAPPIER_SESSION_ID
      : undefined;
    let lastHappierTitle;
    const controller = new AbortController();

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({
          types: ["session.renamed"],
          signal: controller.signal,
        })) {
          const { sessionID, title: originalTitle } = event.data;
          if (!sessionID || typeof originalTitle !== "string" || originalTitle.startsWith("New session - ")) {
            continue;
          }

          const title = originalTitle.startsWith(PREFIX)
            ? originalTitle
            : `${PREFIX}${originalTitle}`;

          if (title !== originalTitle) {
            await ctx.session.update({ sessionID, title });
          }

          if (happierSessionId && title !== lastHappierTitle) {
            await run("happier", ["session", "set-title", happierSessionId, title]);
            lastHappierTitle = title;
          }
        }
      } catch (error) {
        if (!controller.signal.aborted) console.error("Herdr title event subscription failed", error);
      }
    })();

    return () => controller.abort();
  },
});

export default HerdrWorkerTitle;
