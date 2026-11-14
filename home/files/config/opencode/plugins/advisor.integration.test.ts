import { strict as assert } from "node:assert";
import { mkdtemp, mkdir, cp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { it } from "bun:test";

it("returns text-only advice to the unchanged main model and persists it in the conversation", async () => {
  // All provider/model IDs are local fixtures, not real services or configured aliases.
  const directory = await mkdtemp(join(tmpdir(), "opencode-advisor-"));
  const requests: any[] = [];
  const question = "Check this approach";
  const fake = Bun.serve({ hostname: "127.0.0.1", port: 0, async fetch(r) {
    const input = await r.json() as any;
    requests.push(input);
    const reviewer = input.model === "reviewer";
    const transcript = JSON.stringify(input.messages);
    const hasAdvice = transcript.includes("SHARED_ADVICE");
    const calls = !reviewer && !transcript.includes("call_advisor") ? [{ index: 0, id: "call_advisor", type: "function", function: { name: "advisor", arguments: JSON.stringify({ alias: "review", question }) } }] : undefined;
    const content = reviewer ? "SHARED_ADVICE" : hasAdvice ? "CONTINUED_WITH_ADVICE" : "Consulting";
    const message = { role: "assistant", content, ...(calls ? { tool_calls: calls } : {}) };
    if (input.stream) {
      const chunk = (delta: any, finish_reason: any) => `data: ${JSON.stringify({ id: "fixture", object: "chat.completion.chunk", created: 1, model: input.model, choices: [{ index: 0, delta, finish_reason }] })}\n\n`;
      return new Response(chunk(message, null) + chunk({}, calls ? "tool_calls" : "stop") + "data: [DONE]\n\n", { headers: { "content-type": "text/event-stream" } });
    }
    return Response.json({ id: "fixture", object: "chat.completion", created: 1, model: input.model, choices: [{ index: 0, message, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } });
  } });
  let server: any, logs = "";
  const env = { PATH: process.env.PATH!, HOME: directory, XDG_CONFIG_HOME: join(directory, "config"), XDG_DATA_HOME: join(directory, "data"), XDG_CACHE_HOME: join(directory, "cache"), XDG_STATE_HOME: join(directory, "state"), OPENCODE_PASSWORD: "fixture-password" };
  const wait = async (fn: () => boolean | Promise<boolean>) => {
    const end = Date.now() + 10000;
    while (!await fn() && Date.now() < end) await Bun.sleep(50);
    assert.ok(await fn(), "OpenCode did not finish within the test deadline");
  };
  try {
    const plugin = join(directory, "advisor");
    await cp(new URL("./advisor/", import.meta.url), plugin, { recursive: true });
    await mkdir(join(directory, "config/opencode"), { recursive: true });
    await writeFile(join(directory, "config/opencode/opencode.json"), JSON.stringify({
      model: "fixture/executor", agents: { title: { disabled: true } },
      plugins: [{ package: plugin, options: { aliases: { review: "fixture/reviewer" } } }],
      providers: { fixture: { name: "Fixture", package: "@opencode/ai/providers/openai-compatible", settings: { baseURL: `${fake.url}v1`, apiKey: "fixture-key" }, models: Object.fromEntries(["executor", "reviewer"].map((id) => [id, { name: id, capabilities: { tools: true, input: ["text", "image"], output: ["text"] }, limit: { context: 200000, output: 1024 } }])) } },
    }));
    server = Bun.spawn(["opencode", "serve", "--hostname", "127.0.0.1", "--port", "0"], { cwd: directory, env, stdout: "pipe", stderr: "pipe" });
    const read = async (stream: any) => { for await (const b of stream) logs += new TextDecoder().decode(b); };
    void read(server.stdout); void read(server.stderr);
    await wait(() => /http:\/\/127.0.0.1:\d+/.test(logs));
    const url = logs.match(/http:\/\/127.0.0.1:\d+/)![0];
    const api = async (path: string, body?: any) => {
      const response = await fetch(url + path, { method: body === undefined ? "GET" : "POST", headers: { "content-type": "application/json", authorization: `Basic ${Buffer.from(`opencode:${env.OPENCODE_PASSWORD}`).toString("base64")}` }, ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(10000) });
      const text = await response.text();
      assert.ok(response.ok, `${path}: ${text}`);
      return text ? JSON.parse(text) : undefined;
    };
    const session = (await api("/api/session", { permissions: [{ action: "advisor", resource: "fixture/reviewer", effect: "allow" }] })).data;
    const image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
    await api(`/api/session/${session.id}/prompt`, { text: "Prior context", files: [{ uri: `data:image/png;base64,${image}`, name: "fixture.png" }], resume: false });
    await api(`/api/session/${session.id}/command`, { name: "advisor", text: `review ${question}` });
    const history = async () => (await api(`/api/session/${session.id}/context`)).data;
    await wait(async () => (await history()).at(-1)?.type === "idle");
    const messages = await history();
    const assistants = messages.filter((m: any) => m.type === "assistant");
    const advice = assistants.flatMap((m: any) => m.content).find((p: any) => p.type === "tool" && p.name === "advisor");
    assert.equal(advice?.state.status, "completed", JSON.stringify(advice?.state));
    assert.ok(JSON.stringify(advice.state.content).includes("SHARED_ADVICE"));
    assert.ok(messages.some((m: any) => m.type === "user" && m.text.includes(question)));
    const reviews = requests.filter((r) => r.model === "reviewer");
    assert.equal(reviews.length, 1);
    assert.ok(JSON.stringify(reviews[0].messages).includes("Prior context"));
    assert.ok(JSON.stringify(reviews[0].messages).includes(question));
    assert.ok(!JSON.stringify(reviews[0].messages).includes(image));
    assert.ok(!reviews[0].tools?.length);
    assert.equal(requests.at(-1).model, "executor");
    assert.ok(JSON.stringify(requests.at(-1).messages).includes("SHARED_ADVICE"));
    assert.ok(assistants.every((m: any) => m.model.id === "executor"));
    assert.ok(assistants.at(-1).content.some((p: any) => p.type === "text" && p.text.includes("CONTINUED_WITH_ADVICE")));
  } finally {
    if (server) { server.kill(); await server.exited; }
    fake.stop(true);
    await rm(directory, { recursive: true, force: true });
  }
}, 20000);
