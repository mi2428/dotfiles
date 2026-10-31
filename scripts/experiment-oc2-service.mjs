import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import path from "node:path";

const binary = process.env.OPENCODE_V2_BIN;
const parent = process.env.OPENCODE_EXPERIMENT_ROOT;
if (!binary || !parent || !path.isAbsolute(binary) || !path.isAbsolute(parent)) {
  throw new Error("Set absolute OPENCODE_V2_BIN and OPENCODE_EXPERIMENT_ROOT");
}

const scratch = await mkdtemp(path.join(parent, "oc2-service-"));
const pluginDir = path.join(scratch, "rpc-probe");
await mkdir(pluginDir);
await writeFile(path.join(pluginDir, "package.json"), JSON.stringify({
  name: "oc2-herdr-rpc-probe", type: "module", exports: { ".": "./index.mjs" },
}));
await writeFile(path.join(pluginDir, "index.mjs"), `
import { Plugin } from "@opencode/plugin";
import { Rpc } from "@opencode/plugin/rpc";
const Probe = Rpc.define({
  id: "herdr-probe",
  events: {},
  methods: { claim: {
    input: { type: "object", properties: { paneID: { type: "string" } }, required: ["paneID"], additionalProperties: false },
    output: { type: "object", properties: { paneID: { type: "string" } }, required: ["paneID"], additionalProperties: false },
  } },
});
export default Plugin.define({
  id: "herdr-probe-plugin",
  async setup(ctx) {
    await ctx.rpc.register(Probe, { claim: async (input) => ({ paneID: input.paneID }) });
  },
});
`);
const env = {
  ...process.env,
  HOME: scratch,
  XDG_CONFIG_HOME: path.join(scratch, "config"),
  XDG_DATA_HOME: path.join(scratch, "data"),
  XDG_CACHE_HOME: path.join(scratch, "cache"),
  XDG_STATE_HOME: path.join(scratch, "state"),
  OPENCODE_DB: ":memory:",
  OPENCODE_CONFIG_CONTENT: JSON.stringify({
    plugins: [{ package: pluginDir }],
    permissions: [{ action: "shell", resource: "*", effect: "ask" }],
  }),
  OPENCODE_DISABLE_PROJECT_CONFIG: "1",
  OPENCODE_DISABLE_EXTERNAL_SKILLS: "1",
  OPENCODE_DISABLE_CLAUDE_CODE_SKILLS: "1",
  OPENCODE_PASSWORD: randomBytes(32).toString("base64url"),
};
for (const key of Object.keys(env)) {
  if (key.startsWith("HERDR_") || key.startsWith("HAPPIER_")) delete env[key];
}
await Promise.all(["config", "data", "cache", "state"].map((name) => mkdir(path.join(scratch, name))));

let server;
let managed;
let tui;
const rssMiB = (pid) => {
  const result = spawnSync("ps", ["-o", "rss=", "-p", String(pid)], { encoding: "utf8" });
  return result.status === 0 ? Math.round(Number(result.stdout.trim()) / 1024) : null;
};
async function waitFor(predicate, timeout = 10000) {
  const until = Date.now() + timeout;
  while (Date.now() < until) {
    const result = await predicate();
    if (result) return result;
    await new Promise((resolve) => setTimeout(resolve, 80));
  }
  throw new Error("Timed out waiting for an isolated OC2 server event");
}

async function startServer() {
  const startedAt = Date.now();
  const child = spawn(binary, ["serve", "--stdio", "--port", "0"], {
    cwd: scratch,
    env,
    stdio: ["pipe", "pipe", "pipe"],
  });
  let output = "";
  const ready = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("OC2 service readiness timed out")), 10000);
    child.stdout.on("data", (buffer) => {
      output += buffer.toString();
      const newline = output.indexOf("\n");
      if (newline === -1) return;
      try {
        const parsed = new URL(JSON.parse(output.slice(0, newline)).url);
        assert.equal(parsed.protocol, "http:");
        assert.equal(parsed.hostname, "127.0.0.1");
        clearTimeout(timeout);
        resolve(parsed);
      } catch (error) { clearTimeout(timeout); reject(error); }
      child.stdout.removeAllListeners("data");
      child.stdout.resume();
    });
    child.once("error", (error) => { clearTimeout(timeout); reject(error); });
    child.once("exit", () => { clearTimeout(timeout); reject(new Error("OC2 service exited before readiness")); });
  });
  let url;
  try { url = await ready; } catch (error) { child.stdin.end(); child.kill("SIGTERM"); throw error; }
  return { child, url, readyMs: Date.now() - startedAt };
}

