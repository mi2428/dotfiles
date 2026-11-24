/** @jsxImportSource @opentui/solid */
import type { Context } from "@opencode/plugin/tui/context";
import { children, createSignal, onCleanup, type JSX } from "solid-js";

export const MAX_PANEL_WIDTH = 94;
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
  const resize = () => setColumns(renderer.width);
  renderer.on("resize", resize);
  onCleanup(() => renderer.off("resize", resize));
  const layout: HudLayout = {
    get width() { return popupWidth(columns()); },
    get visible() { return columns() >= 80; },
  };
  const content = children(() => props.children(layout));
  const hasCards = () => content.toArray().some((item) => item != null && typeof item !== "boolean");
  return <box id="hud-stack" visible={layout.visible && hasCards()} position="absolute" top={0} right={PANEL_MARGIN}
    width={layout.width} zIndex={900} flexDirection="column" gap={1}>
    {content()}
  </box>;
}

export function HudCard(props: { context: Context; id: string; title: JSX.Element; children: JSX.Element }) {
  const theme = props.context.theme;
  return <box id={props.id} width="100%" flexShrink={0} flexDirection="column" backgroundColor={theme.background.raised.base}
    border={["left", "right"]} borderColor={theme.text.feedback.info.base} customBorderChars={BORDER_CHARS}
    paddingLeft={CARD_PADDING} paddingRight={CARD_PADDING} paddingBottom={1}>
    <box alignSelf="flex-start" flexDirection="row" backgroundColor={theme.text.feedback.info.base}
      paddingLeft={1} paddingRight={1} marginBottom={1}>
      <text fg={theme.background.raised.base} wrapMode="none" truncate>{props.title}</text>
    </box>
    {props.children}
  </box>;
}
