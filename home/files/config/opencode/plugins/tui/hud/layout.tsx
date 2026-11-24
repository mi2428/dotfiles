/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import type { RGBA } from "@opentui/core";
import { For, Show, children, createSignal, onCleanup, type JSX } from "solid-js";

export const MAX_PANEL_WIDTH = 85;
export const HUD_MAX_ROWS = 8;
// Four cards (body + top/bottom padding), three gaps, and nine rows for the prompt/footer and bottom gap.
export const MIN_HUD_HEIGHT = 4 * (HUD_MAX_ROWS + 2) + 3 + 9;
const PANEL_MARGIN = 2;
const CARD_PADDING = 2;
export const CARD_INSET = CARD_PADDING * 2 + 2;
const BORDER_CHARS = {
  topLeft: "", bottomLeft: "", vertical: "┃", topRight: "", bottomRight: "",
  horizontal: " ", bottomT: "", topT: "", cross: "", leftT: "", rightT: "",
};

export function popupWidth(columns: number): number {
  const width = Number.isFinite(columns) ? Math.max(1, Math.floor(columns)) : MAX_PANEL_WIDTH;
  return Math.min(MAX_PANEL_WIDTH, Math.max(1, width - PANEL_MARGIN * 2), Math.max(36, Math.floor(width * 0.85)));
}

export type HudLayout = { readonly width: number; readonly visible: boolean };

export function HudStack(props: { context: Context; children: (layout: HudLayout) => JSX.Element }) {
  const renderer = props.context.renderer;
  const [columns, setColumns] = createSignal(renderer.width);
  const [rows, setRows] = createSignal(renderer.height);
  const resize = () => { setColumns(renderer.width); setRows(renderer.height); };
  renderer.on("resize", resize);
  onCleanup(() => renderer.off("resize", resize));
  const layout: HudLayout = {
    get width() { return popupWidth(columns()); },
    get visible() { return columns() >= 80 && rows() >= MIN_HUD_HEIGHT; },
  };
  const content = children(() => props.children(layout));
  const hasCards = () => content.toArray().some((item) => item != null && typeof item !== "boolean");
  return <box id="hud-stack" visible={layout.visible && hasCards()} position="absolute" top={0} right={PANEL_MARGIN}
    width={layout.width} zIndex={900} flexDirection="column" gap={1}>
    {content()}
  </box>;
}

export function HudCard(props: { context: Context; id: string; accent: RGBA; children: JSX.Element }) {
  const theme = props.context.theme;
  return <box id={props.id} width="100%" flexShrink={0} flexDirection="column" backgroundColor={theme.background.raised.high}
    border={["left", "right"]} borderColor={props.accent} customBorderChars={BORDER_CHARS}
    paddingLeft={CARD_PADDING} paddingRight={CARD_PADDING} paddingTop={1} paddingBottom={1}>
    {props.children}
  </box>;
}

export function HudRows<T>(props: { context: Context; items: readonly T[]; children: (item: T) => JSX.Element }) {
  const shown = () => props.items.slice(0, props.items.length > HUD_MAX_ROWS ? HUD_MAX_ROWS - 1 : HUD_MAX_ROWS);
  return <>
    <For each={shown()}>{props.children}</For>
    <Show when={props.items.length > HUD_MAX_ROWS}>
      <text fg={props.context.theme.text.muted} height={1} wrapMode="none" truncate>
        {`+${props.items.length - (HUD_MAX_ROWS - 1)} more`}
      </text>
    </Show>
  </>;
}
