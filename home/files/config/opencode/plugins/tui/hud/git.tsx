/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import { resolve } from "node:path";
import { Show, createEffect, createMemo, onCleanup } from "solid-js";
import { CARD_INSET, HudCard, HudRows } from "./layout";

export type GitSnapshot = {
  files: Awaited<ReturnType<Context["client"]["vcs"]["status"]>>["data"];
  failed: boolean;
};

async function editedFiles(context: Context, sessionID: string, directory: string, pending: Set<string>, boundary?: string): Promise<Set<string>> {
  const files = new Set<string>();
  const cursors = new Set<string>();
  let cursor: string | undefined;
  let location: string | undefined = directory;
  do {
    const page = await context.client.message.list({
      sessionID, limit: 100, ...(cursor ? { cursor } : { order: "desc" }),
    });
    for (const message of page.data) {
      if (message.type === "location-switched") {
        location = message.previous?.location.directory;
        continue;
      }
      if (message.type !== "assistant" || (boundary && message.id >= boundary)) continue;
      for (const part of message.content) {
        // Snapshots also include concurrent writers. Only this session's successful patch records prove a write.
        if (part.type !== "tool" || part.name !== "patch") continue;
        if (part.state.status !== "completed") {
          if (part.state.status === "running" || part.state.status === "streaming") pending.add(`${message.id}:${part.id}`);
          continue;
        }
        if (!location) throw new Error("Missing patch location");
        const changed = part.state.metadata?.files;
        if (!Array.isArray(changed)) throw new Error("Missing patch file metadata");
        for (const entry of changed) {
          if (!entry || typeof entry !== "object" || Array.isArray(entry) || typeof entry.file !== "string" || !entry.file) {
            throw new Error("Malformed patch file metadata");
          }
          files.add(resolve(location, entry.file));
        }
      }
    }
    cursor = page.cursor.next ?? undefined;
    if (cursor) {
      if (cursors.has(cursor)) throw new Error("Change history cursor did not advance");
      cursors.add(cursor);
    }
  } while (cursor);
  return files;
}

// One reader feeds both the Main footer and Changes HUD, including when the HUD is hidden.
export function watchGit(context: Context, update: (snapshot: GitSnapshot) => void) {
  const childID = createMemo(() => {
    const route = context.ui.router.current();
    return route.type === "session" && context.data.session.get(route.sessionID)?.parentID ? route.sessionID : undefined;
  });
  const boundary = createMemo(() => {
    const id = childID();
    return id ? context.data.session.get(id)?.revert?.messageID : undefined;
  });
  const directory = createMemo(() => {
    const route = context.ui.router.current();
    const location = route.type === "session" ? context.data.session.get(route.sessionID)?.location
      : context.location ?? context.data.location.default();
    return location && context.data.location.vcs.info(location)?.provider === "git" ? location.directory : undefined;
  });
  createEffect(() => {
    const cwd = directory();
    const id = childID();
    const before = boundary();
    update({ files: [], failed: false });
    if (!cwd) return;
    let disposed = false;
    let reading = false;
    let revision = 0;
    let history: Promise<Set<string>> | undefined;
    const pending = new Set<string>();
    const invalidate = () => { revision++; history = undefined; };
    if (id) {
      onCleanup(context.data.on("session.tool.input.started", (event) => {
        if (event.data.sessionID === id && event.data.name === "patch") {
          pending.add(`${event.data.assistantMessageID}:${event.data.id}`);
        }
      }));
      onCleanup(context.data.on("session.tool.success", (event) => {
        if (event.data.sessionID !== id) return;
        if (pending.delete(`${event.data.assistantMessageID}:${event.data.id}`) || Array.isArray(event.data.metadata?.files)) invalidate();
      }));
      onCleanup(context.data.on("session.tool.failed", (event) => {
        if (event.data.sessionID === id) pending.delete(`${event.data.assistantMessageID}:${event.data.id}`);
      }));
      for (const type of ["session.execution.succeeded", "session.execution.failed", "session.execution.interrupted"] as const) {
        onCleanup(context.data.on(type, (event) => { if (event.data.sessionID === id) invalidate(); }));
      }
    }
    const refresh = async () => {
      if (reading) return;
      reading = true;
      const current = revision;
      try {
        const [{ data }, changed] = await Promise.all([
          context.client.vcs.status({ location: { directory: cwd } }),
          id ? history ??= editedFiles(context, id, cwd, pending, before) : undefined,
        ]);
        if (!disposed && current === revision) update({
          files: changed ? data.filter((file) => changed.has(resolve(cwd, file.file))) : data,
          failed: false,
        });
      } catch (error) {
        if (!disposed && current === revision) {
          history = undefined;
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

export function shortenPath(path: string, width: number): string {
  const parts = path.replace(/\s+/g, " ").split("/");
  const characters = new Intl.Segmenter();
  for (let index = 0; index < parts.length - 1 && Bun.stringWidth(parts.join("/")) > width; index++) {
    parts[index] = characters.segment(parts[index]!).containing(0)?.segment ?? "";
  }
  const result = parts.join("/");
  if (Bun.stringWidth(result) <= width) return result;
  let shortened = "";
  for (const { segment } of characters.segment(result)) {
    if (Bun.stringWidth(shortened + segment + "…") > width) break;
    shortened += segment;
  }
  return shortened + "…";
}

export function ChangesHud(props: { context: Context; snapshot: GitSnapshot; width: number }) {
  const context = props.context;
  return <Show when={props.snapshot.failed || props.snapshot.files.length}>
    <HudCard context={context} id="changes-panel" accent={context.theme.diff.text.added}>
      <Show when={props.snapshot.failed} fallback={
        <HudRows context={context} items={props.snapshot.files}>{(file) => {
          const pathWidth = () => Math.max(1, props.width - CARD_INSET - Bun.stringWidth(`󰈙   +${file.additions} -${file.deletions}`));
          return <box height={1} width="100%" flexDirection="row">
            <text fg={context.theme.text.base} minWidth={0} flexShrink={1} height={1} wrapMode="none" truncate>
              {`󰈙 ${shortenPath(file.file, pathWidth())}`}
            </text>
            <text flexShrink={0} height={1} wrapMode="none">
              {"  "}<span style={{ fg: context.theme.diff.text.added }}>{`+${file.additions}`}</span>
              {" "}
              <span style={{ fg: context.theme.diff.text.removed }}>{`-${file.deletions}`}</span>
            </text>
          </box>;
        }}</HudRows>
      }>
        <text fg={context.theme.text.feedback.error.base} height={1} wrapMode="none">󰈙 Git status unavailable</text>
      </Show>
    </HudCard>
  </Show>;
}
