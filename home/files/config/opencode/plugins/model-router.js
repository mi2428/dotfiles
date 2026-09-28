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

const markAutoRoute = (parts, model, label) => {
  const part = parts.find((item) => item.type === "text");
  if (!part) return;
  part.metadata = { ...part.metadata, [ROUTE_METADATA]: { model, label } };
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
    "chat.message": async (input, output) => {
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

      output.message.model = config.fallback;
      const remember = (label) => markAutoRoute(output.parts, output.message.model, label);

      const state = userText(output.parts);
      if (!state) return remember();

      let label = "Smart Router · fallback";
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

        const answer = (await response.json()).answers?.tier;
        const selected = config.tiers?.[answer?.choice];
        if (
          typeof answer?.confidence === "number" &&
          answer.confidence >= config.min_confidence &&
          typeof selected?.providerID === "string" &&
          typeof selected?.modelID === "string" &&
          typeof selected?.variant === "string"
        ) {
          output.message.model = selected;
          label = `Smart Router · ${answer.choice} · confidence ${answer.confidence}`;
        } else if (typeof answer?.confidence === "number") {
          label = `Smart Router · fallback · confidence ${answer.confidence}`;
        }
      } catch (error) {
        console.warn(
          `[model-router] classifier unavailable; using fallback: ${error instanceof Error ? error.message : String(error)}`,
        );
      }

      remember(label);
    },
  };
};

export default ModelRouter;
