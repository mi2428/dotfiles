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
const decision = (choice, confidence, clarity = "CLEAR", contextConfidence = 0.95) =>
  new Response(JSON.stringify({ answers: {
    tier: { choice, confidence },
    clarity: { choice: clarity, confidence: contextConfidence },
  } }));

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
    expect(Object.keys(config.questions.clarity.criteria)).toEqual(["CLEAR", "CONTEXT_REQUIRED"]);
  });

  test("routes a confident user turn", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("SIMPLE", 0.8)) as typeof fetch;

    const hooks = await ModelRouter();
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter.tier).toBe("SIMPLE");
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · SIMPLE · confidence 0.8");
  });

  test("reroutes a second turn while Smart Router stays selected", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let choice = "SIMPLE";
    globalThis.fetch = (async () => decision(choice, 0.8)) as typeof fetch;

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
      return decision("SIMPLE", 0.8);
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
    globalThis.fetch = (async () => decision("REASONING", 0.1)) as typeof fetch;

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
      expect(warning).toHaveBeenCalledWith(expect.stringContaining("routing unavailable"));
    } finally {
      warning.mockRestore();
    }
  });

  test("uses the fallback on low confidence and ignores concrete models", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("REASONING", 0.1)) as typeof fetch;

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

  test("inherits the previous routed model for a contextual follow-up", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("SIMPLE", 0.7, "CONTEXT_REQUIRED", 0.95)) as typeof fetch;
    const client = { session: { messages: async ({ path, query }) => {
      expect(path.id).toBe("session");
      expect(query.directory).toBe("/repo");
      return { data: [
        { info: { role: "user", id: "previous" }, parts: [{ type: "text", metadata: { modelRouter: {
          model: config.tiers.REASONING, tier: "REASONING", label: "Smart Router · REASONING · confidence 0.8",
        } } }] },
        { info: { role: "user", id: "current" }, parts: [] },
      ] };
    } } };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    result.parts[0].text = "まずそこ直して";
    await hooks["chat.message"]({ sessionID: "session", messageID: "current", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.REASONING);
    expect(result.parts[0].metadata.modelRouter.tier).toBe("REASONING");
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · REASONING · inherited");
  });

  test("falls back when a contextual turn has no previous routed model", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("SIMPLE", 0.7, "CONTEXT_REQUIRED", 0.95)) as typeof fetch;
    const client = { session: { messages: async () => ({ data: [] }) } };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    result.parts[0].text = "これ直して";
    await hooks["chat.message"]({ sessionID: "session", messageID: "current", agent: "build" }, result);

    expect(result.message.model).toEqual(config.fallback);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback · context missing");
  });

  test("raises the inherited tier when a follow-up adds harder requirements", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("COMPLEX", 0.7, "CONTEXT_REQUIRED", 0.9)) as typeof fetch;
    const client = { session: { messages: async () => ({ data: [
      { info: { role: "user", id: "previous" }, parts: [{ type: "text", metadata: { modelRouter: {
        model: config.tiers.SIMPLE, tier: "SIMPLE", label: "Smart Router · SIMPLE · confidence 0.8",
      } } }] },
    ] }) } };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    result.parts[0].text = "それを全サービスに展開して安全性も検証して";
    await hooks["chat.message"]({ sessionID: "session", messageID: "current", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.COMPLEX);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · COMPLEX · confidence 0.7");
  });

  test("does not downgrade a previous safety fallback", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("COMPLEX", 0.7, "CONTEXT_REQUIRED", 0.9)) as typeof fetch;
    const client = { session: { messages: async () => ({ data: [
      { info: { role: "user", id: "previous" }, parts: [{ type: "text", metadata: { modelRouter: {
        model: config.fallback, label: "Smart Router · fallback · confidence 0.2",
      } } }] },
    ] }) } };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", messageID: "current", agent: "build" }, result);

    expect(result.message.model).toEqual(config.fallback);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback · inherited");
  });

  test("does not inherit a cheap model when new contextual requirements have low confidence", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("REASONING", 0.2, "CONTEXT_REQUIRED", 0.9)) as typeof fetch;
    const client = { session: { messages: async () => ({ data: [
      { info: { role: "user", id: "previous" }, parts: [{ type: "text", metadata: { modelRouter: {
        model: config.tiers.SIMPLE, tier: "SIMPLE",
      } } }] },
    ] }) } };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", messageID: "current", agent: "build" }, result);

    expect(result.message.model).toEqual(config.fallback);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback · confidence 0.2");
  });
});
