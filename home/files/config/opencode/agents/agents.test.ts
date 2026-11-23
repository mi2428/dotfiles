import { strict as assert } from "node:assert";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, it } from "bun:test";

function agent(name: string) {
  const text = readFileSync(new URL(name, import.meta.url), "utf8");
  const match = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  assert(match, `Invalid agent file: ${name}`);
  return { config: Bun.YAML.parse(match[1]) as any, system: match[2].trim() };
}

describe("V2 agents", () => {
  it("uses the Chat agent body as its system without fixing the model or truncating later instructions", () => {
    const chat = agent("chat.md");
    assert.equal(chat.config.mode, "primary");
    assert.equal(chat.config.model, undefined);
    assert.match(chat.system, /^You are a general-purpose conversational assistant\./);
    assert.doesNotMatch(chat.system, /<\/?chat-agent>/);
    assert.equal(
      existsSync(fileURLToPath(new URL("../plugins/chat-system.js", import.meta.url))),
      false,
    );
  });
});
