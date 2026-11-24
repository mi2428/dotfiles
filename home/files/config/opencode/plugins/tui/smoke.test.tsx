/** @jsxImportSource @opentui/solid */
import { strict as assert } from "node:assert";
import { it, mock, spyOn } from "bun:test";
import { createTestRenderer } from "@opentui/core/testing";
import { BoxRenderable, ScrollBoxRenderable, TextRenderable } from "@opentui/core";
import { render } from "@opentui/solid";
import { For, Show, createSignal } from "solid-js";
import { HUD_MAX_ROWS, MIN_HUD_HEIGHT, HudCard, HudStack } from "./hud/layout";
import { parseThemeDocument, resolveThemeDocument } from "@opencode/theme/tui";
import type { KeymapLayer } from "@opencode/plugin/tui/context";
import { registerEnabledFields } from "@opentui/keymap/addons";
import { createTestKeymap } from "@opentui/keymap/testing";
import plugin from "./tui";
import * as herdrViews from "./lib/herdr-views";
import theme from "../../themes/catppuccin-mocha-mauve.json";

it("never suppresses the host's editor context and interrupt confirmation", () => {
  const keys = ["HERDR_ENV", "HERDR_PANE_ID", "HC_TERMINAL_ID", "OPENCODE_HERDR_VIEWER"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  process.env.HERDR_ENV = "1";
  const claims: Array<{ append?: string; replace?: string }> = [];
  let disposed = 0;
  const ui = { slot: (claim: typeof claims[number]) => { claims.push(claim); return () => { disposed++; }; } };
  try {
    const cleanup = plugin.setup({
      options: {},
      ui,
      keymap: { layer: () => assert.fail("Main shortcuts must stay host-owned") },
    } as never);
    assert(claims.some((claim) => claim.append === "prompt.footer.status"));
    assert(!claims.some((claim) => claim.replace === "prompt.footer" || claim.replace?.startsWith("prompt.footer.")));
    cleanup();
    assert.equal(disposed, claims.length, "unloading must remove every registered slot");
    claims.length = 0;
    disposed = 0;
    delete process.env.HERDR_ENV;
    process.env.HC_TERMINAL_ID = "slim-test";
    const cleanupSlim = plugin.setup({
      options: { herdrViews: false }, ui,
      keymap: { layer: () => assert.fail("Slim shortcuts must stay host-owned") },
      storage: { memory: () => assert.fail("Slim must not start a second pane manager") },
      data: { on: () => assert.fail("Slim must not register native child-view handlers") },
    } as never);
    assert(claims.some((claim) => claim.append === "prompt.footer.status"));
    assert(!claims.some((claim) => claim.replace === "prompt.footer" || claim.replace?.startsWith("prompt.footer.")));
    cleanupSlim();
    assert.equal(disposed, claims.length, "Slim must remove every registered slot too");
  } finally {
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

it("adds Git line counts to Main without replacing native status, or leaking stale repository results", async () => {
  const keys = ["HERDR_ENV", "HC_TERMINAL_ID", "OPENCODE_HERDR_VIEWER"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.HERDR_ENV = "1";
  delete process.env.HC_TERMINAL_ID;
  delete process.env.OPENCODE_HERDR_VIEWER;
  const test = await createTestRenderer({ width: 120, height: 3 });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const [sessionID, setSessionID] = createSignal("first");
  const [repository, setRepository] = createSignal(true);
  let slot: (() => unknown) | undefined;
  let watcher: (() => unknown) | undefined;
  let refresh: () => Promise<void>;
  const interval = globalThis.setInterval;
  const timers = spyOn(globalThis, "setInterval").mockImplementation((...args) => {
    if (args[1] === 3000) refresh = args[0] as typeof refresh;
    return interval(...args);
  });
  type Result = { data: Array<{ additions: number; deletions: number }> };
  const initial = Promise.withResolvers<Result>();
  const read = mock((_input: { location: { directory: string } }) => initial.promise);
  const errors = spyOn(console, "error").mockImplementation(() => {});
  const cleanup = plugin.setup({
    options: { herdrViews: false }, theme: resolved,
    ui: {
      slot: (claim: { append?: string; render: typeof slot }) => {
        if (claim.append === "app" && !watcher) watcher = claim.render;
        if (claim.append === "prompt.footer.status") slot = claim.render;
        return () => {};
      },
      router: { current: () => ({ type: "session", sessionID: sessionID() }) },
    },
    data: {
      session: { get: (id: string) => ({ location: { directory: `/${id}` } }) },
      location: { vcs: { info: () => ({ provider: repository() ? "git" : undefined }) } },
    },
    client: { vcs: { status: read } },
  } as never);
  try {
    assert(slot);
    assert(watcher);
    await render(() => <>{watcher!() as never}<box width="100%" height={1} flexDirection="row" gap={2}>
        <text flexGrow={1} flexShrink={1} minWidth={0} truncate wrapMode="none">Path branch esc interrupt</text>
        {slot!() as never}
        <text flexShrink={0}>ctrl+p commands</text>
      </box></>, test.renderer);
    await test.renderOnce();
    await refresh!();
    assert.equal(read.mock.calls.length, 1, "polling must skip a read still in flight");
    initial.resolve({ data: [{ additions: 12, deletions: 3 }, { additions: 5, deletions: 2 }] });
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Path branch esc interrupt.*Main.*\+17 -5.*ctrl\+p commands/);
    assert.doesNotMatch(test.captureCharFrame(), /|±|\?/);
    const old = Promise.withResolvers<Result>();
    read.mockReturnValueOnce(old.promise);
    const pending = refresh!();
    read.mockResolvedValue({ data: [{ additions: 0, deletions: 4 }] });
    setSessionID("second");
    await Bun.sleep(0);
    old.resolve({ data: [{ additions: 99, deletions: 99 }] });
    await pending;
    await test.renderOnce();
    assert.deepEqual(read.mock.calls.at(-1)![0], { location: { directory: "/second" } });
    assert.match(test.captureCharFrame(), /\+0 -4/);
    assert.doesNotMatch(test.captureCharFrame(), /99/);
    test.resize(60, 3);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Main.*\+0 -4.*ctrl\+p commands/);
    read.mockRejectedValueOnce(new Error("Git failed"));
    await refresh!();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Git !/);
    assert.doesNotMatch(test.captureCharFrame(), /-4/);
    assert.equal(errors.mock.calls.length, 1);
    read.mockResolvedValue({ data: [] });
    await refresh!();
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /Git !|\+0/);
    setRepository(false);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Main.*ctrl\+p commands/);
    assert.doesNotMatch(test.captureCharFrame(), /|Git !/);
  } finally {
    cleanup();
    test.renderer.destroy();
    timers.mockRestore();
    errors.mockRestore();
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

it("shows all four HUDs in child viewers without adding a Main footer", async () => {
  const keys = ["HERDR_ENV", "OPENCODE_HERDR_VIEWER", "OPENCODE_HERDR_SESSION"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.HERDR_ENV = "1";
  process.env.OPENCODE_HERDR_VIEWER = "1";
  process.env.OPENCODE_HERDR_SESSION = "child";
  const test = await createTestRenderer({ width: 120, height: MIN_HUD_HEIGHT });
  const slots: Array<{ append?: string; render: () => unknown }> = [];
  const [running, setRunning] = createSignal(true);
  const sync = async () => {};
  const started = Date.now() - 1000;
  const names = spyOn(herdrViews, "animalName").mockReturnValue("Fox");
  const read = mock(async () => ({ data: [
    { file: "child-change.ts", additions: 1, deletions: 0, status: "modified" },
  ] }));
  const cleanup = plugin.setup({
    options: {}, renderer: test.renderer, theme: resolveThemeDocument(parseThemeDocument(theme), "dark"),
    keymap: { layer: () => {} },
    ui: {
      router: { current: () => ({ type: "session", sessionID: "child" }) },
      slot: (claim: typeof slots[number]) => { slots.push(claim); return () => {}; },
    },
    data: {
      on: () => () => {},
      location: { vcs: { info: () => ({ provider: "git" }) } },
      session: {
        family: () => ["parent", "child", "grandchild"],
        get: (id: string) => ({ parentID: id === "parent" ? undefined : "parent",
          time: { busy: started }, location: { directory: "/child-repo" } }),
        status: () => running() ? "running" : "idle",
        sync, invalidate: () => {},
        permission: { sync, list: () => [] },
        form: { sync, list: () => [] },
        message: { sync, list: () => [{ type: "assistant", content: [
          { type: "tool", name: "todowrite", time: { created: started }, state: { status: "completed", input: { todos: [
            { content: "child current", status: "in_progress" },
            { content: "child next", status: "pending" },
          ] } } },
        ] }] },
      },
      shell: { sync, list: () => [
        { status: running() ? "running" : "exited", command: "child-shell", metadata: { sessionID: "child" } },
        { status: "running", command: "parent-shell", metadata: { sessionID: "parent" } },
      ] },
    },
    client: { vcs: { status: read }, message: { list: async () => ({ data: [
      { id: "child-edit", type: "assistant", content: [
        { type: "tool", name: "patch", state: { status: "completed", metadata: { files: [{ file: "child-change.ts" }] } } },
      ] },
    ], cursor: {} }) } },
  } as never);
  try {
    assert(!slots.some((slot) => slot.append === "prompt.footer.status"), "Main footer stays Main-only");
    await render(() => <For each={slots.filter((slot) => slot.append === "app")}>{(slot) => slot.render() as never}</For>, test.renderer);
    await Bun.sleep(0);
    await test.renderOnce();
    for (const card of ["todo-panel", "agents-panel", "shell-panel", "changes-panel"]) {
      assert(test.renderer.root.findDescendantById(card), `${card} must be available in child viewers`);
    }
    const frame = test.captureCharFrame();
    assert.match(frame, /child current/);
    assert.match(frame, /child next/);
    assert.match(frame, /󰚩  Fox/);
    assert.match(frame, /  child-shell/);
    assert.match(frame, /child-change.ts/);
    assert.doesNotMatch(frame, /parent-shell/);
    assert.equal(names.mock.calls.length, 1, "Agents excludes the current child and the root");
    assert.deepEqual(read.mock.calls, [[{ location: { directory: "/child-repo" } }]]);
    test.resize(79, MIN_HUD_HEIGHT);
    await test.renderOnce();
    assert.equal((test.renderer.root.findDescendantById("hud-stack") as BoxRenderable).visible, false);
    test.resize(120, MIN_HUD_HEIGHT);
    setRunning(false);
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("agents-panel"));
    assert(!test.renderer.root.findDescendantById("shell-panel"));
    assert.match(test.captureCharFrame(), /child-change.ts/);
  } finally {
    cleanup();
    const destroyed = new Promise<void>((resolve) => test.renderer.once("destroy", resolve));
    test.renderer.destroy();
    await destroyed;
    names.mockRestore();
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

it("keeps emergency controls in every input mode and blocks the parent command", async () => {
  const keys = ["HERDR_ENV", "HC_TERMINAL_ID", "OPENCODE_HERDR_VIEWER", "OPENCODE_HERDR_SESSION"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.HERDR_ENV = "1";
  delete process.env.HC_TERMINAL_ID;
  process.env.OPENCODE_HERDR_VIEWER = "1";
  process.env.OPENCODE_HERDR_SESSION = "child";
  const test = createTestKeymap({ defaultKeys: true });
  registerEnabledFields(test.keymap);
  let mode = "composer";
  let sessionID = "child";
  let hostCalls = 0;
  let dialogsClosed = 0;
  let listMoves = 0;
  let fail = false;
  let running = true;
  let finishInterrupt: (() => void) | undefined;
  const closed: string[] = [];
  const close = spyOn(herdrViews, "closeViewer").mockImplementation(async (_env, canClose) => {
    assert(canClose());
    closed.push(sessionID);
  });
  const interrupted: string[] = [];
  const errors: unknown[] = [];
  const leave = () => { hostCalls++; sessionID = "parent"; };
  test.keymap.registerLayer({
    priority: 1,
    commands: [{ name: "session.parent", run: leave }],
    bindings: [
      { key: "ctrl+c", cmd: leave },
      { key: "escape", cmd: () => { if (mode === "modal") dialogsClosed++; else leave(); } },
      { key: "up", cmd: () => { if (mode === "composer") listMoves++; else test.keymap.dispatchCommand("session.parent"); } },
    ],
  });
  try {
    plugin.setup({
      options: {},
      ui: { slot: () => () => {}, router: { current: () => ({ type: "session", sessionID }) },
        dialog: { clear: () => { dialogsClosed++; mode = "composer"; } },
        toast: { show: (error: unknown) => errors.push(error) } },
      data: { session: {
        get: (id: string) => id === "child" ? { parentID: "parent" } : {},
        status: () => running ? "running" : "idle",
      } },
      client: { session: { interrupt: async (input: { sessionID: string }) => {
        interrupted.push(input.sessionID);
        if (fail) throw new Error("offline");
        if (interrupted.length === 1) await new Promise<void>((resolve) => { finishInterrupt = resolve; });
      } } },
      keymap: { layer: (factory: () => KeymapLayer) => {
        const layer = factory();
        test.keymap.registerLayer({
          priority: layer.priority,
          enabled: () => (layer.mode === "global" || mode === (layer.mode ?? "base")) &&
            (typeof layer.enabled === "function" ? layer.enabled() : layer.enabled !== false),
          commands: layer.commands?.filter((command) => command.id).map((command) => ({
            name: command.id!, run: () => command.run(),
          })),
          bindings: layer.commands?.flatMap((command) => {
            const key = command.bind ?? (command.id === "session.parent" ? "up" : false);
            return key ? [{ key, cmd: command.id ?? (() => command.run()) }] : [];
          }),
        });
      } },
    } as never);
    test.host.press("c", { ctrl: true });
    test.host.press("escape");
    test.host.press("up");
    assert.equal(sessionID, "child");
    assert.deepEqual(interrupted, ["child"]);
    test.host.press("c", { ctrl: true });
    assert.deepEqual(interrupted, ["child"], "repeated keys must not duplicate the pending stop");
    running = false;
    test.host.press("c", { ctrl: true });
    assert.deepEqual(closed, [], "an idle event must not close the viewer while the stop request is pending");
    finishInterrupt!();
    await Bun.sleep(0);
    assert.deepEqual(closed, [], "stopping must never automatically close the viewer");
    running = true;
    assert.equal(listMoves, 1, "composer list navigation must remain usable");
    mode = "base";
    test.host.press("up");
    assert.equal(hostCalls, 0, "the configured parent shortcut must not leave the child");
    mode = "modal";
    test.host.press("escape");
    assert.equal(dialogsClosed, 0, "Escape must be disabled inside dialogs too");
    test.host.press("c", { ctrl: true });
    assert.deepEqual(interrupted, ["child", "child"], "dialogs must not hide emergency stop");
    await Bun.sleep(0);
    test.host.press("g", { ctrl: true });
    assert.equal(dialogsClosed, 1);
    mode = "permission";
    test.host.press("escape");
    test.host.press("c", { ctrl: true });
    assert.equal(hostCalls, 0, "permission prompts must not bypass child controls");
    assert.deepEqual(interrupted, ["child", "child", "child"]);
    await Bun.sleep(0);
    mode = "composer";
    fail = true;
    test.host.press("c", { ctrl: true });
    await Bun.sleep(0);
    assert.equal(errors.length, 1, "a rejected interrupt must be visible");
    running = false;
    test.host.press("c", { ctrl: true });
    test.host.press("c", { ctrl: true });
    assert.deepEqual(closed, ["child"], "idle viewers close once, without interrupting or deleting the session");
    await Bun.sleep(0);
    close.mockRejectedValueOnce(new Error("viewer close failed"));
    test.host.press("c", { ctrl: true });
    await Bun.sleep(0);
    assert.equal(errors.length, 2, "a rejected close must be visible and allow retry");
    test.host.press("c", { ctrl: true });
    await Bun.sleep(0);
    assert.deepEqual(closed, ["child", "child"]);
    sessionID = "parent"; // A manual session change must not leave child controls active.
    test.host.press("c", { ctrl: true });
    assert.equal(hostCalls, 1);
    assert.deepEqual(interrupted, ["child", "child", "child", "child"], "never interrupt the parent from a stale child view");
    assert.deepEqual(test.diagnostics.errors, []);
  } finally {
    close.mockRestore();
    test.cleanup();
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

it("shows current execution telemetry without stale tools, fabricated activity, or replacing the composer", async () => {
  const keys = ["HERDR_ENV", "HC_TERMINAL_ID", "OPENCODE_HERDR_VIEWER", "OPENCODE_HERDR_SESSION"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.HERDR_ENV = "1";
  delete process.env.HC_TERMINAL_ID;
  process.env.OPENCODE_HERDR_VIEWER = "1";
  process.env.OPENCODE_HERDR_SESSION = "child";
  const test = await createTestRenderer({ width: 160, height: 8 });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const started = Date.now() - 84_000;
  const [running, setRunning] = createSignal(true);
  const [waiting, setWaiting] = createSignal("");
  const [route, setRoute] = createSignal("child");
  const [modelName, setModelName] = createSignal("Test Model");
  let slot: (() => unknown) | undefined;
  let receive: ((event: { details: any }) => void) | undefined;
  let unsubscribed = 0;
  const cleanup = plugin.setup({
    options: {}, theme: resolved, keymap: { layer: () => {} },
    ui: {
      slot: (claim: { after?: string; render: typeof slot }) => {
        if (claim.after === "app") slot = claim.render;
        return () => {};
      },
      router: { current: () => ({ type: "session", sessionID: route() }) },
    },
    data: {
      listen: (handler: typeof receive) => { receive = handler; return () => { unsubscribed++; }; },
      location: {
        model: { list: () => [{ id: "model", providerID: "test", name: modelName() }] },
        provider: { list: () => [{ id: "test", name: "Test Provider" }] },
      },
      session: {
        get: () => ({ parentID: "parent", agent: "explore", model: { id: "model", providerID: "test" },
          location: { directory: "/repo" }, outcome: "interrupted",
          time: { created: started - 3_600_000, busy: started, idle: running() ? started - 1000 : started + 2000 } }),
        status: () => running() ? "running" : "idle",
        permission: { list: () => waiting() === "approval" ? [{}] : [] },
        form: { list: () => waiting() === "answer" ? [{}] : [] },
        message: { list: () => [{ type: "assistant", content: [
          { type: "tool", name: "stale-tool", time: { created: started - 10_000 }, state: { status: "running" } },
          { type: "tool", name: "shell", time: { created: started + 1 }, state: { status: "running" } },
        ] }] },
      },
    },
  } as never);
  try {
    assert(slot);
    await render(() => <box width="100%" height="100%" flexDirection="column">
      <box flexGrow={1} minHeight={0} paddingBottom={1}>
        <box flexGrow={1} minHeight={0}><text>Transcript</text></box>
        <box id="native-composer" height={3} flexShrink={0} backgroundColor={resolved.background.raised.base}>
          <text>Native composer</text>
        </box>
      </box>
      {slot!() as never}
    </box>, test.renderer);
    await test.renderOnce();
    let frame = test.captureCharFrame();
    assert.match(frame, /Test Model Test Provider  Elapsed 01:.*RUNNING  explore  Tool shell  Last activity -/);
    assert.doesNotMatch(frame, /stale-tool|INTERRUPTED|Ctrl\+/);
    const status = test.renderer.root.findDescendantById("viewer-status") as BoxRenderable;
    const composer = test.renderer.root.findDescendantById("native-composer") as BoxRenderable;
    const identity = test.renderer.root.findDescendantById("viewer-identity") as TextRenderable;
    const metrics = test.renderer.root.findDescendantById("viewer-metrics") as TextRenderable;
    assert.match(identity.plainText, /^Test Model Test Provider  Elapsed 01:/);
    assert.equal(metrics.plainText, "RUNNING  explore  Tool shell  Last activity -");
    const checkAlignment = () => {
      assert(identity.x + identity.width <= metrics.x, "identity and metrics must not overlap");
      assert.equal(status.x + status.width - (metrics.x + metrics.width), identity.x - status.x,
        "metrics must align to the right with the same inset as the left identity");
    };
    assert(status.backgroundColor.equals(resolved.background.base));
    assert.equal(status.y, composer.y + composer.height, "the footer must touch the composer without a blank row or overlap");
    assert(status.y + status.height < test.renderer.height, "the normal footer gap belongs below the status");
    checkAlignment();
    receive!({ details: { type: "session.text.delta", data: { sessionID: "other" } } });
    await test.renderOnce();
    assert.match(metrics.plainText, /Last activity -$/);
    receive!({ details: { type: "session.text.delta", data: { sessionID: "child" } } });
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Last activity \d+s ago/);
    setWaiting("approval");
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /WAITING FOR APPROVAL/);
    setWaiting("answer");
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /WAITING FOR ANSWER/);
    setWaiting("");
    setRunning(false);
    await test.renderOnce();
    frame = test.captureCharFrame();
    assert.match(frame, /Elapsed 00:02.*INTERRUPTED/);
    assert.match(metrics.plainText, /Tool -  Last activity /);
    setModelName("Very long model name ".repeat(12));
    for (const width of [60, 32, 160]) {
      test.resize(width, 12);
      await test.renderOnce();
      assert.match(test.captureCharFrame(), /Native composer/);
      assert.equal(status.y, composer.y + composer.height, "resizing must keep the footer adjacent to the composer");
      checkAlignment();
    }
    setRoute("parent");
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /INTERRUPTED|Elapsed|Last activity/);
    assert.equal(unsubscribed, 1, "leaving the pinned view must release its event subscription");
  } finally {
    cleanup();
    test.renderer.destroy();
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});

it("stacks independent HUD cards and closes empty gaps without remounting on resize", async () => {
  const test = await createTestRenderer({ width: 80, height: MIN_HUD_HEIGHT });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const context = { renderer: test.renderer, theme: resolved } as never;
  const [mounted, setMounted] = createSignal(true);
  const [first, setFirst] = createSignal(true);
  const [second, setSecond] = createSignal(true);
  const listeners = test.renderer.listenerCount("resize");
  try {
    await render(() => <Show when={mounted()}>
      <HudStack context={context}>{() => <>
        <Show when={first()}><HudCard context={context} id="first-card" accent={resolved.syntax.function}><text>first body</text></HudCard></Show>
        <Show when={second()}><HudCard context={context} id="second-card" accent={resolved.text.feedback.warning.base}><text>second body</text></HudCard></Show>
      </>}</HudStack>
    </Show>, test.renderer);
    await test.renderOnce();
    const stack = test.renderer.root.findDescendantById("hud-stack") as BoxRenderable;
    const a = test.renderer.root.findDescendantById("first-card") as BoxRenderable;
    const b = test.renderer.root.findDescendantById("second-card") as BoxRenderable;
    assert.equal(a.x, b.x);
    assert.equal(a.width, b.width);
    assert(a.borderColor.equals(resolved.syntax.function));
    assert(b.borderColor.equals(resolved.text.feedback.warning.base));
    assert(!a.borderColor.equals(b.borderColor), "each card must use its own accent");
    assert(b.y >= a.y + a.height, "cards must not overlap");
    const top = a.y;
    setFirst(false);
    await test.renderOnce();
    assert.equal(b.y, top, "remaining cards must move up when the first card disappears");
    assert.equal(test.renderer.listenerCount("resize"), listeners + 1, "cards share one size observer");
    setFirst(false);
    await test.renderOnce();
    assert.equal(b.y, stack.y, "the remaining card moves up without a placeholder");
    for (const [width, height] of [[60, 60], [120, MIN_HUD_HEIGHT - 1], [120, MIN_HUD_HEIGHT], [80, 20], [80, MIN_HUD_HEIGHT]]) {
      test.resize(width, height);
      await test.renderOnce();
      const visible = width >= 80 && height >= MIN_HUD_HEIGHT;
      assert.equal(stack.visible, visible);
      assert.equal(test.renderer.root.findDescendantById("second-card"), b);
      if (!visible) assert.doesNotMatch(test.captureCharFrame(), /second body/);
      else assert.match(test.captureCharFrame(), /second body/);
    }
    setSecond(false);
    await test.renderOnce();
    assert.equal(stack.visible, false, "no card means no overlay area");
    setMounted(false);
    await test.renderOnce();
    assert.equal(test.renderer.listenerCount("resize"), listeners, "unmounting releases the width observer");
  } finally {
    test.renderer.destroy();
  }
});

it("fits four full HUD cards above the prompt at the minimum viewport height", async () => {
  const test = await createTestRenderer({ width: 80, height: MIN_HUD_HEIGHT });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const context = { renderer: test.renderer, theme: resolved } as never;
  try {
    await render(() => <HudStack context={context}>{() =>
      <For each={[0, 1, 2, 3]}>{(card) =>
        <HudCard context={context} id={`full-card-${card}`} accent={resolved.hue.accent[200]}>
          <For each={Array.from({ length: HUD_MAX_ROWS }, (_, index) => index)}>{(row) =>
            <text height={1} wrapMode="none">row {row}</text>
          }</For>
        </HudCard>
      }</For>
    }</HudStack>, test.renderer);
    await test.renderOnce();
    const stack = test.renderer.root.findDescendantById("hud-stack") as BoxRenderable;
    const last = test.renderer.root.findDescendantById("full-card-3") as BoxRenderable;
    assert.equal(stack.visible, true);
    assert(last.y + last.height <= test.renderer.height - 8, "reserve eight rows below all four full cards");
    test.resize(80, MIN_HUD_HEIGHT - 1);
    await test.renderOnce();
    assert.equal(stack.visible, false);
  } finally {
    test.renderer.destroy();
  }
});

it("renders a fixed-height Todo window with progress instead of scrollback", async () => {
  const test = await createTestRenderer({ width: 80, height: MIN_HUD_HEIGHT });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  assert.equal(resolved.background.base.a, 0);
  const chat = new ScrollBoxRenderable(test.renderer, { width: "100%", height: "100%", scrollY: true });
  for (let index = 0; index < 80; index++) {
    chat.add(new TextRenderable(test.renderer, { content: `message ${index}`, width: "100%" }));
  }
  test.renderer.root.add(chat);
  let slot: (() => unknown) | undefined;
  const [route, setRoute] = createSignal("ses_1");
  const handlers = new Map<string, (event: any) => void>();
  let invalidations = 0;
  const cleanup = plugin.setup({
    options: { herdrViews: false },
    renderer: test.renderer,
    theme: resolved,
    storage: { memory: () => assert.fail("Todo must not retain scroll state") },
    ui: {
      router: { current: () => ({ type: "session", sessionID: route() }) },
      slot: (claim: { append?: string; render: () => unknown }) => { if (claim.append === "app") slot = claim.render; return () => {}; },
    },
    data: {
      on: (name: string, handler: (event: any) => void) => {
        handlers.set(name, handler);
        return () => { handlers.delete(name); };
      },
      session: { get: () => undefined, message: {
        sync: async () => {},
        invalidate: () => { invalidations++; },
        get: () => undefined,
        list: () => [{ type: "assistant", content: [{
          type: "tool", name: "todowrite", state: { status: "completed", input: { todos: [
            { content: "oldest", status: "completed" },
            { content: "older", status: "completed" },
            ...Array.from({ length: 4 }, (_, index) => ({ content: `recent ${index}`, status: "completed" })),
            { content: "recent", status: "completed" },
            { content: "previous", status: "completed" },
            { content: "current work", status: "in_progress" },
            { content: "next", status: "pending" },
            { content: "later", status: "pending" },
             { content: "last visible", status: "pending" },
             ...Array.from({ length: 3 }, (_, index) => ({ content: `future ${index}`, status: "pending" })),
            { content: "hidden future", status: "pending" },
          ] } },
        }] }],
      } },
    },
    client: { session: { message: { get: async ({ sessionID, messageID }: { sessionID: string; messageID: string }) => {
      assert.equal(sessionID, "ses_1");
      if (messageID === "msg_other") return { type: "assistant", content: [{
        type: "tool", id: "tool_other", name: "other", state: { status: "completed", input: {} },
      }] };
      assert.equal(messageID, "msg_fallback");
      return { type: "assistant", content: [{ type: "tool", id: "tool_fallback", name: "todowrite",
        state: { status: "completed", input: { todos: [{ content: "restored progress", status: "in_progress" }] } } }] };
    } } } },
  } as never);
  assert(slot);
  try {
    await render(() => slot!() as never, test.renderer);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    const frame = test.captureCharFrame();
    assert.match(frame, /▶ current work/);
    assert.doesNotMatch(frame, /Todo ·/);
    assert.match(frame, /○ next/);
    assert.doesNotMatch(frame, /oldest|older|previous|hidden future/);
    assert.match(frame, /\+8 left \(8 done, 50%\)/);
    const panel = test.renderer.root.findDescendantById("todo-panel") as BoxRenderable;
    const stack = test.renderer.root.findDescendantById("hud-stack") as BoxRenderable;
    assert(panel);
    assert.equal(panel.width, 68);
    assert.equal(panel.height, 10, "eight body rows plus top/bottom padding");
    assert(panel.backgroundColor.equals(resolved.background.raised.high));
    assert(!panel.backgroundColor.equals(resolved.background.raised.base), "HUD must stand apart from code block backgrounds");
    assert.equal(panel.backgroundColor.a, 1);
    assert((test.renderer.root.findDescendantById("todo-line-0") as TextRenderable).fg.equals(resolved.text.feedback.success.base));
    assert((test.renderer.root.findDescendantById("todo-line-1") as TextRenderable).fg.equals(resolved.text.base));
    const summary = test.renderer.root.findDescendantById("todo-summary") as TextRenderable;
    assert.equal(summary.y + summary.height, panel.y + panel.height - 1, "progress must always be the final body row");
    assert(!test.renderer.root.findDescendantById("todo-scroll"));
    await test.mockMouse.scroll(5, 12, "down", { delayMs: 0 });
    await test.renderOnce();
    assert(chat.scrollTop > 0, "chat receives wheel events outside the HUD");
    setRoute("ses_2");
    await test.renderOnce();
    await test.renderer.idle();
    setRoute("ses_1");
    await test.renderOnce();
    await test.renderer.idle();
    assert.match(test.captureCharFrame(), /\+8 left \(8 done, 50%\)/);
    test.resize(80, MIN_HUD_HEIGHT - 1);
    await test.renderOnce();
    assert.equal(stack.visible, false, "height alone must hide all cards");
    assert.doesNotMatch(test.captureCharFrame(), /▶|○|current work/);
    test.resize(80, MIN_HUD_HEIGHT);
    await test.renderOnce();
    await test.renderer.idle();
    assert.match(test.captureCharFrame(), /\+8 left \(8 done, 50%\)/);
    for (const width of [45, 79, 80, 120, 45, 80]) {
      test.resize(width, MIN_HUD_HEIGHT);
      await test.renderOnce();
      await test.renderer.idle();
      await test.renderOnce();
      assert.equal(stack.visible, width >= 80);
      if (width < 80) assert.doesNotMatch(test.captureCharFrame(), /▶|○|current work/);
      else assert.match(test.captureCharFrame(), /▶ current work/);
      assert.equal(test.renderer.root.findDescendantById("todo-panel"), panel, "resize retains the HUD instance");
    }
    assert(handlers.has("session.tool.input.started"));
    assert(handlers.has("session.tool.success"));
    test.resize(80, MIN_HUD_HEIGHT - 1);
    await test.renderOnce();
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_updated", id: "tool_updated", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: { sessionID: "ses_1", assistantMessageID: "msg_updated",
      id: "tool_updated", metadata: { todos: [
      ...Array.from({ length: 5 }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
      { content: "now active", status: "in_progress" },
      { content: "later", status: "pending" },
    ] } } });
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /▶|○|now active/);
    test.resize(80, MIN_HUD_HEIGHT);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /▶ now active/);
    assert.match(test.captureCharFrame(), /✓ done 0/);
    assert.match(test.captureCharFrame(), /✓ done 4/);
    assert.match(test.captureCharFrame(), /○ later/);
    assert(!test.renderer.root.findDescendantById("todo-summary"), "all seven tasks fit, including completed ones");
    assert((test.renderer.root.findDescendantById("todo-line-0") as TextRenderable).fg.equals(resolved.text.base));
    assert((test.renderer.root.findDescendantById("todo-line-5") as TextRenderable).fg.equals(resolved.text.feedback.success.base));
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_fallback", id: "tool_fallback", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_fallback", id: "tool_fallback",
    } });
    await Bun.sleep(0);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.equal(invalidations, 1);
    assert.match(test.captureCharFrame(), /▶ restored progress/);
    assert(!test.renderer.root.findDescendantById("todo-summary"), "no summary when every task fits");
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other", name: "other",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other",
      metadata: { todos: [{ content: "spoofed", status: "pending" }] },
    } });
    assert.equal(invalidations, 1);
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_other", id: "tool_other",
      metadata: { todos: [{ content: "spoofed", status: "pending" }] },
    } });
    await Bun.sleep(0);
    await test.renderOnce();
    assert.doesNotMatch(test.captureCharFrame(), /spoofed/);
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_done", id: "tool_done", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_done", id: "tool_done",
      metadata: { todos: [
        { content: "finished", status: "completed" }, { content: "cancelled", status: "cancelled" },
      ] },
    } });
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("todo-panel"), "no unfinished Todo means no card");
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_more", id: "tool_more", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_more", id: "tool_more",
      metadata: { todos: [{ content: "new work", status: "pending" }] },
    } });
    await test.renderOnce();
    assert(test.renderer.root.findDescendantById("todo-panel"), "new unfinished work must reopen the card");
    assert((test.renderer.root.findDescendantById("todo-line-0") as TextRenderable).fg.equals(resolved.text.base));
    assert(!test.renderer.root.findDescendantById("todo-summary"));
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_eight", id: "tool_eight", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_eight", id: "tool_eight", metadata: { todos:
        Array.from({ length: 8 }, (_, index) => ({ content: `upcoming ${index}`, status: "pending" })),
      },
    } });
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /○ upcoming 7/);
    assert(!test.renderer.root.findDescendantById("todo-summary"), "eight tasks fit without a summary row");
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_long", id: "tool_long", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_long", id: "tool_long", metadata: { todos: [
        ...Array.from({ length: 12 }, (_, index) => ({ content: `done ${index} ${"日本語".repeat(50)}`, status: "completed" })),
        { content: "long task " + "x".repeat(200), status: "in_progress" },
        ...Array.from({ length: 8 }, (_, index) => ({ content: `future ${index} ${"日本語".repeat(50)}`, status: "pending" })),
      ] },
    } });
    await test.renderOnce();
    const longPanel = test.renderer.root.findDescendantById("todo-panel") as BoxRenderable;
    assert.equal(longPanel.height, 10, "long task names must truncate, not add wrapped rows");
    assert.match(test.captureCharFrame(), /\+9 left \(12 done, 57%\)/);
    handlers.get("session.tool.input.started")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_clear", id: "tool_clear", name: "todowrite",
    } });
    handlers.get("session.tool.success")?.({ data: {
      sessionID: "ses_1", assistantMessageID: "msg_clear", id: "tool_clear", metadata: { todos: [] },
    } });
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("todo-panel"));
  } finally {
    if (typeof cleanup === "function") await cleanup();
    test.renderer.destroy();
  }
});

