import { View, div, svg, image } from "gpui-kit";
import { h_flex, ScrollHandle } from "gpui-base";
import { spaces, panes, focused, terminals, exec, run, openOverlay, closeOverlay, notify, props, theme, window, layout, settings } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

function panelMask(panel) {
  if (!panel || panel.hidden) return 0;
  return (find(panel, "files")?.hidden ? 0 : 1) | (find(panel, "git")?.hidden ? 0 : 2);
}

function showPanel(mask) {
  if (mask) {
    run(mask & 1 ? "layout.show" : "layout.hide", { id: "files" });
    run(mask & 2 ? "layout.show" : "layout.hide", { id: "git" });
  }
  run(mask ? "layout.show" : "layout.hide", { id: "panel" });
}

// A space nobody has chosen panels for opens with Files and Git (1 | 2).
const DEFAULT_PANEL_MASK = 3;

// Same as the agents mod: drops a status glyph, keeps a leading bracket or quote.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").replace(/^\[ [!.] \] /, "").trim();

// A tab Herdr named (unnamed, or after its program) follows its agent's live
// title, as the agents list does; a name the person gave stays.
function label(tab, lead) {
  const prog = lead?.program?.name;
  const base = tab.named ? tab.name : prog ?? "Terminal";
  if (!lead?.program?.agent) return base;
  const live = clean(lead.title);
  // clean() would strip a path's leading ~ or /: test the title with only its status glyph gone.
  const path = /^[~/]|^[A-Za-z]:\\/.test((lead.title ?? "").replace(/^[^\p{L}\p{N}~/]+/u, ""));
  const telling = live && live !== lead.terminal && live !== prog && !path && !live.includes("@") && live.toLowerCase() !== lead.program.key;
  return (tab.name === prog || !tab.named) && telling ? live : base;
}

export default class Tabs extends View {
  init(config, cx) {
    this.changes = config?.terminal ?? props()?.terminal;
    if (this.changes) {
      const overlay = config?.overlay ?? props()?.overlay;
      cx.timer.every(1000, () => {
        if (!terminals().some(t => t.address === this.changes && t.state === "live")) closeOverlay(overlay);
      });
      return;
    }
    this.pressed = null;
    this.scroll = ScrollHandle.new();
    try { this.panels = JSON.parse(localStorage.getItem("panels") ?? "{}"); } catch { this.panels = {}; }
    if (!this.panels || typeof this.panels !== "object" || Array.isArray(this.panels)) this.panels = {};
    this.swipe = { acc: 0, steps: 0, at: 0, last: 0 };
  }

  close() {
    if (this.changes && terminals().some(t => t.address === this.changes && t.state === "live")) run("terminal.kill", { terminal: this.changes });
  }

  openChanges(cx) {
    if (this.opening) return;
    const space = spaces().find(s => s.active), f = focused();
    const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    const cwd = pane?.cwd || f?.cwd || space?.folder;
    const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
    if (!cwd) { notify({ title: "Cannot open Changes", body: "No folder selected", level: "error" }); return; }
    this.opening = true;
    cx.spawn(async () => {
      try {
        const args = ["run", "--json", "--bg", "--rm", "--cwd", cwd];
        if (on) args.push("--on", on);
        args.push("--", "bash", "-c", 'exec bash "$HOME/.config/herdr-app/mods/tabs-files/changes-diff.sh"');
        const result = await exec("hc", args);
        if (result.code !== 0) throw new Error(result.stderr || "Cannot start Changes");
        const terminal = JSON.parse(result.stdout).address;
        if (!terminal) throw new Error("No terminal address returned");
        try {
          openOverlay({ kind: "dialog", frame: "none", width: 0.8, height: 0.8, layout: { type: "column", background: "#1e1e2eeb", radius: 0, children: [
            { type: "block", size: { px: 0 }, content: { mod: "tabs-files", props: { terminal } } },
            { type: "block", content: { terminal } },
          ] } });
        } catch (e) {
          await exec("hc", ["kill", terminal]);
          throw e;
        }
      } catch (e) { notify({ title: "Cannot open Changes", body: String(e), level: "error" }); }
      finally { this.opening = false; }
    });
  }

