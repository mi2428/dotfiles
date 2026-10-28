export function expandCommand(template, args) {
  if (template.includes("$ARGUMENTS")) return template.replaceAll("$ARGUMENTS", args);
  return args.trim() ? `${template}\n\n${args}` : template;
}

export function resolveMode(args, defaultMode, normalize) {
  return normalize(args.trim() || defaultMode);
}

export function readStoredMode(value, normalize) {
  if (value === undefined) return undefined;
  const mode = normalize(value);
  if (!mode) throw new Error("Ponytail stored mode is invalid");
  return mode;
}

export async function registerPonytail(ctx, source, readLegacyMode) {
  const readMode = async () => {
    const stored = readStoredMode(await ctx.storage.get("mode"), source.normalizePersistedMode);
    return stored || readLegacyMode() || source.getDefaultMode();
  };

  await readMode();

  await ctx.command.transform((editor) => {
    for (const command of source.commands) {
      editor.add({
        name: command.name,
        description: command.description,
        execute: async ({ sessionID, prompt, delivery }) => {
          if (command.name === "ponytail") {
            const mode = resolveMode(prompt.text, source.getDefaultMode(), source.normalizePersistedMode);
            if (!mode) throw new Error("Usage: /ponytail [lite|full|ultra|off]");
            await ctx.storage.set("mode", mode);
          }
          await ctx.session.prompt({
            ...prompt,
            sessionID,
            text: expandCommand(command.template, prompt.text),
            delivery,
          });
        },
      });
    }
  });

  await ctx.session.hook("prompt", async (event) => {
    if (source.isDeactivationCommand(event.prompt.text)) {
      await ctx.storage.set("mode", "off");
    }
  });

  await ctx.session.hook("context", async (event) => {
    const mode = await readMode();
    if (mode === "off") return;
    const text = source.getPonytailInstructions(mode);
    if (typeof text !== "string" || !text.trim()) {
      throw new Error("Ponytail generated empty instructions");
    }
    event.system.push({ type: "text", text });
  });
}