async function startManagedServer() {
  const startedAt = Date.now();
  const probe = createServer();
  await new Promise((resolve) => probe.listen(0, "127.0.0.1", resolve));
  const port = probe.address().port;
  await new Promise((resolve) => probe.close(resolve));
  const child = spawn(binary, ["serve", "--hostname", "127.0.0.1", "--port", String(port)], {
    cwd: scratch,
    env,
    stdio: ["ignore", "ignore", "ignore"],
  });
  const url = new URL(`http://127.0.0.1:${port}/`);
  try {
    await waitFor(async () => {
      try { return (await request(url, "/api/info")).ok; } catch { return false; }
    });
  } catch (error) { child.kill("SIGTERM"); throw error; }
  return { child, url, readyMs: Date.now() - startedAt };
}

function stopTui() {
  if (!tui || tui.exitCode !== null || tui.signalCode !== null) return;
  try { process.kill(-tui.pid, "SIGTERM"); } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
}

function request(url, route, method = "GET", body, authenticated = true) {
  return fetch(new URL(route, url), {
    method,
    headers: {
      ...(authenticated ? { Authorization: `Basic ${Buffer.from(`opencode:${env.OPENCODE_PASSWORD}`).toString("base64")}` } : {}),
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

async function json(url, route, method, body) {
  const response = await request(url, route, method, body);
  if (!response.ok) throw new Error(`${method ?? "GET"} ${route}: HTTP ${response.status}`);
  return response.status === 204 ? undefined : response.json();
}

try {
  server = await startServer();
  const { url } = server;
  const privateStartup = { readyMs: server.readyMs, rssMiB: rssMiB(server.child.pid) };
  const unauthenticated = await request(url, "/api/info", "GET", undefined, false);
  assert.equal(unauthenticated.status, 401);
  await json(url, "/api/location");
  let pluginSnapshot = [];
  try {
    await waitFor(async () => {
      const plugins = (await json(url, "/api/plugin")).data;
      pluginSnapshot = plugins.filter(({ id }) => id === "herdr-probe-plugin");
      return plugins.some((item) => item.id === "herdr-probe-plugin" && item.state.status === "active");
    });
  } catch {
    throw new Error(`Isolated RPC plugin did not activate: ${JSON.stringify(pluginSnapshot)}`);
  }
  const rpcPath = "/api/rpc/herdr-probe/claim";
  const rpcDenied = await request(url, rpcPath, "POST", { input: { paneID: "other-pane" } }, false);
  assert.equal(rpcDenied.status, 401);
  const rpcAccepted = await json(url, rpcPath, "POST", { input: { paneID: "other-pane" } });
  assert.equal(rpcAccepted.output?.paneID, "other-pane");

  const first = (await json(url, "/api/session", "POST", { title: "isolated-A" })).data.id;
  const second = (await json(url, "/api/session", "POST", { title: "isolated-B" })).data.id;
  await json(url, `/api/session/${first}/environment`, "PUT", {
    variables: { PATH: env.PATH, HOME: scratch, HERDR_ENV: "1", HERDR_PANE_ID: "test:pane" },
  });
  const markerCommand = `node -e 'console.log("herdr=" + (process.env.HERDR_ENV || "missing"))'; exec sleep 8`;
  const firstShellRequest = json(url, `/api/session/${first}/shell`, "POST", { command: markerCommand });
  const secondShellRequest = json(url, `/api/session/${second}/shell`, "POST", { command: markerCommand });
  const running = await waitFor(async () => {
    const shells = (await json(url, "/api/shell")).data;
    return shells.length >= 2 ? shells : undefined;
  });
  const shellA = running.find((item) => item.metadata?.sessionID === first);
  const shellB = running.find((item) => item.metadata?.sessionID === second);
  assert(shellA && shellB, "shell metadata must identify the owning session");
  const outputA = await waitFor(async () => {
    const output = (await json(url, `/api/shell/${shellA.id}/output`)).data.output;
    return output.includes("herdr=") ? output : undefined;
  });
  const outputB = await waitFor(async () => {
    const output = (await json(url, `/api/shell/${shellB.id}/output`)).data.output;
    return output.includes("herdr=") ? output : undefined;
  });
  assert.match(outputA, /herdr=1/);
  assert.match(outputB, /herdr=missing/);

  const interrupt = await json(url, `/api/session/${first}/interrupt`, "POST");
  const afterInterrupt = (await json(url, "/api/shell")).data;
  const aAfterInterrupt = afterInterrupt.some((item) => item.id === shellA.id);
  const bAfterInterrupt = afterInterrupt.some((item) => item.id === shellB.id);
  await json(url, `/api/shell/${shellA.id}`, "DELETE");
  const afterRemove = (await json(url, "/api/shell")).data;
  assert(!afterRemove.some((item) => item.id === shellA.id));
  assert(afterRemove.some((item) => item.id === shellB.id));
  await json(url, `/api/shell/${shellB.id}`, "DELETE");
  await Promise.all([firstShellRequest, secondShellRequest]);

  // A shell command started through the API is not necessarily an agent-loop tool call.
  console.log(JSON.stringify({
    authWithoutPassword: unauthenticated.status,
    rpcWithoutPassword: rpcDenied.status,
    authenticatedRpcCanClaimAnotherPane: rpcAccepted.output?.paneID === "other-pane",
    distinctShellOwners: true,
    sessionEnvironmentIsolated: /herdr=1/.test(outputA) && /herdr=missing/.test(outputB),
    sessionInterruptReported: interrupt.data?.interrupted ?? interrupt.interrupted ?? null,
    shellAStillRunningAfterInterrupt: aAfterInterrupt,
    shellBStillRunningAfterInterrupt: bAfterInterrupt,
    removingAStoppedB: !afterRemove.some((item) => item.id === shellB.id),
    privateServer: privateStartup,
  }));

  const leaseShellRequest = json(url, `/api/session/${first}/shell`, "POST", { command: "exec sleep 8" })
    .catch(() => undefined);
  const leasedShell = await waitFor(async () => {
    const shells = (await json(url, "/api/shell")).data;
    return shells.find((item) => item.metadata?.sessionID === first);
  });
  const treeShellRequest = json(url, `/api/session/${first}/shell`, "POST", {
    command: `node -e 'const {spawn}=require("node:child_process"); const child=spawn("/bin/sleep",["8"],{stdio:"ignore"}); console.log("child_pid="+child.pid); setTimeout(()=>{},8000)'`,
  }).catch(() => undefined);
  const treeShell = await waitFor(async () => {
    const shells = (await json(url, "/api/shell")).data;
    return shells.find((item) => item.metadata?.sessionID === first && item.id !== leasedShell.id);
  });
  const childOutput = await waitFor(async () => {
    const output = (await json(url, `/api/shell/${treeShell.id}/output`)).data.output;
    return output.includes("child_pid=") ? output : undefined;
  });
  const childPID = Number(childOutput.match(/child_pid=(\d+)/)?.[1]);
  assert(Number.isInteger(childPID) && childPID > 1);
  const detachedRequest = json(url, `/api/session/${first}/shell`, "POST", {
    command: `node -e 'const {spawn}=require("node:child_process"); const child=spawn("/bin/sleep",["8"],{stdio:"ignore",detached:true}); child.unref(); console.log("detached_pid="+child.pid); setTimeout(()=>{},8000)'`,
  }).catch(() => undefined);
  const detachedShell = await waitFor(async () => {
    const shells = (await json(url, "/api/shell")).data;
    return shells.find((item) => item.metadata?.sessionID === first && item.id !== leasedShell.id && item.id !== treeShell.id);
  });
  const detachedOutput = await waitFor(async () => {
    const output = (await json(url, `/api/shell/${detachedShell.id}/output`)).data.output;
    return output.includes("detached_pid=") ? output : undefined;
  });
  const detachedPID = Number(detachedOutput.match(/detached_pid=(\d+)/)?.[1]);
  assert(Number.isInteger(detachedPID) && detachedPID > 1);
  const closedAt = Date.now();
  const exited = new Promise((resolve) => server.child.once("exit", resolve));
  server.child.stdin.end();
  const stopped = await Promise.race([
    exited.then(() => true),
    new Promise((resolve) => setTimeout(() => resolve(false), 5000)),
  ]);
  assert(stopped, "private server should close when its ownership lease ends");
  let shellAlive = false;
  try { process.kill(leasedShell.pid, 0); shellAlive = true; } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
  const detachedState = spawnSync("ps", ["-o", "stat=", "-p", String(detachedPID)], { encoding: "utf8" }).stdout.trim() || "absent";
  console.log(JSON.stringify({
    privateServerExitedAfterLeaseMs: Date.now() - closedAt,
    shellProcessAliveOnServerExit: shellAlive,
    nonDetachedChildStateAfterLease: spawnSync("ps", ["-o", "stat=", "-p", String(childPID)], { encoding: "utf8" }).stdout.trim() || "absent",
    detachedChildStateAfterLease: detachedState,
  }));
  if (detachedState !== "absent") {
    const command = spawnSync("ps", ["-o", "command=", "-p", String(detachedPID)], { encoding: "utf8" }).stdout.trim();
    if (/(?:\/bin\/)?sleep 8$/.test(command)) process.kill(detachedPID, "SIGTERM");
  }
  await Promise.all([leaseShellRequest, treeShellRequest, detachedRequest]);

  managed = await startManagedServer();
  await json(managed.url, "/api/location");
  await waitFor(async () => (await json(managed.url, "/api/plugin")).data
    .some((item) => item.id === "herdr-probe-plugin" && item.state.status === "active"), 20000);
  const managedSession = (await json(managed.url, "/api/session", "POST", { title: "tui-disconnect" })).data.id;
  const permission = (await json(managed.url, `/api/session/${managedSession}/permission`, "POST", {
    action: "shell", resources: ["test-only"],
  })).data;
  const pendingBeforeTui = (await json(managed.url, `/api/session/${managedSession}/permission`)).data;
  assert(pendingBeforeTui.some((item) => item.id === permission.id));
  let managedShellError;
  const managedShellRequest = json(managed.url, `/api/session/${managedSession}/shell`, "POST", {
    command: `node -e 'console.log("herdr=" + (process.env.HERDR_ENV || "missing") + " auth=" + (process.env.OPENCODE_PASSWORD ? "present" : "absent"))'; exec sleep 20`,
  }).catch((error) => { managedShellError = error; });
  const managedShell = await waitFor(async () => {
    const shells = (await json(managed.url, "/api/shell")).data;
    return shells.find((item) => item.metadata?.sessionID === managedSession);
  });
  const shellOutput = await waitFor(async () => {
    const output = (await json(managed.url, `/api/shell/${managedShell.id}/output`)).data.output;
    return output.includes("herdr=") ? output : undefined;
  });
  assert.match(shellOutput, /herdr=missing/);
  assert.match(shellOutput, /auth=present/);
  let renderedBytes = 0;
  let tuiFrame = "";
  const ptyBridge = `
import fcntl, os, pty, select, signal, struct, sys, termios
pid, master = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 110, 0, 0))
    os.execv(sys.argv[1], sys.argv[1:])
def stop(_signal, _frame):
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
while True:
    try: readable, _, _ = select.select([master, sys.stdin.fileno()], [], [], 0.2)
    except InterruptedError: continue
    if master in readable:
        try: data = os.read(master, 4096)
        except OSError: break
        if not data: break
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    if sys.stdin.fileno() in readable:
        data = os.read(sys.stdin.fileno(), 4096)
        if not data: stop(None, None); break
        os.write(master, data)
    if os.waitpid(pid, os.WNOHANG)[0] == pid: break
stop(None, None)
`;
  tui = spawn("python3", ["-c", ptyBridge, binary, "--server", managed.url.href], {
    cwd: scratch,
    env: { ...env, TERM: "xterm-256color", HERDR_ENV: "1", HERDR_PANE_ID: "test:pane",
      HERDR_SOCKET_PATH: "test-only.sock" },
    stdio: ["pipe", "pipe", "pipe"],
    detached: true,
  });
  tui.stdout.on("data", (chunk) => {
    renderedBytes += chunk.length;
    if (tuiFrame.length < 8192) tuiFrame += chunk.toString().slice(0, 8192 - tuiFrame.length);
  });
  let tuiError = "";
  tui.stderr.on("data", (chunk) => { tuiError += chunk.toString().slice(0, 300); });
  try { await waitFor(() => renderedBytes >= 1200 && tui.exitCode === null, 12000); }
  catch { throw new Error(`TUI did not render: exit=${tui.exitCode} bytes=${renderedBytes} stderr=${tuiError}`); }
  stopTui();
  await waitFor(() => tui.exitCode !== null);
  const serverAfterTui = await request(managed.url, "/api/info");
  const shellAfterTui = (await json(managed.url, "/api/shell")).data;
  const pendingAfterTui = (await json(managed.url, `/api/session/${managedSession}/permission`)).data;
  const replyURL = new URL(`/api/session/${managedSession}/permission/${permission.id}/reply`, managed.url).href;
  const replyCode = `fetch(${JSON.stringify(replyURL)}, { method: "POST", headers: { Authorization: "Basic " + Buffer.from("opencode:" + process.env.OPENCODE_PASSWORD).toString("base64"), "Content-Type": "application/json" }, body: JSON.stringify({ decision: "once" }) }).then((response) => console.log("self_reply_status=" + response.status))`;
  await json(managed.url, `/api/session/${managedSession}/shell`, "POST", {
    command: `node -e '${replyCode}'`,
  });
  const pendingAfterReply = (await json(managed.url, `/api/session/${managedSession}/permission`)).data;
  await json(managed.url, `/api/shell/${managedShell.id}`, "DELETE");
  await managedShellRequest;
  if (managedShellError) throw managedShellError;
  console.log(JSON.stringify({
    tuiRenderedBytes: renderedBytes,
    tuiUiMarker: /OpenCode|opencode|model|session/i.test(tuiFrame.replaceAll(/\x1b\[[\d;?]*[A-Za-z]/g, "")),
    tuiPaneMarkersStayedOutOfServerShell: /herdr=missing/.test(shellOutput),
    servicePasswordExposedToServerShell: /auth=present/.test(shellOutput),
    managedServer: { readyMs: managed.readyMs, rssMiB: rssMiB(managed.child.pid) },
    managedServerAliveAfterTuiExit: serverAfterTui.ok,
    sessionShellAliveAfterTuiExit: shellAfterTui.some((item) => item.id === managedShell.id),
    permissionPendingAfterTuiExit: pendingAfterTui.some((item) => item.id === permission.id),
    shellCouldReplyToItsOwnPendingPermission: !pendingAfterReply.some((item) => item.id === permission.id),
  }));
} finally {
  stopTui();
  if (managed && managed.child.exitCode === null) {
    const exit = new Promise((resolve) => managed.child.once("exit", resolve));
    managed.child.kill("SIGTERM");
    await Promise.race([exit, new Promise((resolve) => setTimeout(resolve, 5000))]);
    if (managed.child.exitCode === null && managed.child.signalCode === null) managed.child.kill("SIGKILL");
  }
  if (server) {
    if (server.child.exitCode === null) {
      const exit = new Promise((resolve) => server.child.once("exit", resolve));
      server.child.stdin.end();
      await Promise.race([exit, new Promise((resolve) => setTimeout(resolve, 5000))]);
      if (server.child.exitCode === null) server.child.kill("SIGTERM");
    }
  }
  await rm(scratch, { recursive: true, force: true });
}
