import { strict as assert } from "node:assert";
import { afterEach, describe, it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({
  Plugin: { define: <T>(plugin: T) => plugin },
}));

const { ProfileShellEnvironment } = await import("./profile-shell-env.js");

const variable = "OPENCODE_CHILD_XDG_CONFIG_HOME";
const original = process.env[variable];

afterEach(() => {
  if (original === undefined) delete process.env[variable];
  else process.env[variable] = original;
});

async function hook() {
  let callback: (event: any) => unknown = () => {};
  await ProfileShellEnvironment.setup({
    shell: {
      hook: async (name: string, value: (event: any) => unknown) => {
        assert.equal(name, "create.before");
        callback = value;
      },
    },
  });
  return callback;
}

describe("profile shell environment", () => {
  it("restores the caller's XDG root for V2 shell creation", async () => {
    process.env[variable] = "/Users/example/.config";
    const event = {
      env: {
        XDG_CONFIG_HOME: "/Users/example/.config/opencode-profiles/slim",
        [variable]: process.env[variable],
      },
    };

    await (await hook())(event);

    assert.equal(ProfileShellEnvironment.id, "dotfiles.profile-shell-env");
    assert.equal(event.env.XDG_CONFIG_HOME, "/Users/example/.config");
    assert.equal(variable in event.env, false);
  });

  it("unsets XDG_CONFIG_HOME when the caller did not define one", async () => {
    delete process.env[variable];
    const event = { env: { XDG_CONFIG_HOME: "/tmp/profile" } };

    await (await hook())(event);

    assert.equal("XDG_CONFIG_HOME" in event.env, false);
  });
});
