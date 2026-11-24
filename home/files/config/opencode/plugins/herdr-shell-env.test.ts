import { strict as assert } from "node:assert";
import { it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({ Plugin: { define: <T>(plugin: T) => plugin } }));
const { HerdrShellEnv } = await import("./herdr-shell-env.js");

async function hook() {
  let before: (event: { env: Record<string, string> }) => void = () => {};
  await HerdrShellEnv.setup({ shell: { hook: async (_name: string, callback: typeof before) => { before = callback; } } });
  return before;
}

it("scrubs pane credentials and unknown future Herdr keys", async () => {
  const before = await hook();
  const shell = { env: {
    HERDR_ENV: "1", HERDR_PANE_ID: "wrong:pane", HERDR_SOCKET_PATH: "wrong.sock",
    HERDR_FUTURE_MARKER: "wrong", HC_TERMINAL_ID: "wrong",
    OPENCODE_HERDR_VIEWER: "1", OPENCODE_HERDR_SESSION: "wrong", PATH: "/bin",
  } };
  before(shell);
  assert.deepEqual(shell.env, { PATH: "/bin" });
});
