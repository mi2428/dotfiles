/** @jsxImportSource @opentui/solid */
import { strict as assert } from "node:assert";
import { it, mock, spyOn } from "bun:test";
import { createTestRenderer } from "@opentui/core/testing";
import type { BoxRenderable } from "@opentui/core";
import { render } from "@opentui/solid";
import { createSignal } from "solid-js";
import { parseThemeDocument, resolveThemeDocument } from "@opencode/theme/tui";
import { AgentsHud } from "./agents";
import { ShellHud } from "./shell";
import { ChangesHud, GitStatus, watchGit, type GitSnapshot } from "./git";
import { MIN_HUD_HEIGHT, HudStack } from "./layout";
import * as views from "../lib/herdr-views";
import theme from "../../../themes/catppuccin-mocha-mauve.json";

it("updates live agents and shells, removes stopped work and never mixes session families", async () => {
  const test = await createTestRenderer({ width: 120, height: MIN_HUD_HEIGHT });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const [sessionID, setSessionID] = createSignal("main");
  const [active, setActive] = createSignal(true);
  const [waiting, setWaiting] = createSignal("");
  const [shellStatus, setShellStatus] = createSignal("running");
  const [many, setMany] = createSignal(false);
  let started = Date.now() - 5000;
  const [busy, setBusy] = createSignal(started - 90_000);
  const executionListeners = new Set<(event: { data: { sessionID: string } }) => void>();
  const sync = mock(async () => {});
  const sessionSync = mock(async () => { setBusy(started); });
  const names = spyOn(views, "animalName").mockImplementation((_env, id) => id === "child" ? "Fox" : id);
  const context = {
    renderer: test.renderer, theme: resolved,
    data: {
      on: (_type: string, handler: (event: { data: { sessionID: string } }) => void) => {
        executionListeners.add(handler);
        return () => executionListeners.delete(handler);
      },
      session: {
        family: (id: string) => id === "main" ? ["main", "child",
          ...(many() ? Array.from({ length: 9 }, (_, index) => `child${index + 2}`) : [])] : [id],
        get: (id: string) => ({ id, parentID: id.startsWith("child") ? "main" : undefined,
          time: { get busy() { return busy(); } }, location: { directory: `/${id === "other" ? "other" : "repo"}` } }),
        sync: sessionSync, invalidate: () => {},
        status: () => active() ? "running" : "idle",
        message: { sync, list: () => [{ type: "assistant", content: [
          { type: "tool", name: "stale", time: { created: started - 1 }, state: { status: "running" } },
          { type: "tool", name: "grep", time: { created: started + 1 }, state: { status: "running" } },
        ] }] },
        permission: { sync, list: () => waiting() === "approval" ? [{}] : [] },
        form: { sync, list: () => waiting() === "answer" ? [{}] : [] },
      },
      shell: { sync, list: () => [
        { id: "ours", status: shellStatus(), command: "bun test\nsecond line", metadata: { sessionID: "main" } },
        { id: "foreign", status: "running", command: "private-other-session", metadata: { sessionID: "foreign" } },
      ] },
    },
  } as never;
  try {
    await render(() => <HudStack context={context}>{() => <>
      <AgentsHud context={context} sessionID={sessionID()} />
      <ShellHud context={context} sessionID={sessionID()} />
    </>}</HudStack>, test.renderer);
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /󰚩  Fox  RUNNING  grep  00:/);
    assert.match(test.captureCharFrame(), /  bun test/);
    assert.doesNotMatch(test.captureCharFrame(), /stale|second line|private-other-session/);
    setBusy(Date.now() - 90_000);
    started = Date.now() - 1000;
    for (const listener of executionListeners) listener({ data: { sessionID: "child" } });
    await Bun.sleep(0);
    await test.renderOnce();
    assert.equal(sessionSync.mock.calls.length, 2, "a resumed child must refresh its execution timestamps");
    assert.doesNotMatch(test.captureCharFrame(), /01:30/);
    assert.match(test.captureCharFrame(), /RUNNING  grep  00:0/);
    setWaiting("approval");
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /WAITING FOR APPROVAL/);
    setWaiting("answer");
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /WAITING FOR ANSWER/);
    setWaiting("");
    setMany(true);
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /\+3 more/);
    const agents = test.renderer.root.findDescendantById("agents-panel") as BoxRenderable;
    assert.equal(agents.height, 10, "many agents must still use only eight body rows plus padding");
    setActive(false); // success, failure and interrupt all make the public execution status idle.
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("agents-panel"));
    assert.equal(executionListeners.size, 0, "stopped rows must release execution listeners");
    const stack = test.renderer.root.findDescendantById("hud-stack") as BoxRenderable;
    const shell = test.renderer.root.findDescendantById("shell-panel") as BoxRenderable;
    assert.equal(shell.y, stack.y, "Shell must move up after the last agent stops");
    for (const status of ["exited", "killed", "timeout"]) {
      setShellStatus(status);
      await test.renderOnce();
      assert(!test.renderer.root.findDescendantById("shell-panel"));
      assert.equal(stack.visible, false);
      setShellStatus("running");
      await test.renderOnce();
      assert.match(test.captureCharFrame(), /  bun test/);
    }
    setSessionID("other");
    await Bun.sleep(0);
    await test.renderOnce();
    assert.equal(stack.visible, false, "changing conversations must hide work belonging to the previous one");
    setSessionID("main");
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /  bun test/);
    setActive(true);
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /󰚩  Fox/);
  } finally {
    const destroyed = new Promise<void>((resolve) => test.renderer.once("destroy", resolve));
    try {
      test.renderer.destroy();
      await destroyed;
    } finally {
      names.mockRestore();
    }
    assert.equal(executionListeners.size, 0, "removed cards must release execution listeners");
  }
});

