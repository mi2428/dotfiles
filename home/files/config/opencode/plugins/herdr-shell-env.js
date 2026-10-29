import { Plugin } from "@opencode/plugin";

const WORKER_MARKERS = ["HERDR_HAPPIER_WORKER", "HERDR_AGENT_LAYOUT_WORKER"];

export const HerdrShellEnv = Plugin.define({
  id: "dotfiles.herdr-shell-env",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      // Hooks lack session IDs and may activate after the first shell; the server must start without pane credentials.
      for (const variable of Object.keys(event.env)) {
        if (!variable.startsWith("HERDR_")) continue;
        if (WORKER_MARKERS.includes(variable) && process.env[variable] === "1" && event.env[variable] === "1") continue;
        delete event.env[variable];
      }
    });

  },
});

export default HerdrShellEnv;
