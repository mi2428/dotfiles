import { strict as assert } from "node:assert";
import { afterEach, it, mock } from "bun:test";

mock.module("@opencode/plugin", () => ({ Plugin: { define: <T>(plugin: T) => plugin } }));
const { HerdrShellEnv } = await import("./herdr-shell-env.js");
const markers = ["HERDR_AGENT_LAYOUT_WORKER", "HERDR_HAPPIER_WORKER"] as const;
const original = Object.fromEntries(markers.map((key) => [key, process.env[key]]));
afterEach(() => {
  for (const key of markers) {
    if (original[key] === undefined) delete process.env[key];
    else process.env[key] = original[key];
  }
});

async function hook() {
  let before: (event: { env: Record<string, string> }) => void = () => {};
  await HerdrShellEnv.setup({ shell: { hook: async (_name: string, callback: typeof before) => { before = callback; } } });
  return before;
}

it("scrubs pane credentials and unknown future Herdr keys", async () => {
  delete process.env.HERDR_AGENT_LAYOUT_WORKER;
  delete process.env.HERDR_HAPPIER_WORKER;
  const before = await hook();
  const shell = { env: {
    HERDR_ENV: "1", HERDR_PANE_ID: "wrong:pane", HERDR_SOCKET_PATH: "wrong.sock",
    HERDR_FUTURE_MARKER: "wrong", HERDR_HAPPIER_WORKER: "1", PATH: "/bin",
  } };
  before(shell);
  assert.deepEqual(shell.env, { PATH: "/bin" });
});

it("preserves only matching noncredential worker identity booleans", async () => {
  process.env.HERDR_AGENT_LAYOUT_WORKER = "1";
  process.env.HERDR_HAPPIER_WORKER = "1";
  const before = await hook();
  const shell = { env: {
    HERDR_AGENT_LAYOUT_WORKER: "1", HERDR_HAPPIER_WORKER: "1", HERDR_ENV: "1",
    HERDR_PANE_ID: "worker:pane", HERDR_SOCKET_PATH: "worker.sock", PATH: "/bin",
  } };
  before(shell);
  assert.deepEqual(shell.env, { HERDR_AGENT_LAYOUT_WORKER: "1", HERDR_HAPPIER_WORKER: "1", PATH: "/bin" });
  const unrelated = { env: { HERDR_AGENT_LAYOUT_WORKER: "0", HERDR_HAPPIER_WORKER: "other", PATH: "/bin" } };
  before(unrelated);
  assert.deepEqual(unrelated.env, { PATH: "/bin" });
});
