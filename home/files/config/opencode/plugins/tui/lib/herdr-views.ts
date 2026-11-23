import { execFile } from "node:child_process";
import { randomInt, randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { Database } from "bun:sqlite";

type Env = Record<string, string | undefined>;
export type Run = (command: string, args: string[]) => Promise<any>;
export type Session = { id: string; parentID?: string; location: { directory: string } };
export type View = { id: string; sessionID: string; owner: string };
// Visible tabs may be taken over at any time. Leave even failed spawns for manual
// inspection: a token check followed by close cannot atomically protect a person's tab.
export interface Adapter {
  open(session: Session): Promise<View>;
}

export const run: Run = (command, args) => new Promise((resolve, reject) => {
  execFile(command, args, { timeout: 8_000, maxBuffer: 2 * 1024 * 1024 }, (error, stdout) => {
    if (error) return reject(new Error(`${command} ${args.slice(0, 2).join(" ")} failed`));
    try {
      const result = stdout.trim() ? JSON.parse(stdout) : {};
      if (result.error) throw new Error(`${command} request rejected`);
      resolve(result);
    } catch (error) { reject(error); }
  });
});

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

export const ANIMALS = (
  "Ant Bat Bear Bee Beetle Boar Buffalo Camel Cat Chicken Cobra Cow Crab Crow Deer Dog " +
  "Dolphin Duck Eagle Fish Fly Fox Frog Giraffe Goat Goose Gorilla Hamster Hippo Horse Koala Lion " +
  "Lizard Lobster Monkey Mouse Octopus Otter Owl Panda Parrot Peacock Penguin Pig Pigeon Rabbit Raccoon Rat " +
  "Seal Shark Sheep Shrimp Snail Snake Sparrow Spider Squid Swan Tiger Turtle Walrus Whale Wolf Zebra"
).split(" ");

export function animalName(env: Env, sessionID: string): string {
  const directory = join(env.XDG_STATE_HOME || join(env.HOME || homedir(), ".local", "state"), "opencode-herdr");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const db = new Database(join(directory, "animal-names.sqlite"));
  try {
    db.exec("PRAGMA busy_timeout = 2000");
    db.exec("CREATE TABLE IF NOT EXISTS names (session_id TEXT PRIMARY KEY, animal TEXT NOT NULL UNIQUE)");
    // The unique ledger serializes other parent TUIs too. Names belong to sessions,
    // not panes, task titles, or plugin generations; closing a tab does not free one.
    return db.transaction(() => {
      const saved = db.query<{ animal: string }, [string]>("SELECT animal FROM names WHERE session_id = ?").get(sessionID);
      if (saved) return saved.animal;
      const used = new Set(db.query<{ animal: string }, []>("SELECT animal FROM names").all().map((row) => row.animal));
      for (let round = 1; ; round++) {
        // A finite vocabulary must eventually repeat; a short suffix keeps names unique.
        const available = ANIMALS.map((name) => round === 1 ? name : `${name}${round}`).filter((name) => !used.has(name));
        if (!available.length) continue;
        const name = available[randomInt(available.length)];
        db.query("INSERT INTO names (session_id, animal) VALUES (?, ?)").run(sessionID, name);
        return name;
      }
    }).immediate();
  } finally {
    db.close();
  }
}

export async function nameTabs(env: Env, execute: Run = run): Promise<void> {
  if (env.HERDR_ENV !== "1" || !env.HERDR_PANE_ID || env.OPENCODE_HERDR_VIEWER === "1") return;
  if (env.HC_TERMINAL_ID) throw new Error("Conflicting Herdr terminal identities");
  const parent = (await execute("herdr", ["pane", "get", env.HERDR_PANE_ID])).result?.pane;
  if (!parent?.tab_id || !parent.workspace_id) throw new Error("Herdr parent is unavailable");
  if (parent.tokens?.oc2_view) return;
  await execute("herdr", ["tab", "rename", parent.tab_id, "Main"]);
  const panes = (await execute("herdr", ["pane", "list", "--workspace", parent.workspace_id])).result?.panes;
  if (!Array.isArray(panes)) throw new Error("Herdr returned an invalid pane list");
  for (const pane of panes) {
    if (pane.tokens?.oc2_parent !== env.HERDR_PANE_ID || !pane.tokens?.oc2_view || !pane.tokens?.oc2_session) continue;
    if (typeof pane.tab_id !== "string" || typeof pane.pane_id !== "string") throw new Error("Herdr returned an invalid viewer pane");
    if (pane.tab_id === parent.tab_id) continue;
    // Earlier asynchronous renames may leave this list stale after a tab is released or moved.
    const current = (await execute("herdr", ["pane", "get", pane.pane_id])).result?.pane;
    if (!current) throw new Error("Herdr viewer is unavailable");
    if (current.tab_id !== pane.tab_id || current.tokens?.oc2_parent !== pane.tokens.oc2_parent
      || current.tokens?.oc2_session !== pane.tokens.oc2_session || current.tokens?.oc2_view !== pane.tokens.oc2_view) continue;
    const name = animalName(env, pane.tokens.oc2_session);
    await execute("herdr", ["tab", "rename", pane.tab_id, `󰚩  ${name}`]);
  }
}

// A viewer joins the same service/config namespace; it never starts work or chooses an agent.
export function viewerArgs(session: Session, env: Env): string[] {
  const args = ["OPENCODE_HERDR_VIEWER=1", `OPENCODE_HERDR_SESSION=${session.id}`,
    'OPENCODE_CLI_CONFIG_CONTENT={"session":{"thinking":"show","grouping":"none","tps":true},"attention":{"sound":false,"notifications":false}}'];
  for (const key of ["HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "HERDR_APP_HOME"]) {
    if (env[key]) args.push(`${key}=${env[key]}`);
  }
  return ["-u", "OPENCODE_CONFIG_CONTENT", ...args,
    "opencode", "--session", session.id, session.location.directory];
}

export function createAdapter(env: Env, execute: Run = run): Adapter | undefined {
  if (env.HERDR_ENV === "1" && env.HC_TERMINAL_ID) throw new Error("Conflicting Herdr terminal identities");
  if (env.HC_TERMINAL_ID) {
    const parent = env.HC_TERMINAL_ID;
    return {
      async open(session) {
        const terminal = await execute("hc", ["get", "--json", parent]);
        const space = terminal.labels?.["herdr.space"];
        if (terminal.state !== "live" || !space || !terminal.labels?.["herdr.tab"]) throw new Error("Herdr App parent is unavailable");
        const { terminals } = await execute("hc", ["ls", "--json", "--label", `oc2.session=${session.id}`]);
        if (!Array.isArray(terminals)) throw new Error("Herdr Core returned an invalid terminal list");
        const existing = terminals.find((item) => item.parent === parent && item.state === "live" && item.labels?.["oc2.view"]);
        if (existing) {
          if (typeof existing.address !== "string") throw new Error("Herdr Core returned an invalid viewer address");
          if (!containsTerminal(await execute("herdr-app", ["ls"]), existing.address)) throw new Error("Existing child view is not visible");
          return { id: existing.address, sessionID: session.id, owner: existing.labels["oc2.view"] };
        }
        const owner = randomUUID();
        const tab = `tb${owner.replaceAll("-", "")}`;
        const result = await execute("hc", ["run", "--json", "--bg", "--no-notify", "--parent", parent,
          "--cwd", session.location.directory, "--label", `herdr.space=${space}`, "--label", `herdr.tab=${tab}`,
          "--label", `oc2.view=${owner}`, "--label", `oc2.session=${session.id}`,
          "--", "env", ...viewerArgs(session, env)]);
        if (typeof result.address !== "string" || !result.address || result.parent !== parent || result.labels?.["oc2.view"] !== owner)
          throw new Error("Herdr App returned an unverified viewer; inspect terminals before retrying");
        const view = { id: result.address, sessionID: session.id, owner };
        for (let attempt = 0; attempt < 4; attempt++) {
          const layout = await execute("herdr-app", ["ls"]);
          if (containsTerminal(layout, view.id)) return view;
          await delay(500);
        }
        throw new Error("Herdr App did not display the viewer; inspect terminals");
      },
    };
  }
  if (env.HERDR_ENV === "1" && env.HERDR_PANE_ID) {
    const parent = env.HERDR_PANE_ID;
    return {
      async open(session) {
        const owner = randomUUID();
        const anchor = (await execute("herdr", ["pane", "get", parent])).result?.pane;
        if (!anchor?.workspace_id) throw new Error("Herdr parent is unavailable");
        const panes = (await execute("herdr", ["pane", "list", "--workspace", anchor.workspace_id])).result?.panes;
        if (!Array.isArray(panes)) throw new Error("Herdr returned an invalid pane list");
        const existing = panes.find((pane) => pane.tokens?.oc2_parent === parent
          && pane.tokens?.oc2_session === session.id && pane.tokens?.oc2_view);
        if (existing) {
          if (typeof existing.pane_id !== "string") throw new Error("Herdr returned an invalid viewer pane");
          return { id: existing.pane_id, sessionID: session.id, owner: existing.tokens.oc2_view };
        }
        const result = await execute("herdr", ["tab", "create", "--workspace", anchor.workspace_id, "--no-focus",
          "--label", `󰚩  ${animalName(env, session.id)}`, "--cwd", session.location.directory]);
        const id = result.result?.root_pane?.pane_id;
        if (typeof id !== "string" || !id) throw new Error("Herdr returned an unverified pane; inspect panes before retrying");
        const view = { id, sessionID: session.id, owner };
        await execute("herdr", ["pane", "report-metadata", id, "--source", "dotfiles.oc2-views",
          "--token", `oc2_view=${owner}`, "--token", `oc2_session=${session.id}`, "--token", `oc2_parent=${parent}`]);
        let ready = false;
        for (let attempt = 0; attempt < 20; attempt++) {
          const info = (await execute("herdr", ["pane", "process-info", "--pane", id])).result?.process_info;
          if (info?.foreground_process_group_id === info?.shell_pid && info?.foreground_processes?.length === 1
            && info.foreground_processes[0].pid === info.shell_pid) { ready = true; break; }
          await delay(100);
        }
        if (!ready) throw new Error("Herdr viewer shell is not ready; inspect panes");
        await execute("herdr", ["pane", "run", id, ["exec", "env", ...viewerArgs(session, env)].map(shellQuote).join(" ")]);
        return view;
      },
    };
  }
}

function containsTerminal(value: unknown, id: string): boolean {
  if (!value || typeof value !== "object") return false;
  if (Array.isArray(value)) return value.some((item) => containsTerminal(item, id));
  const item = value as Record<string, unknown>;
  return item.terminal === id || item.address === id || Object.values(item).some((child) => containsTerminal(child, id));
}

export function createViews(options: {
  adapter: Adapter;
  current: () => string | undefined;
  get: (id: string) => Promise<Session>;
  warn: (message: string) => void;
  registry?: {
    has(id: string): boolean;
    set(id: string, view: View | null): void;
  };
}) {
  // Null records mark attempted spawns, including uncertain failures. The TUI keeps this across reloads.
  const views = options.registry ?? new Map<string, View | null>();
  const deleted = new Set<string>();
  let chain = Promise.resolve();
  let disposed = false;
  async function root(session: Session) {
    const seen = new Set<string>();
    while (session.parentID) {
      if (seen.has(session.id)) throw new Error("Session ancestry contains a cycle");
      seen.add(session.id);
      session = await options.get(session.parentID);
    }
    return session.id;
  }
  const enqueue = (work: () => Promise<void>) => {
    chain = chain.then(work).catch(() => options.warn("子の画面接続に失敗しました。子の実行は継続します。"));
    return chain;
  };
  return {
    show(id: string) {
      return enqueue(async () => {
        if (disposed || deleted.has(id) || views.has(id)) return;
        const current = options.current();
        if (!current) return;
        const session = await options.get(id);
        if (!session.parentID || await root(session) !== await root(await options.get(current))) return;
        if (disposed || deleted.has(id) || options.current() !== current) return;
        views.set(id, null); // A failed spawn may have created a view: never blindly retry.
        const view = await options.adapter.open(session);
        views.set(id, view);
      });
    },
    remove(id: string) {
      deleted.add(id);
      // Token checks and pane closure are not atomic. A person may have taken over the
      // view, so session deletion must never close it; close visible tabs manually.
      return chain;
    },
    // Keep completed full TUI views for review. Closing the parent TUI does not cancel work.
    dispose() { disposed = true; return chain; },
  };
}
