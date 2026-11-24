/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import { Show, createEffect, createMemo, createSignal, onCleanup } from "solid-js";
import { animalName } from "../lib/herdr-views";
import { executionElapsed, executionState, executionTools, syncExecution } from "../lib/execution";
import { HudCard, HudRows } from "./layout";

export function AgentsHud(props: { context: Context; sessionID: string }) {
  const context = props.context;
  const ids = createMemo(() => context.data.session.family(props.sessionID).filter((id) =>
    id !== props.sessionID && context.data.session.get(id)?.parentID && context.data.session.status(id) === "running"));
  const [now, setNow] = createSignal(Date.now());
  createEffect(() => {
    if (!ids().length) return;
    setNow(Date.now());
    const timer = setInterval(() => setNow(Date.now()), 1000);
    onCleanup(() => clearInterval(timer));
  });
  return <Show when={ids().length}>
    <HudCard context={context} id="agents-panel" accent={context.theme.syntax.function}>
      <HudRows context={context} items={ids()}>{(id) => {
        const name = animalName(process.env, id);
        const [failed, setFailed] = createSignal(false);
        let disposed = false;
        onCleanup(() => { disposed = true; });
        const refresh = () => {
          setFailed(false);
          void Promise.all([
            syncExecution(context, id),
            context.data.session.message.sync(id),
            context.data.session.permission.sync(id),
            context.data.session.form.sync(id),
          ]).catch((error) => {
            if (!disposed) {
              console.error("Could not load subagent activity", error);
              setFailed(true);
            }
          });
        };
        onCleanup(context.data.on("session.execution.started", (event) => {
          if (event.data.sessionID === id) refresh();
        }));
        refresh();
        const state = () => failed() ? "STATE UNAVAILABLE" : executionState(context, id);
        return <text fg={context.theme.text.base} height={1} wrapMode="none" truncate>
          {`󰚩  ${name}  `}
          <span style={{ fg: failed() ? context.theme.text.feedback.error.base
            : state().startsWith("WAITING") ? context.theme.text.feedback.warning.base : context.theme.text.feedback.success.base }}>
            {state()}
          </span>
          {failed() ? "" : `  ${executionTools(context, id).at(-1)?.name ?? "-"}  ${executionElapsed(context, id, now())}`}
        </text>;
      }}</HudRows>
    </HudCard>
  </Show>;
}
