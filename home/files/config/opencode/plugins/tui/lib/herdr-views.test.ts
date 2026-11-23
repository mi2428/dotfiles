import { strict as assert } from "node:assert";
import { it } from "bun:test";
import { createAdapter, createViews, shellQuote, viewerArgs, type Run, type Session, type View } from "./herdr-views";

const session = (id: string, parentID?: string): Session => ({ id, parentID, location: { directory: "/repo with 'quote" } });

it("opens each native descendant once without dispatching any work", async () => {
  const sessions = new Map([session("root"), session("child", "root"), session("grandchild", "child"),
    session("other"), session("foreign", "other")].map((item) => [item.id, item]));
  const opened: string[] = [];
  let current = "root";
  const views = createViews({
    current: () => current,
    get: async (id) => { const item = sessions.get(id); assert(item); return item; },
    adapter: {
      open: async (item) => { opened.push(item.id); return { id: `view-${item.id}`, sessionID: item.id, owner: "test" }; },
    },
    warn: () => assert.fail("Unexpected view failure"),
  });
  await Promise.all([views.show("child"), views.show("child"), views.show("grandchild"), views.show("foreign"), views.show("root")]);
  assert.deepEqual(opened, ["child", "grandchild"]);
  current = "other";
  await views.show("child");
  await views.remove("grandchild");
  await views.show("grandchild");
  await views.dispose();
  await views.show("foreign");
  assert.deepEqual(opened, ["child", "grandchild"]);
});

it("does not replay an uncertain spawn or interfere with the child on view failure", async () => {
  let attempts = 0;
  let warnings = 0;
  const views = createViews({ current: () => "root", get: async (id) => session(id, id === "root" ? undefined : "root"),
    adapter: { open: async () => { attempts++; throw new Error("Lost spawn reply"); } },
    warn: () => { warnings++; },
  });
  await views.show("child");
  await views.show("child");
  assert.equal(attempts, 1);
  assert.equal(warnings, 1);
});

it("keeps the view registry across TUI reloads, including spawns still in flight", async () => {
  const registry = new Map<string, View | null>();
  let opens = 0;
  const options = { registry, current: () => "root", get: async (id: string) => session(id, id === "child" ? "root" : undefined),
    adapter: { open: async (): Promise<View> => { opens++; return { id: "view", sessionID: "child", owner: "test" }; } },
    warn: () => assert.fail(),
  };
  const before = createViews(options);
  await before.show("child");
  await before.dispose();
  await createViews(options).show("child");
  assert.equal(opens, 1);
  registry.set("pending", null);
  await createViews(options).show("pending");
  assert.equal(opens, 1);
});

it("does not open a view after the displayed conversation changes during lookup", async () => {
  let current = "root";
  const views = createViews({ current: () => current,
    get: async (id) => { if (id === "child") current = "other"; return session(id, id === "child" ? "root" : undefined); },
    adapter: { open: async () => assert.fail("Stale view") }, warn: () => assert.fail(),
  });
  await views.show("child");
});

it("pins a full TUI to the same config/state without leaking inline config or prompts", () => {
  const args = viewerArgs(session("child"), { XDG_CONFIG_HOME: "/profile", XDG_STATE_HOME: "/state", OPENCODE_CONFIG_CONTENT: "private" });
  assert.deepEqual(args.slice(-4), ["opencode", "--session", "child", "/repo with 'quote"]);
  assert(args.includes("XDG_CONFIG_HOME=/profile"));
  assert(args.includes("XDG_STATE_HOME=/state"));
  assert(!args.includes("private"));
  assert(!args.includes("--prompt"));
  assert.equal(shellQuote("a'b"), "'a'\\''b'");
  assert.equal(createAdapter({}), undefined);
  assert.throws(() => createAdapter({ HERDR_ENV: "1", HC_TERMINAL_ID: "t1" }), /Conflicting/);
});

it("reuses an owned App view without starting another process or closing terminals", async () => {
  const calls: Array<[string, string[]]> = [];
  let labels: Record<string, string> = {};
  let terminals: unknown[] = [];
  const execute: Run = async (command, args) => {
    calls.push([command, args]);
    if (command === "herdr-app") return { spaces: [{ tabs: [{ panes: [{ terminal: "t2" }] }] }] };
    if (args[0] === "ls") return { terminals };
    if (args[0] === "get" && args.at(-1) === "t1") return { state: "live", labels: { "herdr.space": "sp1", "herdr.tab": "tb1" } };
    if (args[0] === "run") {
      for (let index = 0; index < args.length; index++) {
        if (args[index] === "--label") { const [key, value] = args[++index].split("="); labels[key] = value; }
      }
      return { address: "t2", parent: "t1", labels };
    }
    if (args[0] === "get") return { parent: "t1", state: "live", labels };
    return {};
  };
  const adapter = createAdapter({ HC_TERMINAL_ID: "t1", XDG_CONFIG_HOME: "/profile" }, execute)!;
  const view = await adapter.open(session("child", "root"));
  const spawn = calls.find(([, args]) => args[0] === "run")![1];
  assert.deepEqual(spawn.slice(-4), ["opencode", "--session", "child", "/repo with 'quote"]);
  terminals = [{ address: "t2", parent: "t1", state: "live", labels }];
  assert.equal((await createAdapter({ HC_TERMINAL_ID: "t1" }, execute)!.open(session("child", "root"))).id, view.id);
  assert.equal(calls.filter(([, args]) => args[0] === "run").length, 1, "reconnecting reuses an existing owned viewer");
  assert(calls.every(([, args]) => !["kill", "rm"].includes(args[0])));
});

it("runs a legacy viewer only after its shell is ready, never sends an agent prompt", async () => {
  const calls: Array<[string, string[]]> = [];
  let owner: string | undefined;
  const execute: Run = async (command, args) => {
    calls.push([command, args]);
    if (args[0] === "tab") return { result: { root_pane: { pane_id: "w1:p2" } } };
    if (args[1] === "report-metadata") owner = args.find((arg) => arg.startsWith("oc2_view="))!.split("=")[1];
    if (args[1] === "process-info") return { result: { process_info: {
      shell_pid: 4, foreground_process_group_id: 4, foreground_processes: [{ pid: 4 }],
    } } };
    if (args[1] === "get") return { result: { pane: { workspace_id: "w1", tokens: { oc2_view: owner } } } };
    if (args[1] === "list") return { result: { panes: [] } };
    return {};
  };
  const adapter = createAdapter({ HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1" }, execute)!;
  await adapter.open(session("child", "root"));
  const launch = calls.find(([, args]) => args[1] === "run");
  assert(launch?.[1].at(-1)!.includes("'--session' 'child'"));
  assert(calls.every(([, args]) => !args.includes("close") && !args.includes("agent") && !args.includes("prompt")));
});
