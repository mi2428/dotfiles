import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";

const binary = process.env.OPENCODE_V2_BIN;
const parent = process.env.OPENCODE_EXPERIMENT_ROOT;
if (!binary || !parent || !path.isAbsolute(binary) || !path.isAbsolute(parent)) {
  throw new Error("Set absolute OPENCODE_V2_BIN and OPENCODE_EXPERIMENT_ROOT");
}
const scratch = await mkdtemp(path.join(parent, "oc2-model-"));
await Promise.all(["config", "data", "cache", "state"].map((name) => mkdir(path.join(scratch, name))));

let calls = 0;
const provider = createServer(async (req, res) => {
  if (req.url !== "/v1/chat/completions") { res.writeHead(404); res.end(); return; }
  for await (const chunk of req) void chunk;
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  const id = ++calls;
  const data = (choice) => res.write(`data: ${JSON.stringify({ id: `chatcmpl-${id}`, object: "chat.completion.chunk", created: 0, model: "mock", choices: [{ index: 0, ...choice }] })}\n\n`);
  if (id < 3) {
    data({ delta: { role: "assistant", tool_calls: [{ index: 0, id: `call_${id}`, type: "function", function: { name: "shell", arguments: '{"command":"exec sleep 8"}' } }] }, finish_reason: null });
    data({ delta: {}, finish_reason: "tool_calls" });
  } else data({ delta: { role: "assistant", content: "Done" }, finish_reason: "stop" });
  res.end("data: [DONE]\n\n");
});
await new Promise((resolve) => provider.listen(0, "127.0.0.1", resolve));
const baseURL = `http://127.0.0.1:${provider.address().port}/v1`;
const password = randomBytes(32).toString("base64url");
const env = {
  ...process.env,
  HOME: scratch,
  XDG_CONFIG_HOME: path.join(scratch, "config"),
  XDG_DATA_HOME: path.join(scratch, "data"),
  XDG_CACHE_HOME: path.join(scratch, "cache"),
  XDG_STATE_HOME: path.join(scratch, "state"),
  OPENCODE_DB: ":memory:",
  OPENCODE_PASSWORD: password,
  OPENCODE_CONFIG_CONTENT: JSON.stringify({
    model: "probe/mock",
    plugins: [],
    providers: {
      probe: { name: "Local probe", package: "@opencode/ai/providers/openai-compatible", settings: {
        baseURL, apiKey: "test-only",
      }, models: { mock: { name: "Offline probe", capabilities: { tools: true, input: ["text"], output: ["text"] }, limit: { context: 16384, output: 1024 } } } },
    },
    permissions: [{ action: "shell", resource: "*", effect: "allow" }],
  }),
  OPENCODE_DISABLE_PROJECT_CONFIG: "1",
  OPENCODE_DISABLE_EXTERNAL_SKILLS: "1",
};
for (const key of Object.keys(env)) if (key.startsWith("HERDR_") || key.startsWith("HAPPIER_")) delete env[key];

let server;
let url;
const request = async (route, method = "GET", body) => {
  const response = await fetch(new URL(route, url), { method, headers: {
    Authorization: `Basic ${Buffer.from(`opencode:${password}`).toString("base64")}`,
    ...(body ? { "Content-Type": "application/json" } : {}),
  }, ...(body ? { body: JSON.stringify(body) } : {}) });
  if (!response.ok) throw new Error(`${method} ${route}: HTTP ${response.status} ${(await response.text()).slice(0, 500)}`);
  return response.status === 204 ? undefined : response.json();
};
async function until(predicate, timeout = 12000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const found = await predicate();
    if (found) return found;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Timed out waiting for local model-owned shell");
}

try {
  server = spawn(binary, ["serve", "--stdio", "--port", "0"], { cwd: scratch, env, stdio: ["pipe", "pipe", "ignore"] });
  url = await new Promise((resolve, reject) => {
    let output = "";
    const timer = setTimeout(() => reject(new Error("Server readiness timed out")), 10000);
    server.stdout.on("data", (chunk) => {
      output += chunk.toString();
      if (!output.includes("\n")) return;
      clearTimeout(timer);
      try { resolve(new URL(JSON.parse(output.slice(0, output.indexOf("\n"))).url)); } catch (error) { reject(error); }
      server.stdout.removeAllListeners("data");
      server.stdout.resume();
    });
    server.once("error", reject);
  });
  const listed = await request("/api/model");
  assert(listed.data.some((model) => model.providerID === "probe"), "Local model must be registered");
  const a = (await request("/api/session", "POST", { title: "model-A", model: { providerID: "probe", id: "mock" } })).data.id;
  const b = (await request("/api/session", "POST", { title: "model-B", model: { providerID: "probe", id: "mock" } })).data.id;
  await Promise.all([request(`/api/session/${a}/prompt`, "POST", { text: "Run a test shell" }), request(`/api/session/${b}/prompt`, "POST", { text: "Run a test shell" })]);
  const shells = await until(async () => {
    const data = (await request("/api/shell")).data;
    return data.some((item) => item.metadata?.sessionID === a) && data.some((item) => item.metadata?.sessionID === b) ? data : undefined;
  });
  const shellA = shells.find((item) => item.metadata?.sessionID === a);
  const shellB = shells.find((item) => item.metadata?.sessionID === b);
  const interrupted = await request(`/api/session/${a}/interrupt`, "POST");
  const remaining = await until(async () => {
    const data = (await request("/api/shell")).data;
    return !data.some((item) => item.id === shellA.id) ? data : undefined;
  });
  assert(remaining.some((item) => item.id === shellB.id));
  console.log(JSON.stringify({
    localMockRequests: calls,
    agentInterruptReported: interrupted.data?.interrupted ?? interrupted.interrupted ?? null,
    foregroundShellAStopped: !remaining.some((item) => item.id === shellA.id),
    foregroundShellBPreserved: remaining.some((item) => item.id === shellB.id),
  }));
  await request(`/api/shell/${shellB.id}`, "DELETE");
  await request(`/api/session/${b}/interrupt`, "POST");
} finally {
  if (server) {
    server.stdin.end();
    if (server.exitCode === null) {
      const exited = new Promise((resolve) => server.once("exit", resolve));
      await Promise.race([exited, new Promise((resolve) => setTimeout(resolve, 4000))]);
      if (server.exitCode === null) server.kill("SIGTERM");
    }
  }
  await new Promise((resolve) => provider.close(resolve));
  await rm(scratch, { recursive: true, force: true });
}
