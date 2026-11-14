import { strict as assert } from "node:assert";
import { it } from "bun:test";
import { resolveRequest, registerAdvisor } from "./advisor/runtime.mjs";

it("requires an exact alias and preserves the question", () => {
  const aliases = { review: "fixture/advisor" };
  assert.equal(resolveRequest(aliases, "review hoge  fuga\npoyo").text, "hoge  fuga\npoyo");
  for (const text of ["", "hoge fuga", "off question", "__proto__ question"]) assert.throws(() => resolveRequest(aliases, text), /そのようなモデルはありません/);
  assert.throws(() => resolveRequest(aliases, "review"), /質問文を指定/);
});

it("excludes attachment contents and private reasoning, and sends nothing when permission is denied", async () => {
  let tool: any, denied = true;
  const generated: any[] = [];
  const model = { providerID: "fixture", id: "advisor", variant: "fixture-effort" };
  const messages: any[] = [{ type: "user", text: "Prior context", files: [{ mime: "image/png", data: "PRIVATE_IMAGE_DATA", uri: "file:///PRIVATE_IMAGE" }] }, { type: "assistant", content: [{ type: "reasoning", text: "PRIVATE_REASONING" }, { type: "text", text: "My current approach" }, { type: "tool", name: "read", state: { status: "completed", input: {}, content: [{ type: "file", uri: "PRIVATE_TOOL_IMAGE", mime: "image/png" }, { type: "text", text: "Visible tool output" }] } }] }];
  await registerAdvisor({
    options: { aliases: { review: "fixture/advisor#fixture-effort" } },
    tool: { transform: async (fn: any) => fn({ add: (t: any) => { tool = t; } }) },
    command: { transform: async () => {} },
    session: { hook: async () => {}, context: async () => messages },
    model: { list: async () => ({ data: [{ ...model, enabled: true, capabilities: { output: ["text"] }, variants: [{ id: model.variant }] }] }) },
    permission: { assert: async () => { if (denied) throw new Error("Permission denied"); } },
    experimental: { generate: { text: async (input: any) => { generated.push(input); return { text: "Use a transaction" }; } } },
  } as any, () => model as any);
  const request = { sessionID: "ses_test", messageID: "msg_test", id: "call_test", agent: "build", signal: new AbortController().signal, progress: async () => {} };
  const input = { alias: "review", question: "Check the boundary" };
  await assert.rejects(tool.execute(input, request), /Permission denied/);
  assert.equal(generated.length, 0);
  denied = false;
  const answer = await tool.execute(input, request);
  assert.equal(generated.length, 1);
  assert.match(answer.content, /Use a transaction/);
  assert.ok(!generated[0].prompt.includes("PRIVATE_REASONING"));
  assert.ok(generated[0].prompt.includes("Prior context"));
  assert.ok(generated[0].prompt.includes("Visible tool output"));
  assert.ok(!generated[0].prompt.includes("PRIVATE_IMAGE"));
  assert.ok(!generated[0].prompt.includes("PRIVATE_TOOL_IMAGE"));
  assert.ok(generated[0].prompt.includes(input.question));
  assert.deepEqual(generated[0].model, model);
});
