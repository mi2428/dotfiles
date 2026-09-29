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

const markAutoRoute = (parts, model, label, tier) => {
  const part = parts.find((item) => item.type === "text");
  if (!part) return;
  part.metadata = { ...part.metadata, [ROUTE_METADATA]: { model, label, tier } };
};

const previousRoute = async (client, directory, sessionID, messageID) => {
  // ponytail: inspect the last 100 messages; paginate if a tool-heavy turn hides the previous user message.
  const response = await client.session.messages({ path: { id: sessionID }, query: { directory, limit: 100 } });
  if (response.error || !Array.isArray(response.data)) throw new Error("session context unavailable");
  const previous = response.data.findLast((item) => item.info?.role === "user" && item.info.id !== messageID);
  const part = previous?.parts?.find((item) => item.type === "text" && item.metadata?.[ROUTE_METADATA]);
  return part?.metadata?.[ROUTE_METADATA];
};

export const ModelRouter = async ({ client, directory } = {}) => {
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
      if (
        typeof config.min_context_confidence !== "number" ||
        config.min_context_confidence < 0 || config.min_context_confidence > 1
      )
        throw new Error("[model-router] context confidence threshold is not configured");

      output.message.model = config.fallback;
      const remember = (label, tier) => markAutoRoute(output.parts, output.message.model, label, tier);

      const state = userText(output.parts);
      if (!state) return remember();
      if (/(^|[^a-z\d_])router:max(?=$|[^a-z\d_])/i.test(state)) {
        const selected = config.tiers?.REASONING;
        if (!selected?.providerID || !selected?.modelID || !selected?.variant)
          throw new Error("[model-router] REASONING tier is not configured");
        output.message.model = selected;
        return remember("Smart Router · REASONING · router:max", "REASONING");
      }

      let label = "Smart Router · fallback";
      let tier;
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
        if (
          !["CLEAR", "CONTEXT_REQUIRED"].includes(clarity?.choice) ||
          typeof clarity?.confidence !== "number"
        )
          throw new Error("invalid context assessment");

        const answer = answers?.tier;
        const selectedTier = config.tiers?.[answer?.choice];
        const confident = typeof answer?.confidence === "number" && answer.confidence >= config.min_confidence &&
          typeof selectedTier?.providerID === "string" && typeof selectedTier?.modelID === "string" &&
          typeof selectedTier?.variant === "string";
        if (clarity.choice === "CONTEXT_REQUIRED" && clarity.confidence >= config.min_context_confidence && !confident) {
          if (typeof answer?.confidence === "number")
            label = `Smart Router · fallback · confidence ${answer.confidence}`;
        } else if (clarity.choice === "CONTEXT_REQUIRED" && clarity.confidence >= config.min_context_confidence) {
          const previous = client && await previousRoute(client, directory, input.sessionID, input.messageID);
          const selected = [config.fallback, ...Object.values(config.tiers)].find(
            (model) => model.providerID === previous?.model?.providerID &&
              model.modelID === previous?.model?.modelID && model.variant === previous?.model?.variant,
          );
          if (selected) {
            const previousTier = config.tiers?.[previous.tier];
            tier = previousTier?.providerID === selected.providerID && previousTier?.modelID === selected.modelID &&
              previousTier?.variant === selected.variant ? previous.tier : undefined;
            const rank = Object.keys(config.tiers);
            const previousRank = selected === config.fallback ? rank.length : rank.findIndex((name) =>
              config.tiers[name].providerID === selected.providerID &&
              config.tiers[name].modelID === selected.modelID && config.tiers[name].variant === selected.variant);
            if (rank.indexOf(answer.choice) > previousRank) {
              output.message.model = selectedTier;
              tier = answer.choice;
              label = `Smart Router · ${tier} · confidence ${answer.confidence}`;
            } else {
              output.message.model = selected;
              label = `Smart Router · ${tier ?? (selected === config.fallback ? "fallback" : "context")} · inherited`;
            }
          } else {
            label = "Smart Router · fallback · context missing";
          }
        } else if (confident) {
          output.message.model = selectedTier;
          tier = answer.choice;
          label = `Smart Router · ${tier} · confidence ${answer.confidence}`;
        } else if (typeof answer?.confidence === "number") {
          label = `Smart Router · fallback · confidence ${answer.confidence}`;
        }
      } catch (error) {
        console.warn(
          `[model-router] routing unavailable; using fallback: ${error instanceof Error ? error.message : String(error)}`,
        );
      }

      remember(label, tier);
    },
  };
};

export default ModelRouter;
