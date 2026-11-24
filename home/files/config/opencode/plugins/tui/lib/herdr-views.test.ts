import { strict as assert } from "node:assert";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, it } from "bun:test";
import { ANIMALS, animalName, closeViewer, createAdapter, createViews, nameTabs, shellQuote, viewerArgs, type Run, type Session, type View } from "./herdr-views";

const session = (id: string, parentID?: string): Session => ({ id, parentID, location: { directory: "/repo with 'quote" } });
mkdirSync(join(tmpdir(), "opencode"), { recursive: true });
const testState = mkdtempSync(join(tmpdir(), "opencode", "herdr-names-"));
afterAll(() => rmSync(testState, { recursive: true, force: true }));

it("keeps random names unique and durable, including exhaustion and competing parent processes", async () => {
  const env = { XDG_STATE_HOME: join(testState, "allocation") };
  assert.equal(new Set(ANIMALS).size, ANIMALS.length);
  const names = Array.from({ length: ANIMALS.length + 1 }, (_, index) => animalName(env, `session-${index}`));
  assert.equal(new Set(names).size, names.length);
  assert(names.slice(0, ANIMALS.length).every((name) => ANIMALS.includes(name)));
  assert.match(names.at(-1)!, /2$/);
  assert.equal(animalName(env, "session-0"), names[0], "reopening the ledger must not rename a reused session");
  const [a, b] = await Promise.all(["a", "b"].map(async (tag) => {
    const code = `import { animalName } from ${JSON.stringify(new URL("./herdr-views.ts", import.meta.url).href)};
      console.log(JSON.stringify(Array.from({length:5}, (_, i) =>
        animalName(${JSON.stringify(env)}, i === 0 ? "shared" : ${JSON.stringify(tag)} + i))));`;
    const worker = Bun.spawn([process.execPath, "--eval", code], { stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr, exit] = await Promise.all([
      new Response(worker.stdout).text(), new Response(worker.stderr).text(), worker.exited,
    ]);
    assert.equal(exit, 0, stderr);
    return JSON.parse(stdout) as string[];
  }));
  assert.equal(a[0], b[0], "two parents must agree on the same child's name");
  assert.equal(new Set([a[0], ...a.slice(1), ...b.slice(1)]).size, 9);
});

it("names Main and owned child tabs only, keeping aliases across reconnects", async () => {
  const env = { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", XDG_STATE_HOME: join(testState, "migration") };
  const renamed: string[][] = [];
  const panes = [
    { pane_id: "w1:p2", tab_id: "w1:t2", tokens: { oc2_parent: "w1:p1", oc2_session: "child", oc2_view: "owned" } },
    { pane_id: "w1:p3", tab_id: "w1:t3", tokens: { oc2_parent: "someone-else", oc2_session: "foreign", oc2_view: "foreign" } },
    { pane_id: "w1:p4", tab_id: "w1:t4", tokens: { oc2_parent: "w1:p1", oc2_session: "released" } },
    { pane_id: "w1:p5", tab_id: "w1:t1", tokens: { oc2_parent: "w1:p1", oc2_session: "same-tab", oc2_view: "owned" } },
    { pane_id: "w1:p6", tab_id: "w1:t6", tokens: { oc2_parent: "w1:p1", oc2_session: "stale", oc2_view: "owned" } },
  ];
  const execute: Run = async (_command, args) => {
    if (args[0] === "tab") {
      renamed.push(args.slice(2));
      if (args[2] === "w1:t2") delete panes[4]!.tokens.oc2_view;
      return {};
    }
    if (args[1] === "get") return { result: { pane: args[2] === env.HERDR_PANE_ID
      ? { tab_id: "w1:t1", workspace_id: "w1" }
      : panes.find((pane) => pane.pane_id === args[2]) } };
    return { result: { panes: structuredClone(panes) } };
  };
  await nameTabs(env, execute);
  const first = renamed.map((row) => [...row]);
  assert.deepEqual(first, [["w1:t1", "Main"], ["w1:t2", `󰚩  ${animalName(env, "child")}`]],
    "never rename Main through a child pane or a tab released since listing");
  await nameTabs(env, execute);
  assert.deepEqual(renamed.slice(2), first);
  await nameTabs({ ...env, OPENCODE_HERDR_VIEWER: "1" }, execute);
  assert.equal(renamed.length, 4, "a child TUI must not rename its own tab Main");
});

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
  const args = viewerArgs(session("child"), {
    HERDR_PANE_ID: "w1:p1", XDG_CONFIG_HOME: "/profile", XDG_STATE_HOME: "/state", OPENCODE_CONFIG_CONTENT: "private",
  }, "owner");
  assert.deepEqual(args.slice(-4), ["opencode", "--session", "child", "/repo with 'quote"]);
  assert(args.includes("XDG_CONFIG_HOME=/profile"));
  assert(args.includes("XDG_STATE_HOME=/state"));
  assert(args.includes("OPENCODE_HERDR_OWNER=owner"));
  assert(args.includes("OPENCODE_HERDR_PARENT=w1:p1"));
  assert(!args.includes("private"));
  assert(!args.includes("--prompt"));
  assert.equal(shellQuote("a'b"), "'a'\\''b'");
  assert.equal(createAdapter({}), undefined);
  assert.throws(() => createAdapter({ HERDR_ENV: "1", HC_TERMINAL_ID: "t1" }), /Conflicting/);
});

