/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import { Show, createEffect, createMemo, onCleanup } from "solid-js";
import { HudCard, HudRows } from "./layout";

export type GitSnapshot = {
  files: Awaited<ReturnType<Context["client"]["vcs"]["status"]>>["data"];
  failed: boolean;
};

// One reader feeds both the Main footer and Changes HUD, including when the HUD is hidden.
export function watchGit(context: Context, update: (snapshot: GitSnapshot) => void) {
  const directory = createMemo(() => {
    const route = context.ui.router.current();
    const location = route.type === "session" ? context.data.session.get(route.sessionID)?.location
      : context.location ?? context.data.location.default();
    return location && context.data.location.vcs.info(location)?.provider === "git" ? location.directory : undefined;
  });
  createEffect(() => {
    const cwd = directory();
    update({ files: [], failed: false });
    if (!cwd) return;
    let disposed = false;
    let reading = false;
    const refresh = async () => {
      if (reading) return;
      reading = true;
      try {
        const { data } = await context.client.vcs.status({ location: { directory: cwd } });
        if (!disposed) update({ files: data, failed: false });
      } catch (error) {
        if (!disposed) {
          console.error("Could not read Git status", error);
          update({ files: [], failed: true });
        }
      } finally { reading = false; }
    };
    void refresh();
    const timer = setInterval(refresh, 3000);
    onCleanup(() => { disposed = true; clearInterval(timer); });
  });
}

export function GitStatus(props: { context: Context; snapshot: GitSnapshot }) {
  const counts = createMemo(() => props.snapshot.files.reduce((total, file) => ({
    additions: total.additions + file.additions, deletions: total.deletions + file.deletions,
  }), { additions: 0, deletions: 0 }));
  return <>
    <Show when={props.snapshot.failed}><text fg={props.context.theme.text.feedback.error.base}>Git !</text></Show>
    <Show when={counts().additions > 0 || counts().deletions > 0}>
      <text id="git-status" wrapMode="none" flexShrink={0} fg={props.context.theme.text.muted}>
        <span style={{ fg: props.context.theme.diff.text.added }}>{`+${counts().additions}`}</span>
        {" "}
        <span style={{ fg: props.context.theme.diff.text.removed }}>{`-${counts().deletions}`}</span>
      </text>
    </Show>
  </>;
}

export function ChangesHud(props: { context: Context; snapshot: GitSnapshot }) {
  const context = props.context;
  return <Show when={props.snapshot.failed || props.snapshot.files.length}>
    <HudCard context={context} id="changes-panel" accent={context.theme.diff.text.added}>
      <Show when={props.snapshot.failed} fallback={
        <HudRows context={context} items={props.snapshot.files}>{(file) =>
          <text fg={context.theme.text.base} height={1} wrapMode="none" truncate>
            {`󰈙 ${file.file.replace(/\s+/g, " ")}  `}
            <span style={{ fg: context.theme.diff.text.added }}>{`+${file.additions}`}</span>
            {" "}
            <span style={{ fg: context.theme.diff.text.removed }}>{`-${file.deletions}`}</span>
          </text>
        }</HudRows>
      }>
        <text fg={context.theme.text.feedback.error.base} height={1} wrapMode="none">󰈙 Git status unavailable</text>
      </Show>
    </HudCard>
  </Show>;
}
