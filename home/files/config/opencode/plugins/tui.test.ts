import { strict as assert } from "node:assert";
import { describe, it } from "bun:test";
import {
  BoxRenderable,
  DiffRenderable,
  ScrollBoxRenderable,
  SyntaxStyle,
  TextAttributes,
  TextRenderable,
} from "./tui/node_modules/@opentui/core";
import { createTestRenderer } from "./tui/node_modules/@opentui/core/testing";
import { buildTodoView } from "./tui/lib/todo-overlay";
import {
  buildTodoOverlayNodes,
  MAX_BODY_HEIGHT,
  MAX_PANEL_WIDTH,
  popupWidth,
  registerMessageLabelColors,
  registerTodoOverlay,
  sessionIDFromRoute,
} from "./tui/tui";

const todos = [
  { content: "finish report", status: "completed" },
  { content: "wire overlay", status: "pending" },
  { content: "run tests", status: "in_progress" },
  { content: "old task", status: "cancelled" },
];

describe("message label colors", () => {
  it("recolors nested labels and coalesces message updates", async () => {
    type Handler = (event: never) => void;
    const handlers = new Map<string, Handler>();
    const label = { children: [" File "], fg: "old-fg", bg: "old-bg" };
    const nested = { children: [label], fg: "old-fg", bg: "old-bg" };
    const directory = { children: [" Directory "], fg: "old-fg", bg: "old-bg" };
    let renders = 0;
    let scans = 0;
    let unsubscribes = 0;
    let dispose: (() => void) | undefined;
    const api = {
      event: {
        on: (name: string, handler: Handler) => {
          handlers.set(name, handler);
          return () => {
            handlers.delete(name);
            unsubscribes += 1;
          };
        },
      },
      renderer: {
        root: {
          getTextChildren: () => {
            scans += 1;
            return [nested, directory];
          },
          getChildren: () => [],
        },
        requestRender: () => {
          renders += 1;
        },
      },
      route: { current: { name: "session", params: { sessionID: "ses_1" } } },
      theme: { current: { selectedListItemText: "selected", primary: "primary" } },
      lifecycle: { onDispose: (handler: () => void) => (dispose = handler) },
    };

    registerMessageLabelColors(api as never);
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(renders, 1);
    assert.equal(scans, 1);
    assert.deepEqual(
      [label.fg, label.bg, nested.fg, nested.bg, directory.fg, directory.bg],
      ["selected", "primary", "selected", "primary", "selected", "primary"],
    );

    renders = 0;
    scans = 0;
    handlers.get("message.part.updated")?.({
      properties: { sessionID: "ses_1", part: { type: "tool" } },
    } as never);
    handlers.get("message.part.updated")?.({
      properties: { sessionID: "ses_2", part: { type: "file" } },
    } as never);
    handlers.get("message.updated")?.({
      properties: { sessionID: "ses_1", info: { role: "assistant" } },
    } as never);
    assert.equal(renders, 1);
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(scans, 1);

    assert(dispose);
    dispose();
    assert.equal(unsubscribes, 2);
  });
});

