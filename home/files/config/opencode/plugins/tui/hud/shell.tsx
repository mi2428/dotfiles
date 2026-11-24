/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import { Show, createEffect, createMemo, createSignal, onCleanup } from "solid-js";
import { HudCard, HudRows } from "./layout";

export function ShellHud(props: { context: Context; sessionID: string }) {
  const context = props.context;
  const [failed, setFailed] = createSignal(false);
  const directory = createMemo(() => context.data.session.get(props.sessionID)?.location.directory);
  createEffect(() => {
    const cwd = directory();
    setFailed(false);
    if (!cwd) return;
    let disposed = false;
    onCleanup(() => { disposed = true; });
    void context.data.shell.sync({ directory: cwd }).catch((error) => {
      if (!disposed) {
        console.error("Could not load shell activity", error);
        setFailed(true);
      }
    });
  });
  const shells = createMemo(() => {
    const session = context.data.session.get(props.sessionID);
    if (!session) return [];
    return context.data.shell.list(session.location).filter((shell) =>
      shell.metadata.sessionID === props.sessionID && shell.status === "running");
  });
  return <Show when={failed() || shells().length}>
    <HudCard context={context} id="shell-panel" accent={context.theme.text.feedback.warning.base}>
      <Show when={!failed()} fallback={<text fg={context.theme.text.feedback.error.base}>  Shell status unavailable</text>}>
        <HudRows context={context} items={shells()}>{(shell) =>
        <text fg={context.theme.text.base} height={1} wrapMode="none" truncate>
          {`  ${shell.command.split("\n", 1)[0]}`}
        </text>
        }</HudRows>
      </Show>
    </HudCard>
  </Show>;
}
