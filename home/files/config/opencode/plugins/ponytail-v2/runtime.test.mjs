import assert from "node:assert/strict";
import test from "node:test";
import { expandCommand, readStoredMode, registerPonytail, resolveMode } from "./runtime.mjs";

const normalize = (value) => {
  if (typeof value !== "string") return null;
  const mode = value.trim().toLowerCase();
  return ["off", "lite", "full", "ultra", "review"].includes(mode) ? mode : null;
};

test("resolves and validates persistent modes", () => {
  assert.equal(resolveMode(" ULTRA ", "full", normalize), "ultra");
  assert.equal(resolveMode("", "lite", normalize), "lite");
  assert.equal(resolveMode("invalid", "full", normalize), null);
  assert.equal(readStoredMode(undefined, normalize), undefined);
  assert.equal(readStoredMode("off", normalize), "off");
  assert.throws(() => readStoredMode(42, normalize), /stored mode is invalid/);
});

test("expands the pinned command templates", () => {
  assert.equal(expandCommand("Switch to $ARGUMENTS mode.", "lite"), "Switch to lite mode.");
  assert.equal(expandCommand("Review changes.", "src"), "Review changes.\n\nsrc");
  assert.equal(expandCommand("Review changes.", ""), "Review changes.");
});

test("registers V2 commands and session hooks", async () => {
  const commands = new Map();
  const hooks = new Map();
  const prompts = [];
  const storage = new Map();
  const ctx = {
    command: { transform: async (edit) => edit({ add: (command) => commands.set(command.name, command) }) },
    session: {
      hook: async (name, hook) => hooks.set(name, hook),
      prompt: async (prompt) => prompts.push(prompt),
    },
    storage: {
      get: async (key) => storage.get(key),
      set: async (key, value) => storage.set(key, value),
    },
  };
  const source = {
    commands: [
      { name: "ponytail", description: "Switch mode", template: "Switch to $ARGUMENTS mode." },
      { name: "ponytail-help", description: "Show help", template: "Show help." },
    ],
    getDefaultMode: () => "full",
    getPonytailInstructions: (mode) => `rules:${mode}`,
    isDeactivationCommand: (text) => text.toLowerCase() === "normal mode",
    normalizePersistedMode: normalize,
  };

  await registerPonytail(ctx, source, () => null);
  const system = [];
  await hooks.get("context")({ system });
  assert.deepEqual(system, [{ type: "text", text: "rules:full" }]);

  await commands.get("ponytail").execute({
    sessionID: "session-1",
    prompt: { text: "ultra" },
    delivery: "steer",
  });
  assert.equal(storage.get("mode"), "ultra");
  assert.equal(prompts[0].text, "Switch to ultra mode.");
  await assert.rejects(
    commands.get("ponytail").execute({ sessionID: "session-1", prompt: { text: "invalid" }, delivery: "steer" }),
    /Usage: \/ponytail/,
  );

  await hooks.get("prompt")({ prompt: { text: "normal mode" } });
  const offSystem = [];
  await hooks.get("context")({ system: offSystem });
  assert.equal(storage.get("mode"), "off");
  assert.deepEqual(offSystem, []);
});

test("migrates the legacy mode into plugin storage once", async () => {
  const hooks = new Map();
  const storage = new Map();
  let legacyReads = 0;
  const ctx = {
    command: { transform: async () => {} },
    session: { hook: async (name, hook) => hooks.set(name, hook) },
    storage: {
      get: async (key) => storage.get(key),
      set: async (key, value) => storage.set(key, value),
    },
  };
  const source = {
    commands: [],
    getDefaultMode: () => "full",
    getPonytailInstructions: (mode) => `rules:${mode}`,
    isDeactivationCommand: () => false,
    normalizePersistedMode: normalize,
  };

  await registerPonytail(ctx, source, () => {
    legacyReads += 1;
    return "ultra";
  });
  assert.equal(storage.get("mode"), "ultra");
  await hooks.get("context")({ system: [] });
  await hooks.get("context")({ system: [] });
  assert.equal(legacyReads, 1);

  await registerPonytail(ctx, source, () => {
    throw new Error("stored mode must skip legacy migration");
  });
});
