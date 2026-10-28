import { readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { createRequire } from "node:module";
import path from "node:path";
import { Plugin } from "@opencode/plugin";
import { registerPonytail } from "./runtime.mjs";

const require = createRequire(import.meta.url);

function loadSource(sourceRoot) {
  if (typeof sourceRoot !== "string" || !path.isAbsolute(sourceRoot)) {
    throw new Error("Ponytail requires an absolute options.sourceRoot");
  }

  const instructions = require(path.join(sourceRoot, "hooks/ponytail-instructions.js"));
  const config = require(path.join(sourceRoot, "hooks/ponytail-config.js"));
  const frontmatter = require(path.join(sourceRoot, ".opencode/plugins/ponytail-frontmatter.cjs"));
  for (const fn of [
    instructions.getPonytailInstructions,
    config.getDefaultMode,
    config.isDeactivationCommand,
    config.normalizePersistedMode,
    frontmatter.parseCommandFile,
  ]) {
    if (typeof fn !== "function") throw new Error("Ponytail source is incompatible");
  }

  const commandDir = path.join(sourceRoot, ".opencode/command");
  const commands = readdirSync(commandDir)
    .filter((file) => file.endsWith(".md"))
    .sort()
    .map((file) => {
      const parsed = frontmatter.parseCommandFile(path.join(commandDir, file));
      if (!parsed?.template) throw new Error(`Invalid Ponytail command: ${file}`);
      return { name: path.basename(file, ".md"), ...parsed };
    });
  if (!commands.some(({ name }) => name === "ponytail")) {
    throw new Error("Ponytail source has no /ponytail command");
  }

  return { ...instructions, ...config, commands };
}

function readLegacyMode(normalize) {
  const configHome = process.env.XDG_CONFIG_HOME || path.join(homedir(), ".config");
  try {
    return normalize(readFileSync(path.join(configHome, "opencode/.ponytail-active"), "utf8").trim());
  } catch {
    return null;
  }
}

export default Plugin.define({
  id: "ponytail",
  async setup(ctx) {
    const source = loadSource(ctx.options.sourceRoot);
    await registerPonytail(ctx, source, () => readLegacyMode(source.normalizePersistedMode));
  },
});
