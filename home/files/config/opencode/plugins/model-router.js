import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const DEFAULT_TRIGGER = { providerID: "smart-router", modelID: "auto" };
const ROUTE_METADATA = "modelRouter";

const configPath = () => {
  if (process.env.OPENCODE_ROUTER_CONFIG) return process.env.OPENCODE_ROUTER_CONFIG;
  const root = process.env.OPENCODE_CHILD_XDG_CONFIG_HOME ?? process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config");
  return join(root, "opencode", "model-router.json");
};

const userText = (parts) =>
  parts
    .filter((part) => part.type === "text" && !part.synthetic && typeof part.text === "string")
    .map((part) => part.text.trim())
    .filter(Boolean)
    .join("\n");

const sameModel = (left, right) =>
  left?.providerID === right?.providerID &&
  left?.modelID === right?.modelID &&
  left?.variant === right?.variant;

const markAutoRoute = (parts, model) => {
  const part = parts.find((item) => item.type === "text");
  if (!part) return;
  part.metadata = { ...part.metadata, [ROUTE_METADATA]: { model } };
};

const previousAutoRoute = async (client, directory, sessionID) => {
  if (!client) return;
  const response = await client.session.messages({
    path: { id: sessionID },
    query: { directory, limit: 2 },
  });
  const latestUser = response.data?.findLast((message) => message.info?.role === "user");
  const marker = latestUser?.parts.find((part) => part.type === "text" && part.metadata?.[ROUTE_METADATA]);
  return marker?.metadata?.[ROUTE_METADATA]?.model;
};

export const ModelRouter = async ({ client, directory } = {}) => {
  const routes = new Map();
  const showRoute = async (message, variant = "info", duration = 4000) => {
    if (!client) return;
    try {
      await client.tui.showToast({
        body: { title: "Smart Router", message, variant, duration },
        query: { directory },
        throwOnError: true,
      });
    } catch (error) {
      console.warn(`[model-router] toast unavailable: ${error instanceof Error ? error.message : String(error)}`);
    }
  };
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
      const triggered =
        output.message.model.providerID === trigger.providerID && output.message.model.modelID === trigger.modelID;
      if (!triggered) {
        if (!routes.has(input.sessionID))
          routes.set(input.sessionID, await previousAutoRoute(client, directory, input.sessionID));
        if (!sameModel(output.message.model, routes.get(input.sessionID))) {
          routes.set(input.sessionID, undefined);
          return;
        }
      }

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
      const remember = () => {
        markAutoRoute(output.parts, output.message.model);
        routes.set(input.sessionID, output.message.model);
      };

      const state = userText(output.parts);
      if (!state) return remember();

      await showRoute("Classifying with JevK5...", "info", config.timeout_ms + 2000);
      let result = "Classifier unavailable · fallback";
      let variant = "warning";
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
        const confidence = typeof answer?.confidence === "number" ? ` · confidence ${answer.confidence}` : "";
        if (
          typeof answer?.confidence === "number" &&
          answer.confidence >= config.min_confidence &&
          typeof selected?.providerID === "string" &&
          typeof selected?.modelID === "string" &&
          typeof selected?.variant === "string"
        ) {
          output.message.model = selected;
          result = `${answer.choice}${confidence}`;
          variant = "success";
        } else {
          result =
            typeof answer?.confidence === "number" && answer.confidence < config.min_confidence
              ? `Low confidence ${answer.confidence} · fallback`
              : `Invalid classification${confidence} · fallback`;
        }
      } catch (error) {
        console.warn(
          `[model-router] classifier unavailable; using fallback: ${error instanceof Error ? error.message : String(error)}`,
        );
      }

      remember();
      const { providerID, modelID, variant: effort } = output.message.model;
      await showRoute(`${result} · ${providerID}/${modelID} / ${effort}`, variant);
    },
  };
};

export default ModelRouter;