describe("todo overlay state", () => {
  it("shows completed, current, and future items in timeline order", () => {
    const view = buildTodoView(todos);
    assert(view);
    assert.deepEqual(view.lines, [
      { kind: "completed", text: "▸ finish report" },
      { kind: "in_progress", text: "▸ run tests" },
      { kind: "pending", text: "▸ wire overlay" },
    ]);
    assert.equal(view.active, 2);
    assert.equal(view.total, 3);
    assert.equal(view.completed, 1);
    assert.equal(view.cancelled, 1);
    assert.equal(view.windowStart, 0);
    assert.equal(view.windowEnd, 2);
  });

  it("returns no overlay data only when there are no displayable items", () => {
    assert.equal(buildTodoView([]), null);
    assert.equal(buildTodoView([{ content: "cancelled", status: "cancelled" }]), null);

    const completed = buildTodoView([{ content: "done", status: "completed" }]);
    assert(completed);
    assert.deepEqual(completed.lines, [{ kind: "completed", text: "▸ done" }]);
    assert.equal(completed.active, 0);
    assert.equal(completed.total, 1);
    assert.equal(completed.windowStart, 0);
    assert.equal(completed.windowEnd, 0);

    const completedHistory = buildTodoView(
      Array.from({ length: 6 }, (_, index) => ({ content: `done ${index}`, status: "completed" })),
    );
    assert(completedHistory);
    assert.equal(completedHistory.windowStart, 1);
    assert.equal(completedHistory.windowEnd, 5);
  });

  it("keeps the overlay session-only and styles it as a responsive top-right toast", () => {
    assert.equal(sessionIDFromRoute({ name: "home" }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: "ses_1" } }), "ses_1");
    assert.equal(sessionIDFromRoute({ name: "session", params: {} }), undefined);
    assert.equal(sessionIDFromRoute({ name: "session", params: { sessionID: 42 } } as never), undefined);
    assert.equal(sessionIDFromRoute({ name: "other", params: { sessionID: "ses_1" } }), undefined);
    assert.equal(buildTodoOverlayNodes([], {} as never), null);

    const nodes = buildTodoOverlayNodes(
      [{ content: "work", status: "pending" }],
      {
        backgroundPanel: "panel",
        borderSubtle: "border",
        info: "info",
        success: "success",
        warning: "warning",
        text: "text",
        textMuted: "muted",
      },
      240,
    );
    assert(nodes);
    assert.equal(nodes.props.position, "absolute");
    assert.equal(nodes.props.top, 0);
    assert.equal(nodes.props.right, 2);
    assert.equal(nodes.props.width, MAX_PANEL_WIDTH);
    assert.deepEqual(nodes.props.border, ["left", "right"]);
    assert.equal(nodes.props.borderStyle, undefined);
    assert.equal(nodes.props.paddingTop, 0);
    assert.equal("focusable" in nodes.props, false);
    const header = nodes.children?.[0];
    assert(header);
    assert.equal(header.kind, "box");
    assert.equal(header.props.alignSelf, "flex-start");
    assert.equal(header.props.backgroundColor, "info");
    assert.equal(header.children?.[0]?.props.fg, "panel");
    assert.equal(header.children?.[0]?.props.attributes, undefined);
    assert.equal(header.children?.[0]?.text, "Todo · 0 of 1");
    assert.equal(nodes.children?.[1]?.kind, "scrollbox");
    assert.equal(nodes.children?.[1]?.props.height, 1);
    assert.deepEqual(nodes.children?.[1]?.props.verticalScrollbarOptions, { visible: false, showArrows: false, width: 0 });
    assert.equal(nodes.children?.[1]?.children?.[0]?.props.fg, "warning");
    assert.equal(nodes.children?.[1]?.children?.[0]?.props.wrapMode, "char");
    assert.equal(nodes.children?.[1]?.children?.[0]?.text, "▸ work");
    assert.equal(popupWidth(80), 68);
    assert.equal(popupWidth(120), MAX_PANEL_WIDTH);
    assert.equal(popupWidth(200), MAX_PANEL_WIDTH);
    assert.equal(popupWidth(240), MAX_PANEL_WIDTH);
    assert.equal(MAX_PANEL_WIDTH, 94);
    assert.equal(MAX_BODY_HEIGHT, 12);
  });

  it("covers styled split-diff cells on the first app row", async () => {
    const width = 80;
    const syntax = SyntaxStyle.fromStyles({
      "keyword.type": { bold: true, fg: "#ffffff" },
      keyword: { bold: true, fg: "#ffffff" },
      type: { bold: true, fg: "#ffffff" },
      default: { fg: "#ffffff" },
    });
    const test = await createTestRenderer({ width, height: 8 });

    try {
      test.renderer.root.add(
        new DiffRenderable(test.renderer, {
          diff: [
            "diff --git a/a.ts b/a.ts",
            "--- a/a.ts",
            "+++ b/a.ts",
            "@@ -1,3 +1,3 @@",
            "-const oldValue = true",
            "+const newValue = false",
            " type Old = string",
            " type New = number",
          ].join("\n"),
          view: "split",
          width: "100%",
          wrapMode: "word",
          filetype: "typescript",
          syntaxStyle: syntax,
          fg: "#ffffff",
        }),
      );
      for (let pass = 0; pass < 6; pass += 1) {
        await Bun.sleep(30);
        await test.renderOnce();
      }
      const before = test.renderer.currentRenderBuffer.buffers.attributes.slice();
      const nodes = buildTodoOverlayNodes(
        [
          { content: "done", status: "completed" },
          { content: "current task", status: "in_progress" },
          { content: "next", status: "pending" },
        ],
        {
          backgroundPanel: "#181825",
          borderSubtle: "#585b70",
          info: "#94e2d5",
          primary: "#cba6f7",
          selectedListItemText: "#1e1e2e",
          success: "#a6e3a1",
          warning: "#f9e2af",
          text: "#cdd6f4",
          textMuted: "#bac2de",
        },
        width,
      );
      assert(nodes);

      const materialize = (node: typeof nodes): any => {
        const Constructor = node.kind === "box"
          ? BoxRenderable
          : node.kind === "scrollbox"
            ? ScrollBoxRenderable
            : TextRenderable;
        const renderable = new Constructor(
          test.renderer,
          node.kind === "text" ? { ...node.props, content: node.text } : { ...node.props },
        ) as any;
        for (const child of node.children ?? []) renderable.add(materialize(child as typeof nodes));
        return renderable;
      };
      const app = new BoxRenderable(test.renderer, {
        position: "absolute",
        top: 0,
        right: 0,
        bottom: 0,
        left: 0,
        zIndex: 900,
      });
      const panel = materialize(nodes) as BoxRenderable;
      app.add(panel);
      test.renderer.root.add(app);
      await test.renderOnce();

      const countBold = (attributes: Uint32Array, row: number, start: number, end: number): number => {
        let count = 0;
        for (let column = start; column < end; column += 1) {
          if ((attributes[row * width + column]! & TextAttributes.BOLD) !== 0) count += 1;
        }
        return count;
      };
      const after = test.renderer.currentRenderBuffer.buffers.attributes;
      const panelEnd = panel.x + panel.width;
      assert(countBold(before, 0, panel.x, panelEnd) > 0, "split diff must exercise bold syntax cells");
      assert.equal(countBold(after, 0, panel.x, panelEnd), 0);
      assert.equal(panel.y, 0);
      assert.match(test.captureCharFrame().split("\n")[0]!.slice(panel.x, panelEnd), /Todo · 1 of 3/);
      assert.deepEqual(Array.from(after.slice(0, panel.x)), Array.from(before.slice(0, panel.x)));
    } finally {
      test.renderer.destroy();
      syntax.destroy();
    }
  });

  it("keeps every task scrollable and centers the initial window around the current task", () => {
    const longContent = "x".repeat(140);
    const manyTodos = [
      { content: "oldest done", status: "completed" },
      { content: "older done", status: "completed" },
      { content: "recent done", status: "completed" },
      { content: "latest done", status: "completed" },
      { content: longContent, status: "in_progress" },
      { content: "next", status: "pending" },
      { content: "later", status: "pending" },
      { content: "last visible", status: "pending" },
      { content: "hidden future", status: "pending" },
      { content: "cancelled", status: "cancelled" },
    ];
    const view = buildTodoView(manyTodos);

    assert(view);
    assert.deepEqual(view.lines, [
      { kind: "completed", text: "▸ oldest done" },
      { kind: "completed", text: "▸ older done" },
      { kind: "completed", text: "▸ recent done" },
      { kind: "completed", text: "▸ latest done" },
      { kind: "in_progress", text: `▸ ${longContent}` },
      { kind: "pending", text: "▸ next" },
      { kind: "pending", text: "▸ later" },
      { kind: "pending", text: "▸ last visible" },
      { kind: "pending", text: "▸ hidden future" },
    ]);
    assert.equal(view.lines.every((line) => line.text.startsWith("▸ ")), true);
    assert.equal(view.windowStart, 2);
    assert.equal(view.windowEnd, 6);
    assert.equal(view.total, 9);
    assert.equal(view.active, 5);
    assert.equal(view.completed, 4);
    assert.equal(view.cancelled, 1);

    const nodes = buildTodoOverlayNodes(manyTodos, {
      backgroundPanel: "panel",
      borderSubtle: "border",
      info: "info",
      success: "success",
      warning: "warning",
      text: "text",
      textMuted: "muted",
    });
    const body = nodes?.children?.[1];
    assert(body);
    assert.equal(body.kind, "scrollbox");
    assert.equal(body.props.height, 6);
    assert.equal(body.children?.length, 9);
    assert.deepEqual(body.scrollWindow, {
      startID: "opencode-todo-line-2",
      endID: "opencode-todo-line-6",
      key: "4:5:opencode-todo-line-2:opencode-todo-line-6",
    });
    assert.deepEqual(body.children?.map((line) => line.props.fg), [
      "muted",
      "muted",
      "muted",
      "muted",
      "success",
      "warning",
      "warning",
      "warning",
      "warning",
    ]);
    assert.equal(body.children?.every((line) => line.props.wrapMode === "char"), true);

    const wrappedCurrent = buildTodoOverlayNodes(
      [
        { content: "done", status: "completed" },
        { content: longContent, status: "in_progress" },
        { content: "next", status: "pending" },
      ],
      {} as never,
      80,
    );
    assert.equal(wrappedCurrent?.children?.[1]?.props.height, 5);

    const wideCurrent = buildTodoOverlayNodes(
      [{ content: "日本語".repeat(50), status: "in_progress" }],
      {} as never,
      80,
    );
    assert.equal(wideCurrent?.children?.[1]?.props.height, 5);

    const many = buildTodoOverlayNodes(
      Array.from({ length: 12 }, (_, index) => ({ content: `task ${index}`, status: "pending" })),
      {} as never,
    );
    assert.equal(many?.children?.[1]?.children?.length, 12);
    assert.equal(many?.children?.[1]?.scrollWindow?.startID, "opencode-todo-line-0");
    assert.equal(many?.children?.[1]?.scrollWindow?.endID, "opencode-todo-line-4");
  });

  it("redraws progress without dropping the overlay when a new request starts", () => {
    type TodoEvent = {
      properties: { sessionID: string; todos: Array<{ content: string; status: string }> };
    };
    let todoEventHandler: ((event: TodoEvent) => void) | undefined;
    let dispose: (() => void) | undefined;
    let appSlot: (() => unknown) | undefined;
    let reads = 0;
    let renders = 0;
    let unsubscribes = 0;
    let liveTodos = [
      { content: "first", status: "completed" },
      { content: "second", status: "completed" },
      { content: "third", status: "in_progress" },
      { content: "fourth", status: "pending" },
      { content: "fifth", status: "pending" },
      { content: "sixth", status: "pending" },
    ];
    let liveMessages = [{ id: "old-user-message", role: "user" }];

    const api = {
      state: {
        session: {
          todo: (sessionID: string) => {
            assert.equal(sessionID, "ses_1");
            reads += 1;
            return liveTodos;
          },
          messages: () => liveMessages,
        },
      },
      event: {
        on: (name: string, handler: (event: never) => void) => {
          if (name === "todo.updated") {
            todoEventHandler = handler as (event: TodoEvent) => void;
          } else {
            assert.fail(`unexpected event subscription: ${name}`);
          }
          return () => {
            unsubscribes += 1;
          };
        },
      },
      renderer: { width: 120, requestRender: () => (renders += 1) },
      lifecycle: { onDispose: (handler: () => void) => (dispose = handler) },
      slots: {
        register: (registration: { slots: { app: () => unknown } }) => {
          appSlot = registration.slots.app;
        },
      },
      route: { current: { name: "session", params: { sessionID: "ses_1" } } },
      theme: {
        current: {
          backgroundPanel: "panel",
          borderSubtle: "border",
          info: "info",
          success: "success",
          warning: "warning",
          text: "text",
          textMuted: "muted",
        },
      },
    };
    type FakeNode = {
      kind: string;
      props: Record<string, unknown>;
      children: unknown[];
      scrollTop: number;
      isDestroyed: boolean;
      y: number;
      height: number;
      [key: string]: unknown;
    };
    const solid = {
      createSignal: <T>(initial: T) => {
        let value = initial;
        return [
          () => value,
          (next: T | ((previous: T) => T)) => {
            value = typeof next === "function" ? (next as (previous: T) => T)(value) : next;
          },
        ] as const;
      },
      createElement: (kind: string): FakeNode => ({
        kind,
        props: {},
        children: [],
        scrollTop: 0,
        isDestroyed: false,
        y: 0,
        height: 1,
      }),
      setProp: (node: FakeNode, name: string, value: unknown) => {
        node.props[name] = value;
        node[name] = value;
      },
      insert: (node: FakeNode, child: unknown) => {
        const value = typeof child === "function" ? (child as () => unknown)() : child;
        if (value !== null && value !== undefined) node.children.push(value);
      },
    };
    const overlayFrom = (slot: FakeNode): FakeNode => {
      const overlay = slot.children[0] as FakeNode | undefined;
      assert(overlay);
      return overlay;
    };
    const scrollBoxFrom = (root: FakeNode): FakeNode => {
      const result = overlayFrom(root).children.find((child) => (child as FakeNode).kind === "scrollbox") as FakeNode;
      assert(result);
      return result;
    };
    const headerFrom = (root: FakeNode): FakeNode => {
      const header = overlayFrom(root).children[0] as FakeNode;
      const headerText = header.children[0] as FakeNode;
      assert(headerText);
      return headerText;
    };
    const lineNodesFrom = (scrollbox: FakeNode): FakeNode[] => scrollbox.children as FakeNode[];
    const lineTextsFrom = (scrollbox: FakeNode): string[] =>
      lineNodesFrom(scrollbox).map((line) => line.children[0] as string);
    const applyLayout = (scrollbox: FakeNode) => {
      const lines = lineNodesFrom(scrollbox);
      lines.forEach((line, index) => {
        line.y = index;
        line.height = 1;
      });
      scrollbox.content = {
        y: 0,
        height: lines.length,
        findDescendantById: (id: string) => lines.find((line) => line.props.id === id),
      };
      const onSizeChange = scrollbox.props.onSizeChange as ((this: FakeNode) => void) | undefined;
      assert(onSizeChange);
      onSizeChange.call(scrollbox);
      onSizeChange.call(scrollbox);
    };

    registerTodoOverlay(api as never, solid);
    assert(todoEventHandler);
    assert(dispose);
    assert(appSlot);
    const first = appSlot() as FakeNode;
    const firstScrollBox = scrollBoxFrom(first);
    const initializeFirstScroll = firstScrollBox.props.onSizeChange as ((this: FakeNode) => void) | undefined;
    assert(initializeFirstScroll);
    initializeFirstScroll.call(firstScrollBox);
    assert.equal(firstScrollBox.scrollTop, 0);
    applyLayout(firstScrollBox);
    assert.equal(headerFrom(first).children[0], "Todo · 2 of 6");
    assert.deepEqual(lineTextsFrom(firstScrollBox), [
      "▸ first",
      "▸ second",
      "▸ third",
      "▸ fourth",
      "▸ fifth",
      "▸ sixth",
    ]);
    assert.deepEqual(lineNodesFrom(firstScrollBox).map((line) => line.props.fg), [
      "muted",
      "muted",
      "success",
      "warning",
      "warning",
      "warning",
    ]);
    assert.equal(firstScrollBox.height, 5);
    assert.equal(firstScrollBox.scrollTop, 0);
    firstScrollBox.scrollTop = 3;

    const second = appSlot() as FakeNode;
    const secondScrollBox = scrollBoxFrom(second);
    applyLayout(secondScrollBox);
    assert.equal(reads, 2);
    assert.equal(secondScrollBox.scrollTop, 3);

    liveTodos = liveTodos.map((todo, index) => {
      if (index === 2) return { ...todo, status: "completed" };
      if (index === 3) return { ...todo, status: "in_progress" };
      return todo;
    });
    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    assert.equal(renders, 1);
    const third = appSlot() as FakeNode;
    const thirdScrollBox = scrollBoxFrom(third);
    applyLayout(thirdScrollBox);
    assert.equal(headerFrom(third).children[0], "Todo · 3 of 6");
    assert.equal(thirdScrollBox.scrollTop, 1);
    assert.equal(lineNodesFrom(thirdScrollBox)[2]?.props.fg, "muted");
    assert.equal(lineNodesFrom(thirdScrollBox)[3]?.props.fg, "success");

    liveTodos = liveTodos.map((todo, index) => {
      if (index === 3) return { ...todo, status: "completed" };
      if (index === 4) return { ...todo, status: "in_progress" };
      return todo;
    });
    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    assert.equal(renders, 2);
    const fourth = appSlot() as FakeNode;
    const fourthScrollBox = scrollBoxFrom(fourth);
    applyLayout(fourthScrollBox);
    assert.equal(headerFrom(fourth).children[0], "Todo · 4 of 6");
    assert.equal(fourthScrollBox.scrollTop, 2);
    assert.equal(fourthScrollBox.height, 4);
    assert.equal(lineNodesFrom(fourthScrollBox)[3]?.props.fg, "muted");
    assert.equal(lineNodesFrom(fourthScrollBox)[4]?.props.fg, "success");
    assert.equal(reads, 4);

    assert.equal(renders, 2);
    assert(appSlot());
    assert.equal(reads, 5);

    liveMessages = [...liveMessages, { id: "new-user-message", role: "user" }];
    const updated = appSlot() as FakeNode;
    assert.equal(updated.children.length, 1);
    assert.equal(headerFrom(updated).children[0], "Todo · 4 of 6");
    assert.equal(reads, 6);

    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    assert.equal(renders, 3);
    assert.equal((appSlot() as FakeNode).children.length, 1);
    assert.equal(headerFrom(appSlot() as FakeNode).children[0], "Todo · 4 of 6");

    liveTodos = [
      { content: "inspect new request", status: "in_progress" },
      { content: "implement new request", status: "pending" },
    ];
    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    assert.equal(renders, 4);
    const next = appSlot() as FakeNode;
    assert.equal(headerFrom(next).children[0], "Todo · 0 of 2");
    assert.deepEqual(lineTextsFrom(scrollBoxFrom(next)), ["▸ inspect new request", "▸ implement new request"]);

    dispose();
    assert.equal(unsubscribes, 1);
  });

  it("reactively invalidates the mounted slot as todos and user requests change", () => {
    type TodoEvent = {
      properties: { sessionID: string; todos: Array<{ content: string; status: string }> };
    };
    type FakeNode = {
      kind: string;
      props: Record<string, unknown>;
      children: unknown[];
      scrollTop: number;
      isDestroyed: boolean;
    };

    let todoEventHandler: ((event: TodoEvent) => void) | undefined;
    let appSlot: (() => unknown) | undefined;
    let activeObserver: (() => void) | undefined;
    let liveTodos = [{ content: "first request", status: "in_progress" }];
    let liveMessages = [{ id: "first-request", role: "user" }];
    const messageObservers = new Set<() => void>();

    const api = {
      state: {
        session: {
          todo: () => liveTodos,
          messages: () => {
            if (activeObserver) messageObservers.add(activeObserver);
            return liveMessages;
          },
        },
      },
      event: {
        on: (name: string, handler: (event: never) => void) => {
          if (name === "todo.updated") todoEventHandler = handler as (event: TodoEvent) => void;
          return () => {};
        },
      },
      renderer: { width: 120, requestRender: () => {} },
      lifecycle: { onDispose: () => {} },
      slots: {
        register: (registration: { slots: { app: () => unknown } }) => {
          appSlot = registration.slots.app;
        },
      },
      route: { current: { name: "session", params: { sessionID: "ses_1" } } },
      theme: {
        current: {
          backgroundPanel: "panel",
          borderSubtle: "border",
          info: "info",
          success: "success",
          warning: "warning",
          text: "text",
          textMuted: "muted",
        },
      },
    };
    const solid = {
      createSignal: <T>(initial: T) => {
        let value = initial;
        const observers = new Set<() => void>();
        return [
          () => {
            if (activeObserver) observers.add(activeObserver);
            return value;
          },
          (next: T | ((previous: T) => T)) => {
            value = typeof next === "function" ? (next as (previous: T) => T)(value) : next;
            for (const observer of observers) observer();
          },
        ] as const;
      },
      createElement: (kind: string): FakeNode => ({
        kind,
        props: {},
        children: [],
        scrollTop: 0,
        isDestroyed: false,
      }),
      setProp: (node: FakeNode, name: string, value: unknown) => {
        node.props[name] = value;
      },
      insert: (node: FakeNode, child: unknown) => {
        if (typeof child === "function") {
          const update = () => {
            activeObserver = update;
            const value = (child as () => unknown)();
            activeObserver = undefined;
            node.children = value === null || value === undefined ? [] : [value];
          };
          update();
          return;
        }
        node.children.push(child);
      },
    };

    registerTodoOverlay(api as never, solid);
    assert(todoEventHandler);
    assert(appSlot);

    const rendered = appSlot() as FakeNode;
    assert(rendered);

    liveTodos = [{ content: "first request", status: "completed" }];
    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    const completedOverlay = rendered.children[0] as FakeNode;
    const completedHeader = (completedOverlay.children[0] as FakeNode).children[0] as FakeNode;
    assert.equal(completedHeader.children[0], "Todo · 1 of 1");

    liveMessages = [...liveMessages, { id: "next-request", role: "user" }];
    for (const observer of messageObservers) observer();
    assert.equal(rendered.children.length, 1);

    liveTodos = [{ content: "second request", status: "in_progress" }];
    todoEventHandler({ properties: { sessionID: "ses_1", todos: liveTodos } });
    assert.equal(rendered.children.length, 1);
  });
});