it("restores an old Todo on a short cold start and reveals it after increasing height", async () => {
  const test = await createTestRenderer({ width: 80, height: MIN_HUD_HEIGHT - 1 });
  let slot: (() => unknown) | undefined;
  const requests: string[] = [];
  plugin.setup({
    options: { herdrViews: false },
    renderer: test.renderer,
    theme: resolveThemeDocument(parseThemeDocument(theme), "dark"),
    ui: {
      router: { current: () => ({ type: "session", sessionID: "ses_old" }) },
      slot: (claim: { append?: string; render: () => unknown }) => { if (claim.append === "app") slot = claim.render; return () => {}; },
    },
    data: { on: () => () => {}, session: { get: () => undefined, message: {
      sync: async () => {}, list: () => [],
    } } },
    client: { message: { list: async (input: { sessionID: string; cursor?: string; order?: string; type: string }) => {
      if (input.cursor && "order" in input) throw new Error("Cursor cannot be combined with order");
      assert.deepEqual([input.sessionID, input.type], ["ses_old", "assistant"]);
      if (!input.cursor) assert.equal(input.order, "desc");
      else assert.equal("order" in input, false);
      requests.push(input.cursor ?? "first");
      if (!input.cursor) return { data: [], cursor: { next: "older" } };
      return { data: [{ id: "msg_old", type: "assistant", content: [{
        type: "tool", name: "todowrite", state: { status: "completed", input: { todos: [
          { content: "old task still visible", status: "in_progress" },
        ] } },
      }] }], cursor: {} };
    } } },
  } as never);
  assert(slot);
  try {
    await render(() => slot!() as never, test.renderer);
    await Bun.sleep(0);
    await test.renderOnce();
    assert.deepEqual(requests, ["first", "older"]);
    assert.doesNotMatch(test.captureCharFrame(), /▶|○|old task still visible/);
    test.resize(80, MIN_HUD_HEIGHT);
    await test.renderOnce();
    await test.renderer.idle();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /▶ old task still visible/);
  } finally {
    test.renderer.destroy();
  }
});
