import type { Context } from "@opencode/plugin/tui/context";

export async function syncExecution(context: Context, sessionID: string): Promise<void> {
  // execution.started updates cached status, but not the current run's timestamps.
  context.data.session.invalidate(sessionID);
  await context.data.session.sync(sessionID);
}

export function executionStart(context: Context, sessionID: string): number | undefined {
  const time = context.data.session.get(sessionID)?.time;
  // The server publishes this field, but the generated client types omit it.
  if (!time || !("busy" in time)) return undefined;
  if (typeof time.busy !== "number" || !Number.isFinite(time.busy)) throw new Error("Invalid session execution timestamp");
  return time.busy;
}

export function executionState(context: Context, sessionID: string) {
  if (context.data.session.status(sessionID) === "running") {
    if (context.data.session.permission.list(sessionID)?.length) return "WAITING FOR APPROVAL";
    if (context.data.session.form.list(sessionID)?.length) return "WAITING FOR ANSWER";
    return "RUNNING";
  }
  const outcome = context.data.session.get(sessionID)?.outcome;
  return outcome ? { succeeded: "DONE", failed: "FAILED", interrupted: "INTERRUPTED" }[outcome] : "IDLE";
}

export function executionTools(context: Context, sessionID: string) {
  const start = executionStart(context, sessionID);
  if (context.data.session.status(sessionID) !== "running" || start === undefined) return [];
  return context.data.session.message.list(sessionID).flatMap((message) => message.type === "assistant"
    ? message.content.filter((part) => part.type === "tool") : [])
    .filter((part) => part.time.created >= start && (part.state.status === "running" || part.state.status === "streaming"));
}

export function executionElapsed(context: Context, sessionID: string, now: number): string {
  const start = executionStart(context, sessionID);
  const end = context.data.session.status(sessionID) === "running" ? now : context.data.session.get(sessionID)?.time.idle;
  if (start === undefined || end === undefined || end < start) return "--";
  const seconds = Math.floor((end - start) / 1000);
  return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
}
