import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import {
  applyHappierSessionSelection,
  happierSessionSelectionFromEnvironment,
} from "./tui";

describe("Happier OpenCode selection", () => {
  it("parses and applies the requested agent and model", async () => {
    const selection = happierSessionSelectionFromEnvironment({
      OPENCODE_HAPPIER_AGENT: " Herdr Supervisor ",
      OPENCODE_HAPPIER_MODEL: "openai/gpt-5.4-mini",
    });
    const calls: unknown[] = [];
    const client = {
      v2: {
        session: {
          switchAgent: async (...args: unknown[]) => calls.push(["agent", ...args]),
          switchModel: async (...args: unknown[]) => calls.push(["model", ...args]),
        },
      },
    };

    await applyHappierSessionSelection(client as never, "ses_test", selection);

    assert.deepEqual(calls, [
      ["agent", { sessionID: "ses_test", agent: "Herdr Supervisor" }, { throwOnError: true }],
      [
        "model",
        {
          sessionID: "ses_test",
          model: { providerID: "openai", id: "gpt-5.4-mini" },
        },
        { throwOnError: true },
      ],
    ]);
  });
});