it("shares one Git reader, clears both views after commit and rejects stale or failed reads", async () => {
  const test = await createTestRenderer({ width: 120, height: MIN_HUD_HEIGHT });
  const resolved = resolveThemeDocument(parseThemeDocument(theme), "dark");
  const [sessionID, setSessionID] = createSignal("main");
  const [git, setGit] = createSignal<GitSnapshot>({ files: [], failed: false });
  const first = Promise.withResolvers<{ data: GitSnapshot["files"] }>();
  const read = mock((_input: unknown) => first.promise);
  let refresh: () => Promise<void>;
  const interval = globalThis.setInterval;
  const timers = spyOn(globalThis, "setInterval").mockImplementation((...args) => {
    if (args[1] === 3000) refresh = args[0] as typeof refresh;
    return interval(...args);
  });
  const errors = spyOn(console, "error").mockImplementation(() => {});
  const context = {
    renderer: test.renderer, theme: resolved,
    ui: { router: { current: () => ({ type: "session", sessionID: sessionID() }) } },
    data: {
      session: { get: (id: string) => ({ location: { directory: `/${id}` } }) },
      location: { vcs: { info: () => ({ provider: "git" }) } },
    },
    client: { vcs: { status: read } },
  } as never;
  try {
    await render(() => {
      watchGit(context, setGit);
      return <>
        <GitStatus context={context} snapshot={git()} />
        <HudStack context={context}>{(layout) => <ChangesHud context={context} snapshot={git()} />}</HudStack>
      </>;
    }, test.renderer);
    await test.renderOnce();
    await refresh!();
    assert.equal(read.mock.calls.length, 1, "footer and HUD must not poll independently or overlap a pending read");
    first.resolve({ data: [{ file: "live.tsx", additions: 12, deletions: 3, status: "modified" }] });
    await Bun.sleep(0);
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /󰈙 live.tsx\s+\+12 -3/);
    assert(test.renderer.root.findDescendantById("git-status"));
    const many = Array.from({ length: 12 }, (_, i) => ({ file: `file${i}.ts`, additions: i, deletions: 1, status: "modified" as const }));
    read.mockResolvedValue({ data: many.slice(0, 8) });
    await refresh!();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /file7.ts/);
    assert.doesNotMatch(test.captureCharFrame(), /\+\d+ more/);
    read.mockResolvedValue({ data: many });
    await refresh!();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /\+5 more/);
    const more = test.captureCharFrame().split("\n").find((line) => line.includes("+5 more"))!;
    const fileRow = test.captureCharFrame().split("\n").find((line) => line.includes("file0.ts"))!;
    assert.equal(more.indexOf("+5 more"), fileRow.indexOf("󰈙"), "overflow is plain text aligned with the file bullets");
    assert.doesNotMatch(more, /󰈙/);
    assert.equal((test.renderer.root.findDescendantById("changes-panel") as BoxRenderable).height, 10);
    read.mockResolvedValue({ data: [{ file: "binary-or-mode", additions: 0, deletions: 0, status: "modified" }] });
    await refresh!();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /binary-or-mode/);
    assert(!test.renderer.root.findDescendantById("git-status"));
    read.mockResolvedValue({ data: [] }); // The server reports no remaining diff after commit.
    await refresh!();
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("changes-panel"));
    assert(!test.renderer.root.findDescendantById("git-status"));
    const old = Promise.withResolvers<{ data: GitSnapshot["files"] }>();
    read.mockReturnValueOnce(old.promise);
    const pending = refresh!();
    read.mockResolvedValue({ data: [{ file: "new-repo.ts", additions: 1, deletions: 0, status: "added" }] });
    setSessionID("other");
    await Bun.sleep(0);
    old.resolve({ data: [{ file: "stale-repo.ts", additions: 99, deletions: 99, status: "modified" }] });
    await pending;
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /new-repo.ts/);
    assert.doesNotMatch(test.captureCharFrame(), /stale-repo/);
    read.mockRejectedValueOnce(new Error("offline"));
    await refresh!();
    await test.renderOnce();
    assert.match(test.captureCharFrame(), /Git status unavailable/);
    assert.doesNotMatch(test.captureCharFrame(), /new-repo.ts/);
    assert.equal(errors.mock.calls.length, 1);
    read.mockResolvedValue({ data: [] });
    await refresh!();
    await test.renderOnce();
    assert(!test.renderer.root.findDescendantById("changes-panel"));
  } finally {
    test.renderer.destroy();
    timers.mockRestore();
    errors.mockRestore();
  }
});
