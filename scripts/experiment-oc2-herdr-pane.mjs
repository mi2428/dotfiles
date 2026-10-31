import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const action = process.argv[2];
const parse = (root) => readFile(path.join(root, "registration.json"), "utf8").then(JSON.parse);
async function stopOwner(state, root) {
  if (state.root !== path.resolve(root))
    throw new Error("Experiment owner no longer matches registration");
  const providerURL = new URL(JSON.parse(state.config).providers.probe.settings.baseURL);
  if (providerURL.hostname !== "127.0.0.1") throw new Error("Experiment provider must be local");
  const url = new URL("/__experiment_owner/stop", providerURL);
  url.searchParams.set("root", state.root);
  const response = await fetch(url, { method: "POST", headers: { Authorization: `Bearer ${state.password}` },
    signal: AbortSignal.timeout(2000) });
  if (response.status !== 202) throw new Error("Experiment owner refused stop request");
}
if (action === "--launch") {
  const state = await parse(process.argv[3]);
  const client = spawn(state.binary, ["--server", state.url, ...process.argv.slice(4)], {
    cwd: state.worktree,
    env: { ...process.env, HOME: state.root, XDG_CONFIG_HOME: path.join(state.root, "config"),
      XDG_DATA_HOME: path.join(state.root, "data"), XDG_STATE_HOME: path.join(state.root, "state"),
      OPENCODE_PASSWORD: state.password, OPENCODE_CONFIG_CONTENT: state.config },
    stdio: "inherit",
  });
  let finished = false;
  const finish = async (code) => {
    if (finished) return;
    finished = true;
    try { await stopOwner(state, process.argv[3]); } catch (error) { console.error(error.message); process.exitCode = 1; }
    if (process.exitCode !== 1) process.exitCode = code ?? 1;
  };
  client.once("exit", (code) => { void finish(code); });
  client.once("error", (error) => { console.error(error.message); void finish(1); });
} else if (action === "--api") {
  const state = await parse(process.argv[3]);
  const method = process.argv[4];
  const route = process.argv[5];
  assert(["GET", "POST"].includes(method) && route?.startsWith("/api/"));
  const payload = process.argv[6];
  const response = await fetch(new URL(route, state.url), {
    method,
    headers: { Authorization: `Basic ${Buffer.from(`opencode:${state.password}`).toString("base64")}`,
      ...(payload ? { "Content-Type": "application/json" } : {}) },
    ...(payload ? { body: payload } : {}),
  });
  if (!response.ok) throw new Error(`${method} ${route}: HTTP ${response.status}`);
  const data = response.status === 204 ? null : await response.json();
  console.log(JSON.stringify({ status: response.status, id: data?.data?.id,
    title: data?.data?.title, outcome: data?.data?.outcome?.type,
    interrupted: data?.data?.interrupted ?? data?.interrupted,
    activeCount: route === "/api/session/active" ? Object.keys(data?.data ?? {}).length : undefined,
    count: Array.isArray(data?.data) ? data.data.length : undefined }));
} else if (action === "--inspect") {
  const state = await parse(process.argv[3]);
  const statistics = JSON.parse(await readFile(path.join(state.root, "stream-stats.json"), "utf8"));
  console.log(JSON.stringify(statistics));
} else if (action === "--provider") {
  const state = await parse(process.argv[3]);
  const baseURL = JSON.parse(state.config).providers?.probe?.settings?.baseURL;
  const url = new URL(baseURL);
  assert.equal(url.hostname, "127.0.0.1");
  console.log(JSON.stringify({ baseURL: url.href, model: "probe/mock" }));
} else if (action === "--events") {
  const state = await parse(process.argv[3]);
  const sessionID = process.argv[4];
  assert(/^ses_[A-Za-z0-9]+$/.test(sessionID));
  const response = await fetch(new URL(`/api/experimental/session/${sessionID}/log?follow=false&after=0`, state.url), {
    headers: { Authorization: `Basic ${Buffer.from(`opencode:${state.password}`).toString("base64")}` },
  });
  if (!response.ok) throw new Error(`Session log HTTP ${response.status}`);
  const lines = (await response.text()).split("\n");
  const types = lines.filter((line) => line.startsWith("data: ")).map((line) => {
    const item = JSON.parse(line.slice(6));
    return item.type ?? item.event?.type ?? item.event ?? item.data?.type ?? "unknown";
  });
  console.log(JSON.stringify({ status: response.status, events: types }));
} else if (action === "--stop") {
  const state = await parse(process.argv[3]);
  await stopOwner(state, process.argv[3]);
  console.log("Experiment owner stop requested");
} else if (action === "--serve") {
  const binary = process.env.OPENCODE_V2_BIN;
  const parent = process.env.OPENCODE_EXPERIMENT_ROOT;
  const worktree = process.env.OPENCODE_EXPERIMENT_WORKTREE;
  assert(binary && parent && worktree && path.isAbsolute(binary) && path.isAbsolute(parent) && path.isAbsolute(worktree));
  const root = await mkdtemp(path.join(parent, "oc2-herdr-pane-"));
  await Promise.all(["config/opencode", "data", "state", "cache"].map((name) => mkdir(path.join(root, name), { recursive: true })));
  let cancelled = 0;
  await writeFile(path.join(root, "stream-stats.json"), JSON.stringify({ cancelled }));
  const password = randomBytes(32).toString("base64url");
  let stop;
  const provider = createServer(async (request, response) => {
    if (request.url?.startsWith("/__experiment_owner/stop?")) {
      const requestedRoot = new URL(request.url, "http://127.0.0.1").searchParams.get("root");
      if (request.method !== "POST" || request.headers.authorization !== `Bearer ${password}` || requestedRoot !== root || !stop) {
        response.writeHead(403); response.end(); return;
      }
      response.writeHead(202); response.end();
      void stop().catch((error) => { console.error(error); process.exitCode = 1; });
      return;
    }
    if (request.url !== "/v1/chat/completions") { response.writeHead(404); response.end(); return; }
    response.on("close", () => {
      if (!response.writableFinished) void writeFile(path.join(root, "stream-stats.json"), JSON.stringify({ cancelled: ++cancelled }));
    });
    for await (const chunk of request) void chunk;
    response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
    const send = (text, finish = null) => response.write(`data: ${JSON.stringify({ id: "chatcmpl-probe", object: "chat.completion.chunk", created: 0, model: "mock", choices: [{ index: 0, delta: { role: "assistant", content: text }, finish_reason: finish }] })}\n\n`);
    send("STATUS: TEST. ");
    await new Promise((resolve) => setTimeout(resolve, 3000));
    send("No source changes. ");
    await new Promise((resolve) => setTimeout(resolve, 3000));
    send("Verification: local mock streamed text in the full TUI. ");
    await new Promise((resolve) => setTimeout(resolve, 3000));
    send("Risk: the model cannot inspect Herdr state. Next: supervisor checks pane status and cleanup.", "stop");
    response.end("data: [DONE]\n\n");
  });
  await new Promise((resolve) => provider.listen(0, "127.0.0.1", resolve));
  const baseURL = `http://127.0.0.1:${provider.address().port}/v1`;
  const config = JSON.stringify({ model: "probe/mock", default_agent: "herdr-worker", plugins: [],
    agents: { "herdr-worker": { mode: "primary", model: "probe/mock", prompt: "Test only; do not modify files." } },
    providers: { probe: { name: "Local test provider", package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL, apiKey: "test-only" }, models: { mock: { name: "Offline mock",
        capabilities: { tools: true, input: ["text"], output: ["text"] }, limit: { context: 16384, output: 1024 } } } } },
  });
  const tuiPlugin = process.env.OPENCODE_EXPERIMENT_HERDR_PLUGIN;
  assert(tuiPlugin === "none" || (tuiPlugin && path.isAbsolute(tuiPlugin)));
  await writeFile(path.join(root, "config", "opencode", "cli.json"), JSON.stringify({
    plugins: tuiPlugin === "none" ? [] : [tuiPlugin],
  }));
  const env = { PATH: process.env.PATH, HOME: root, SHELL: process.env.SHELL ?? "/bin/zsh", TERM: "xterm-256color",
    XDG_CONFIG_HOME: path.join(root, "config"), XDG_DATA_HOME: path.join(root, "data"),
    XDG_STATE_HOME: path.join(root, "state"), XDG_CACHE_HOME: path.join(root, "cache"),
    OPENCODE_DB: ":memory:", OPENCODE_PASSWORD: password, OPENCODE_CONFIG_CONTENT: config,
    OPENCODE_DISABLE_PROJECT_CONFIG: "1", OPENCODE_DISABLE_EXTERNAL_SKILLS: "1",
  };
  const server = spawn(binary, ["serve", "--stdio", "--port", "0"], {
    cwd: worktree, env, stdio: ["pipe", "pipe", "ignore"],
  });
  let closedServer = false;
  const closed = new Promise((resolve) => server.once("close", () => { closedServer = true; resolve(); }));
  let stopPromise;
  stop = () => stopPromise ??= (async () => {
    if (!server.stdin.destroyed) server.stdin.end();
    if (!closedServer) server.kill("SIGTERM");
    await Promise.race([closed, delay(2000, undefined, { ref: false })]);
    if (!closedServer) {
      server.kill("SIGKILL");
      await Promise.race([closed, delay(2000, undefined, { ref: false })]);
      if (!closedServer) throw new Error("V2 server did not exit; experiment root retained");
    }
    provider.closeAllConnections();
    await new Promise((resolve) => provider.close(resolve));
    await rm(root, { recursive: true, force: true });
  })();
  process.on("SIGTERM", () => { void stop().catch((error) => { console.error(error); process.exitCode = 1; }); });
  process.on("SIGINT", () => { void stop().catch((error) => { console.error(error); process.exitCode = 1; }); });
  let ready = "";
  try {
    const url = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("V2 server readiness timeout")), 10000);
      server.stdout.on("data", (chunk) => {
        ready += chunk.toString();
        if (!ready.includes("\n")) return;
        clearTimeout(timer);
        try { resolve(new URL(JSON.parse(ready.slice(0, ready.indexOf("\n"))).url).href); }
        catch (error) { reject(error); }
        server.stdout.removeAllListeners("data");
        server.stdout.resume();
      });
      server.once("error", (error) => { clearTimeout(timer); reject(error); });
      server.once("close", () => { clearTimeout(timer); reject(new Error("V2 server closed before ready")); });
    });
    await writeFile(path.join(root, "registration.json"), JSON.stringify({ root, worktree,
      binary, url, password, config }), { flag: "wx", mode: 0o600 });
    console.log(`EXPERIMENT_DIR=${root}`);
    await closed;
  } finally {
    await stop();
  }
} else throw new Error("Use --serve, --launch, --api, or --stop");