it("closes only the explicitly selected idle viewer, preserving Main, sibling panes and session data", async () => {
  const identity = { OPENCODE_HERDR_VIEWER: "1", OPENCODE_HERDR_SESSION: "child",
    OPENCODE_HERDR_OWNER: "owned", OPENCODE_HERDR_PARENT: "w1:p1" };
  const env = { ...identity, HERDR_ENV: "1", HERDR_PANE_ID: "w1:p2" };
  const calls: Array<[string, string[]]> = [];
  let allowed = true;
  const pane = { pane_id: "w1:p2", tokens: { oc2_view: "owned", oc2_session: "child", oc2_parent: "w1:p1" } };
  const execute: Run = async (command, args) => {
    calls.push([command, args]);
    return { result: { pane } };
  };
  await closeViewer(env, () => allowed, execute);
  assert.deepEqual(calls, [
    ["herdr", ["pane", "get", "w1:p2"]],
    ["herdr", ["pane", "close", "w1:p2"]],
  ]);
  for (const key of ["oc2_view", "oc2_session", "oc2_parent"] as const) {
    const saved = pane.tokens[key];
    pane.tokens[key] = "someone-else";
    await assert.rejects(closeViewer(env, () => true, execute), /ownership changed/);
    pane.tokens[key] = saved;
  }
  await assert.rejects(closeViewer({ ...env, HERDR_PANE_ID: "w1:p1" }, () => true, execute), /pane is missing/);
  await assert.rejects(closeViewer({ ...env, OPENCODE_HERDR_OWNER: "" }, () => true, execute), /identity is missing/);
  allowed = true;
  await assert.rejects(closeViewer(env, () => allowed, async (...args) => {
    const result = await execute(...args);
    allowed = false; // The child resumed or the person navigated away during lookup.
    return result;
  }), /no longer idle or selected/);
  assert.equal(calls.filter(([, args]) => args.includes("close")).length, 1);

  const appEnv = { ...identity, HC_TERMINAL_ID: "t2", OPENCODE_HERDR_PARENT: "t1" };
  const appCalls: Array<[string, string[]]> = [];
  let appPanes = [{ pane: "p2", terminal: "t2" }, { pane: "p3", terminal: "t3" }];
  const appExecute: Run = async (command, args) => {
    appCalls.push([command, args]);
    if (command === "hc") return { address: "t2", parent: "t1", state: "live",
      labels: { "oc2.view": "owned", "oc2.session": "child" } };
    return { spaces: [{ tabs: [{ panes: appPanes }] }] };
  };
  await closeViewer(appEnv, () => true, appExecute);
  assert.deepEqual(appCalls.at(-1), ["herdr-app", ["do", "pane.close", "--pane", "p2"]]);
  appPanes = [];
  await assert.rejects(closeViewer(appEnv, () => true, appExecute), /pane is not unique/);
  appPanes = [{ pane: "p2", terminal: "t2" }, { pane: "p4", terminal: "t2" }];
  await assert.rejects(closeViewer(appEnv, () => true, appExecute), /pane is not unique/);
  await assert.rejects(closeViewer(appEnv, () => true, async () => { throw new Error("offline"); }), /offline/);
  assert.equal(appCalls.filter(([, args]) => args.includes("pane.close")).length, 1);
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
  assert(spawn.includes(`OPENCODE_HERDR_OWNER=${labels["oc2.view"]}`));
  assert(spawn.includes("OPENCODE_HERDR_PARENT=t1"));
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
  const env = { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", XDG_STATE_HOME: join(testState, "adapter") };
  const adapter = createAdapter(env, execute)!;
  await adapter.open(session("child", "root"));
  const create = calls.find(([, args]) => args[0] === "tab")![1];
  assert.equal(create[create.indexOf("--label") + 1], `󰚩  ${animalName(env, "child")}`);
  const launch = calls.find(([, args]) => args[1] === "run");
  assert(launch?.[1].at(-1)!.includes("'--session' 'child'"));
  assert(launch?.[1].at(-1)!.includes(`'OPENCODE_HERDR_OWNER=${owner}'`));
  assert(launch?.[1].at(-1)!.includes("'OPENCODE_HERDR_PARENT=w1:p1'"));
  assert(calls.every(([, args]) => !args.includes("close") && !args.includes("agent") && !args.includes("prompt")));
});
