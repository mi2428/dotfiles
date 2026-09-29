import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const DEFAULT_TRIGGER = { providerID: "smart-router", modelID: "auto" };
const ROUTE_METADATA = "modelRouter";

const configPath = () => {
  if (process.env.OPENCODE_ROUTER_CONFIG) return process.env.OPENCODE_ROUTER_CONFIG;
  const root = process.env.XDG_CONFIG_HOME ?? process.env.OPENCODE_CHILD_XDG_CONFIG_HOME ?? join(homedir(), ".config");
  return join(root, "opencode", "model-router.json");
};

const userText = (parts) =>
  parts
    .filter((part) => part.type === "text" && !part.synthetic && typeof part.text === "string")
    .map((part) => part.text.trim())
    .filter(Boolean)
    .join("\n");

const markAutoRoute = (parts, model, tier, confidence, reason) => {
  const part = parts.find((item) => item.type === "text");
  if (!part) return;
  const name = model.modelID.replace(/^gpt-(\d+)-(.+)$/i, (_, version, family) =>
    `GPT-${version} ${family[0].toUpperCase()}${family.slice(1)}`);
  const label = `Smart Router · ${tier ?? "fallback"} (${name})` +
    (confidence === undefined ? "" : ` · ${confidence}`) + (reason ? ` · ${reason}` : "");
  part.metadata = { ...part.metadata, [ROUTE_METADATA]: { model, label, tier } };
};

export const ModelRouter = async () => {
  let config;
  let configError;
  try {
    config = JSON.parse(await readFile(configPath(), "utf8"));
  } catch (error) {
    configError = error;
  }

  return {
    "chat.message": async (_input, output) => {
      const trigger = config?.trigger ?? DEFAULT_TRIGGER;
      if (output.message.model.providerID !== trigger.providerID || output.message.model.modelID !== trigger.modelID)
        return;

      if (!config) {
        throw new Error(
          `[model-router] config unavailable: ${configError instanceof Error ? configError.message : String(configError)}`,
        );
      }
      if (
        typeof config.fallback?.providerID !== "string" ||
        typeof config.fallback?.modelID !== "string" ||
        typeof config.fallback?.variant !== "string"
      )
        throw new Error("[model-router] fallback model is not configured");
      if (
        typeof config.min_context_confidence !== "number" ||
        config.min_context_confidence < 0 || config.min_context_confidence > 1 ||
        typeof config.min_confidence !== "number" ||
        config.min_confidence < 0 || config.min_confidence > 1
      )
        throw new Error("[model-router] confidence thresholds are not configured");

      output.message.model = config.fallback;
      const remember = (tier, confidence, reason) =>
        markAutoRoute(output.parts, output.message.model, tier, confidence, reason);

      const state = userText(output.parts);
      if (!state) return remember();
      if (/(^|[^a-z\d_])router:max(?=$|[^a-z\d_])/i.test(state)) {
        const selected = config.tiers?.REASONING;
        if (!selected?.providerID || !selected?.modelID || !selected?.variant)
          throw new Error("[model-router] REASONING tier is not configured");
        output.message.model = selected;
        return remember("REASONING", undefined, "router:max");
      }

      let tier;
      let confidence;
      try {
        const headers = { "Content-Type": "application/json" };
        if (process.env.OLLAYA_API_KEY) headers.Authorization = `Bearer ${process.env.OLLAYA_API_KEY}`;
        const response = await fetch(config.endpoint, {
          method: "POST",
          headers,
          body: JSON.stringify({
            model: config.model,
            state,
            questions: config.questions,
            keep_alive: config.keep_alive,
          }),
          signal: AbortSignal.timeout(config.timeout_ms),
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);

        const answers = (await response.json()).answers;
        const clarity = answers?.clarity;
        if (!["CLEAR", "CONTEXT_REQUIRED"].includes(clarity?.choice) ||
          typeof clarity?.confidence !== "number" || clarity.confidence < 0 || clarity.confidence > 1)
          throw new Error("invalid context assessment");

        const answer = answers?.tier;
        if (!["SIMPLE", "DEFAULT"].includes(answer?.choice) ||
          typeof answer?.confidence !== "number" || answer.confidence < 0 || answer.confidence > 1)
          throw new Error("invalid tier assessment");
        confidence = answer.confidence;
        if (answer.choice === "SIMPLE" && confidence >= config.min_confidence &&
          clarity.choice === "CLEAR" && clarity.confidence >= config.min_context_confidence) {
          const selected = config.tiers?.SIMPLE;
          if (!selected?.providerID || !selected?.modelID || !selected?.variant)
            throw new Error("[model-router] SIMPLE tier is not configured");
          output.message.model = selected;
          tier = "SIMPLE";
        }
      } catch (error) {
        console.warn(
          `[model-router] routing unavailable; using fallback: ${error instanceof Error ? error.message : String(error)}`,
        );
      }

      remember(tier, confidence);
    },
  };
};

export default ModelRouter;
