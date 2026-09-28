import { afterEach, describe, expect, spyOn, test } from "bun:test";
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
  test("defines the requested six tiers and classifier criteria", () => {
    expect(Object.entries(config.tiers).map(([tier, model]) => [tier, model.variant])).toEqual([
      ["SIMPLE", "auto"],
      ["LOW", "medium"],
      ["MEDIUM", "max"],
      ["HIGH", "medium"],
      ["COMPLEX", "high"],
      ["REASONING", "max"],
    ]);
    expect(config.tiers.LOW.modelID).toBe(config.tiers.MEDIUM.modelID);
    expect(config.tiers.HIGH.modelID).toBe(config.tiers.REASONING.modelID);
    expect(Object.keys(config.questions.tier.criteria)).toEqual(Object.keys(config.tiers));
  });

  test("routes a confident user turn", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }))) as typeof fetch;

    const hooks = await ModelRouter();
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · SIMPLE · confidence 0.8");
  });

  test("reroutes a second turn while Smart Router stays selected", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let choice = "SIMPLE";
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice, confidence: 0.8 } } }))) as typeof fetch;

    let hooks = await ModelRouter();
    const first = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, first);

    choice = "REASONING";
    hooks = await ModelRouter();
    const second = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, second);

    expect(second.message.model).toEqual(config.tiers.REASONING);
    expect(second.parts[0].metadata.modelRouter.label).toBe("Smart Router · REASONING · confidence 0.8");
  });

  test("stops routing when the selected concrete model equals the previous auto result", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let classifierCalls = 0;
    globalThis.fetch = (async () => {
      classifierCalls++;
      return new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }));
    }) as typeof fetch;
    const hooks = await ModelRouter();
    const first = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, first);

    const manualModel = first.message.model;
    const manual = output(manualModel);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, manual);
    const continued = output(manualModel);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, continued);

    expect(manual.message.model).toEqual(manualModel);
    expect(continued.message.model).toEqual(manualModel);
    expect(classifierCalls).toBe(1);
    expect(manual.parts[0].metadata).toBeUndefined();
    expect(continued.parts[0].metadata).toBeUndefined();
  });

  test("records the confidence when routing falls back", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "REASONING", confidence: 0.1 } } }))) as typeof fetch;

    const hooks = await ModelRouter();
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.fallback);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback · confidence 0.1");
  });

  test("records fallback when JevK5 is unavailable", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => { throw new Error("offline"); }) as typeof fetch;
    const warning = spyOn(console, "warn").mockImplementation(() => {});

    try {
      const hooks = await ModelRouter();
      const result = output();
      await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

      expect(result.message.model).toEqual(config.fallback);
      expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback");
      expect(warning).toHaveBeenCalledWith(expect.stringContaining("classifier unavailable"));
    } finally {
      warning.mockRestore();
    }
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