  // One tab per wheel notch. A touchpad or smooth-scrolling mouse sends many
  // small events per gesture: a short swipe or one smoothed notch (about
  // 25 px) switches one tab, a longer swipe keeps going a tab per 60 px, at
  // most one every 100 ms so each shows.
  wheel(e) {
    if (e.delta_lines) {
      if (e.delta_lines.y) run(e.delta_lines.y > 0 ? "tab.prev" : "tab.next");
      return;
    }
    const s = this.swipe, now = Date.now();
    // Phases often arrive only as moves (a macOS touchpad included): a pause
    // or a turn starts a new gesture.
    if (e.touch_phase === "started" || now - s.at > 250 || e.delta.y * s.acc < 0) Object.assign(s, { acc: 0, steps: 0 });
    s.at = now;
    s.acc += e.delta.y;
    const need = s.steps ? 60 : 20;
    if (Math.abs(s.acc) < need || now - s.last < 100) return;
    s.acc -= Math.sign(s.acc) * need;
    s.steps++;
    s.last = now;
    run(e.delta.y > 0 ? "tab.prev" : "tab.next");
  }

  // Remember which right-side panes are visible in each space.
  syncPanel(space, panel) {
    if (!space || !panel) return;
    const now = panelMask(panel);
    if (space.id !== this.space) {
      const first = this.space === undefined;
      this.space = space.id; this.pending = null;
      if (!(first && !(space.id in this.panels))) {
        const stored = this.panels[space.id];
        const want = stored === "files" || stored === "git" ? 3 : Number.isInteger(stored) && stored >= 0 && stored <= 3 ? stored : DEFAULT_PANEL_MASK;
        if (want !== now) {
          this.pending = { want, until: Date.now() + 1000 };
          showPanel(want);
          return;
        }
      }
    }
    // Until the restore lands (or something else won), the old state isn't a choice.
    if (this.pending) {
      if (this.pending.want !== now && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (this.panels[space.id] === now) return;
    this.panels[space.id] = now;
    localStorage.setItem("panels", JSON.stringify(this.panels));
  }

  togglePanel(id, space, panel) {
    if (!space || !panel) return;
    const want = (this.pending?.want ?? panelMask(panel)) ^ (id === "files" ? 1 : 2);
    this.pending = { want, until: Date.now() + 1000 };
    this.panels[space.id] = want;
    localStorage.setItem("panels", JSON.stringify(this.panels));
    showPanel(want);
  }

  render() {
    if (this.changes) return div();
    const t = theme();
    const space = spaces().find(p => p.active);
    const shown = space?.tabs ?? [];
    const managed = new Set(terminals().filter(t => t.state === "live" && t.parent && t.labels?.["herdr.supervised"] === "1").map(t => t.address));
    const active = shown.findIndex(tab => tab.active);
    const selected = shown[active]?.id;
    if (selected !== this.selected || active !== this.selectedIndex) {
      this.selected = selected;
      this.selectedIndex = active;
      if (active >= 0) this.scroll.scroll_to_item(active);
    }
    const stop = (_e, cx) => cx.stop_propagation();
    const button = (id, label, action) => div().id(id).size(26).flex_none().flex().items_center().justify_center().text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", stop).on_click(action).child(label);
    const item = (c, i) => {
      const lead = panes().find(p => p.tab === c.id && p.program?.agent) ?? panes().find(p => p.tab === c.id);
      const supervised = panes().some(p => p.tab === c.id && managed.has(p.terminal));
      const program = lead?.program;
      const name = label(c, lead);
      return h_flex().id(`tab-${c.id}`).h(29).px(10).gap(7).items_center().flex_none().text_size(12.8)
        // A rename or status dot on this or an earlier tab can push the active one out.
        .when(i <= active, el => el.on_size_change((_size, cx) => { this.scroll.scroll_to_item(active); cx.notify(); }))
        .border(1).border_color(c.active ? t.border : t.chrome).bg(supervised ? t.accent + (c.active ? "45" : "30") : c.active ? t.raised : t.chrome).text_color(c.active ? t.foreground : t.muted)
        .hover(s => s.bg(t.hover))
        .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); this.pressed = i; if (e.click_count === 2) run("tab.rename", { id: c.id }); })
        .on_mouse_up("left", () => {
          const from = this.pressed; this.pressed = null;
          if (from !== null && from !== i) run("tab.move", { id: shown[from].id, index: space.tabs.findIndex(x => x.id === c.id) + 1 });
          else run("tab.select", { id: c.id });
        })
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "menu-square", frame: "none", kind: "popup", width: 200, props: { square: true, tab: "tab", target: { id: c.id, space: space.id } } }); })
        .when(Boolean(program?.icon), el => el.child(program.tint ? svg(program.icon).size(14).text_color(t.muted) : image(program.icon).size(14)))
        .child(div().max_w(170).truncate().child(c.zoomed ? `${name} Z` : name))
        .when(c.status === "working", el => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)))
        .when(c.status === "blocked" || c.status === "done", el => el.child(div().size(6).bg(t[c.status])))
        .when(c.active, el => el.child(div().id(`close-${c.id}`).text_color(t.dim).on_mouse_down("left", stop).on_click((_e, cx) => { cx.stop_propagation(); run("tab.close", { id: c.id }); }).child(svg("mods/pane/close.svg").size(12))));
    };
    const root = layout(), sidebar = find(root, "sidebar"), w = window();
    // Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
    const lightsPadding = w?.platform === "macos" && w.titlebar === "none" && !w.fullscreen && root?.traffic_lights
      ? Math.max(10, (root.traffic_lights[0] + 64) / settings().zoom - (sidebar?.hidden ? 0 : sidebar?.size?.px ?? 0))
      : 10;
    const panel = find(root, "panel");
    this.syncPanel(space, panel);
    const panelButton = (id, label, icon, action) => {
      const on = !action && Boolean(panelMask(panel) & (id === "files" ? 1 : 2));
      return h_flex().id(`panel-${id}`).h(26).px(8).gap(5).flex_none().items_center()
        .text_size(12).bg(on ? t.selected : t.chrome).text_color(on ? t.foreground : t.muted)
        .hover(s => s.bg(t.hover)).on_mouse_down("left", stop)
        .on_click(action ?? (() => this.togglePanel(id, space, panel))).child(svg(icon).size(14)).child(label);
    };
    return h_flex().size_full().min_w(0).px(10).pl(lightsPadding).gap(3).items_center().bg(t.chrome)
      .on_mouse_up("left", () => { this.pressed = null; })
      .on_scroll_wheel(e => this.wheel(e))
      .child(h_flex().id("tab-scroll").flex_1().min_w(0).h_full().items_center().gap(3).overflow_x_scrollbar().track_scroll(this.scroll)
        .on_size_change((_size, cx) => { if (active >= 0) { this.scroll.scroll_to_item(active); cx.notify(); } })
        .children(shown.map(item)))
      .child(button("tab-new", "+", () => openOverlay({ mod: "new-menu-square", frame: "none", kind: "popup", width: 250, height: 512 })))
      .child(panelButton("files", "Files", "mods/files/file.svg"))
      .child(panelButton("git", "Git", "mods/git-graph/branch.svg"))
      .child(panelButton("changes", "Changes", "mods/changes/changes.svg", (_e, cx) => this.openChanges(cx)))
      .when(w?.buttons, el => el.child(button("minimize", w.platform === "windows" ? svg("mods/tabs/win-min.svg").size(16) : "−", () => run("window.minimize")))
        .child(button("maximize", w.platform === "windows" ? svg(`mods/tabs/${w.maximized ? "win-restore" : "win-max"}.svg`).size(16) : "□", () => run("window.maximize")))
        .child(button("close-window", w.platform === "windows" ? svg("mods/tabs/win-close.svg").size(16) : svg("mods/pane/close.svg").size(13), () => run("window.close"))));
  }
}
