import { strict as assert } from "node:assert";
import { afterEach, describe, it } from "bun:test";
import { ProfileShellEnvironment } from "./profile-shell-env.js";

const variable = "OPENCODE_CHILD_XDG_CONFIG_HOME";
const original = process.env[variable];

afterEach(() => {
  if (original === undefined) delete process.env[variable];
  else process.env[variable] = original;
});

describe("profile shell environment", () => {
  it("restores the caller's XDG root for agent shell commands", async () => {
    process.env[variable] = "/Users/example/.config";
    const hooks = await ProfileShellEnvironment();
    const output = {
      env: {
        XDG_CONFIG_HOME: "/Users/example/.config/opencode-profiles/slim",
        [variable]: process.env[variable],
      },
    };

    await hooks["shell.env"]({}, output);

    assert.equal(output.env.XDG_CONFIG_HOME, "/Users/example/.config");
    assert.equal(variable in output.env, false);
  });

  it("unsets XDG_CONFIG_HOME when the caller did not define one", async () => {
    delete process.env[variable];
    const hooks = await ProfileShellEnvironment();
    const output = { env: { XDG_CONFIG_HOME: "/tmp/profile" } };

    await hooks["shell.env"]({}, output);

    assert.equal("XDG_CONFIG_HOME" in output.env, false);
  });
});
