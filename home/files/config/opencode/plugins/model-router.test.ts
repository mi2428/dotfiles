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
  test("only downgrades clearly SIMPLE requests; includes the model name and compact score", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("SIMPLE", 0.95)) as typeof fetch;
    const result = output();
    await (await ModelRouter())["chat.message"]({}, result);
    expect(result.message.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter).toEqual({
      model: config.tiers.SIMPLE, tier: "SIMPLE", label: "Smart Router · SIMPLE (GPT-6 Luna) · 0.95",
    });
  });

  test("keeps the default for non-simple, uncertain and contextual requests", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    const hooks = await ModelRouter();
    for (const [response, label] of [
      [decision("DEFAULT", 0.97), "Smart Router · fallback (GPT-6 Sol) · 0.97"],
      [decision("SIMPLE", 0.2588), "Smart Router · fallback (GPT-6 Sol) · 0.2588"],
      [decision("SIMPLE", 0.97, "CONTEXT_REQUIRED"), "Smart Router · fallback (GPT-6 Sol) · 0.97"],
      [decision("SIMPLE", 0.97, "CLEAR", 0.2), "Smart Router · fallback (GPT-6 Sol) · 0.97"],
    ] as const) {
      globalThis.fetch = (async () => response) as typeof fetch;
      const result = output();
      await hooks["chat.message"]({}, result);
      expect(result.message.model).toEqual(config.fallback);
      expect(result.parts[0].metadata.modelRouter.label).toBe(label);
    }
  });

  test("does not inherit a SIMPLE override on the next turn", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let choice = "SIMPLE";
    globalThis.fetch = (async () => decision(choice, 0.99, choice === "SIMPLE" ? "CLEAR" : "CONTEXT_REQUIRED")) as typeof fetch;
    const hooks = await ModelRouter();
    const first = output();
    await hooks["chat.message"]({}, first);
    choice = "DEFAULT";
    const next = output();
    next.parts[0].text = "その続きやって";
    await hooks["chat.message"]({}, next);
    expect(first.message.model).toEqual(config.tiers.SIMPLE);
    expect(next.message.model).toEqual(config.fallback);
  });

  test("honors an explicit router:max token without calling the classifier", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => { throw new Error("classifier should not run"); }) as typeof fetch;
    const result = output();
    result.parts[0].text = "これを ROUTER:MAX で検証して";
    await (await ModelRouter())["chat.message"]({}, result);
    expect(result.message.model).toEqual(config.tiers.REASONING);
    expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · REASONING (GPT-6 Sol) · router:max");
  });

  test("does not treat partial router:max tokens as explicit model choices", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => decision("DEFAULT", 0.95)) as typeof fetch;
    const hooks = await ModelRouter();
    for (const text of ["prerouter:max", "router:maximum", "xhigh"]) {
      const result = output();
      result.parts[0].text = text;
      await hooks["chat.message"]({}, result);
      expect(result.message.model).toEqual(config.fallback);
    }
  });

  test("respects a manually selected model even if the classifier or config is unavailable", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = resolve(import.meta.dir, "missing-model-router.json");
    globalThis.fetch = (async () => { throw new Error("classifier should not run"); }) as typeof fetch;
    const manual = output({ providerID: "openai", modelID: "gpt-6-sol", variant: "high" });
    await (await ModelRouter())["chat.message"]({}, manual);
    expect(manual.message.model.variant).toBe("high");
    expect(manual.parts[0].metadata).toBeUndefined();
    await expect((await ModelRouter())["chat.message"]({}, output())).rejects.toThrow("config unavailable");
  });

  test("keeps the default and names it when the classifier fails", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    globalThis.fetch = (async () => { throw new Error("offline"); }) as typeof fetch;
    const warning = spyOn(console, "warn").mockImplementation(() => {});
    try {
      const result = output();
      await (await ModelRouter())["chat.message"]({}, result);
      expect(result.message.model).toEqual(config.fallback);
      expect(result.parts[0].metadata.modelRouter.label).toBe("Smart Router · fallback (GPT-6 Sol)");
      expect(warning).toHaveBeenCalledWith(expect.stringContaining("routing unavailable"));
    } finally {
      warning.mockRestore();
    }
  });
});
