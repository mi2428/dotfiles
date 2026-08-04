const CHILD_XDG_CONFIG_HOME = "OPENCODE_CHILD_XDG_CONFIG_HOME";

export const ProfileShellEnvironment = async () => ({
  "shell.env": async (_input, output) => {
    const childConfigHome = process.env[CHILD_XDG_CONFIG_HOME]?.trim();
    if (childConfigHome) {
      output.env.XDG_CONFIG_HOME = childConfigHome;
    } else {
      delete output.env.XDG_CONFIG_HOME;
    }
    delete output.env[CHILD_XDG_CONFIG_HOME];
  },
});

export default ProfileShellEnvironment;
