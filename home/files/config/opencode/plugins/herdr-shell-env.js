import { Plugin } from "@opencode/plugin";

export const HerdrShellEnv = Plugin.define({
  id: "dotfiles.herdr-shell-env",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      // Hooks lack session IDs and may activate after the first shell; the server must start without pane credentials.
      for (const variable of Object.keys(event.env)) {
        if (!variable.startsWith("HERDR_") && !variable.startsWith("OPENCODE_HERDR_") && variable !== "HC_TERMINAL_ID") continue;
        delete event.env[variable];
      }
    });

  },
});

export default HerdrShellEnv;
