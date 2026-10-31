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

function effect(rules: any[], action: string, resource: string) {
  const matches = (pattern: string, value: string) =>
    new RegExp(`^${pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value);
  return rules.findLast((rule) => matches(rule.action, action) && matches(rule.resource, resource))?.effect ?? "ask";
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

  it("asks for arbitrary Supervisor shells while keeping read-only Herdr inspection allowed", () => {
    const supervisor = agent("herdr-supervisor.md");
    const inherited = [
      { action: "*", resource: "*", effect: "allow" },
      { action: "shell", resource: "*", effect: "allow" },
    ];
    const rules = [...inherited, ...supervisor.config.permissions];

    assert.equal(effect(rules, "execute", "*"), "allow");
    assert.equal(effect(rules, "shell", "herdr agent wait core --until done"), "allow");
    assert.equal(effect(rules, "shell", "herdr agent start core"), "ask");
    assert.equal(effect(rules, "subagent", "explore"), "deny");
  });
});
