import { afterEach, describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { ModelRouter } from "./model-router.js";

const configPath = resolve(import.meta.dir, "../model-router.json");
const config = JSON.parse(readFileSync(configPath, "utf8"));
const originalFetch = globalThis.fetch;
const originalConfig = process.env.OPENCODE_ROUTER_CONFIG;

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalConfig === undefined) delete process.env.OPENCODE_ROUTER_CONFIG;
  else process.env.OPENCODE_ROUTER_CONFIG = originalConfig;
});

const output = (model = { providerID: "smart-router", modelID: "auto" }) => ({
  message: { agent: "build", model },
  parts: [{ type: "text", text: "Fix one typo." }],
});

describe("model router", () => {
  test("routes a confident user turn", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }))) as typeof fetch;

    const hooks = await ModelRouter();
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.SIMPLE);
  });

  test("uses the fallback on low confidence and ignores concrete models", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "REASONING", confidence: 0.1 } } }))) as typeof fetch;

    const hooks = await ModelRouter();
    const uncertain = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, uncertain);
    expect(uncertain.message.model).toEqual(config.fallback);

    const concreteModel = { providerID: "manual", modelID: "chosen", variant: "low" };
    const concrete = output(concreteModel);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, concrete);
    expect(concrete.message.model).toEqual(concreteModel);
  });

  test("fails visibly when the routing policy is unavailable", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = resolve(import.meta.dir, "missing-model-router.json");

    const hooks = await ModelRouter();
    await expect(hooks["chat.message"]({ sessionID: "session", agent: "build" }, output())).rejects.toThrow(
      "config unavailable",
    );
  });
});
