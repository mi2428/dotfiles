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
const modelLabel = (model) => `${model.providerID}/${model.modelID} / ${model.variant}`;

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
    const toasts = [];
    const client = { tui: { showToast: async (options) => { toasts.push(options); return { data: true }; } } };
    globalThis.fetch = (async () => {
      expect(toasts.map(({ body }) => body.message)).toEqual(["Classifying with JevK5..."]);
      return new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }));
    }) as typeof fetch;

    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.tiers.SIMPLE);
    expect(result.parts[0].metadata.modelRouter.model).toEqual(config.tiers.SIMPLE);
    expect(toasts).toEqual([
      {
        body: { title: "Smart Router", message: "Classifying with JevK5...", variant: "info", duration: 12000 },
        query: { directory: "/repo" },
        throwOnError: true,
      },
      {
        body: {
          title: "Smart Router",
          message: `SIMPLE · confidence 0.8 · ${modelLabel(config.tiers.SIMPLE)}`,
          variant: "success",
          duration: 4000,
        },
        query: { directory: "/repo" },
        throwOnError: true,
      },
    ]);
  });

  test("reroutes the concrete model inherited by the TUI", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let choice = "SIMPLE";
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice, confidence: 0.8 } } }))) as typeof fetch;
    const messages = [];
    const toasts = [];
    const client = {
      session: { messages: async () => ({ data: messages.slice(-2) }) },
      tui: { showToast: async ({ body }) => { toasts.push(body); return { data: true }; } },
    };

    let hooks = await ModelRouter({ client, directory: "/repo" });
    const first = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, first);
    messages.push({ info: { role: "user" }, parts: first.parts }, { info: { role: "assistant" }, parts: [] });

    choice = "REASONING";
    hooks = await ModelRouter({ client, directory: "/repo" });
    const second = output(first.message.model);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, second);

    expect(second.message.model).toEqual(config.tiers.REASONING);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "Classifying with JevK5...",
      `SIMPLE · confidence 0.8 · ${modelLabel(config.tiers.SIMPLE)}`,
      "Classifying with JevK5...",
      `REASONING · confidence 0.8 · ${modelLabel(config.tiers.REASONING)}`,
    ]);
  });

  test("stops routing after a concrete model is selected", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    let classifierCalls = 0;
    globalThis.fetch = (async () => {
      classifierCalls++;
      return new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }));
    }) as typeof fetch;
    const messages = [];
    const toasts = [];
    const client = {
      session: { messages: async () => ({ data: messages.slice(-2) }) },
      tui: { showToast: async ({ body }) => { toasts.push(body); return { data: true }; } },
    };
    const hooks = await ModelRouter({ client, directory: "/repo" });
    const first = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, first);
    messages.push({ info: { role: "user" }, parts: first.parts }, { info: { role: "assistant" }, parts: [] });

    const manualModel = { providerID: "manual", modelID: "chosen", variant: "low" };
    const manual = output(manualModel);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, manual);
    messages.push({ info: { role: "user" }, parts: manual.parts }, { info: { role: "assistant" }, parts: [] });
    const continued = output(manualModel);
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, continued);

    expect(manual.message.model).toEqual(manualModel);
    expect(continued.message.model).toEqual(manualModel);
    expect(classifierCalls).toBe(1);
    expect(toasts).toHaveLength(2);
  });

  test("shows the confidence when routing falls back", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    const toasts = [];
    const client = { tui: { showToast: async ({ body }) => { toasts.push(body); return { data: true }; } } };
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "REASONING", confidence: 0.1 } } }))) as typeof fetch;

    const hooks = await ModelRouter({ client, directory: "/repo" });
    const result = output();
    await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

    expect(result.message.model).toEqual(config.fallback);
    expect(toasts[1]).toEqual({
      title: "Smart Router",
      message: `Low confidence 0.1 · fallback · ${modelLabel(config.fallback)}`,
      variant: "warning",
      duration: 4000,
    });
  });

  test("shows a fallback toast when JevK5 is unavailable", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    const toasts = [];
    const client = { tui: { showToast: async ({ body }) => { toasts.push(body); return { data: true }; } } };
    globalThis.fetch = (async () => { throw new Error("offline"); }) as typeof fetch;
    const warning = spyOn(console, "warn").mockImplementation(() => {});

    try {
      const hooks = await ModelRouter({ client, directory: "/repo" });
      const result = output();
      await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

      expect(result.message.model).toEqual(config.fallback);
      expect(toasts.map((toast) => toast.message)).toEqual([
        "Classifying with JevK5...",
        `Classifier unavailable · fallback · ${modelLabel(config.fallback)}`,
      ]);
      expect(warning).toHaveBeenCalledWith(expect.stringContaining("classifier unavailable"));
    } finally {
      warning.mockRestore();
    }
  });

  test("toast delivery failure does not change the selected model", async () => {
    process.env.OPENCODE_ROUTER_CONFIG = configPath;
    const client = { tui: { showToast: async () => { throw new Error("no TUI"); } } };
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ answers: { tier: { choice: "SIMPLE", confidence: 0.8 } } }))) as typeof fetch;
    const warning = spyOn(console, "warn").mockImplementation(() => {});

    try {
      const hooks = await ModelRouter({ client, directory: "/repo" });
      const result = output();
      await hooks["chat.message"]({ sessionID: "session", agent: "build" }, result);

      expect(result.message.model).toEqual(config.tiers.SIMPLE);
      expect(warning).toHaveBeenCalledTimes(2);
      expect(warning).toHaveBeenCalledWith(expect.stringContaining("toast unavailable"));
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
