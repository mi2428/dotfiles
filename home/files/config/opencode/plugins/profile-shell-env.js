import { Plugin } from "@opencode/plugin";

const CHILD_XDG_CONFIG_HOME = "OPENCODE_CHILD_XDG_CONFIG_HOME";

export const ProfileShellEnvironment = Plugin.define({
  id: "dotfiles.profile-shell-env",
  async setup(ctx) {
    await ctx.shell.hook("create.before", (event) => {
      const childConfigHome = process.env[CHILD_XDG_CONFIG_HOME]?.trim();
      if (childConfigHome) {
        event.env.XDG_CONFIG_HOME = childConfigHome;
      } else {
        delete event.env.XDG_CONFIG_HOME;
      }
      delete event.env[CHILD_XDG_CONFIG_HOME];
    });
  },
});

export default ProfileShellEnvironment;
