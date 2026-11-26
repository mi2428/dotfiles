import { expect, mock, test } from "bun:test";
import type { ComposerShape, ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const stripAnsi = (text: string) =>
  text.replace(/\x1b\[[0-9;]*m/g, "").replace(/<\/?gray>/g, "");

mock.module("@oh-my-pi/pi-tui/text/width", () => ({
  truncate: (text: string, width: number) =>
    text.length <= width ? text : `${text.slice(0, Math.max(0, width - 1))}…`,
  visibleWidth: (text: string) => stripAnsi(text).length,
}));

const border = (text: string) => `<gray>${text}</gray>`;
const box = {
  topLeft: "╭",
  topRight: "╮",
  bottomLeft: "╰",
  bottomRight: "╯",
  horizontal: "─",
  vertical: "│",
};

const ctx = (overrides: Record<string, unknown> = {}) => ({
  box,
  border,
  paddingX: 2,
  width: 12,
  overflow: 0,
  last: false,
  text: "hi",
  pad: "",
  ...overrides,
});

type ChromeContext = Parameters<NonNullable<ComposerShape["top"]>>[0];
type RowContext = Parameters<ComposerShape["row"]>[0];

// Dynamic import is required: mock.module above must be installed before the extension loads.
async function loadShape(): Promise<ComposerShape> {
  let shape: ComposerShape | undefined;
  const { default: register } = await import("../../home/files/config/omp/extensions/dotfiles-bold-status");
  // Test double for the single registration method the extension calls.
  register({
    registerComposerShape: (value: ComposerShape) => {
      shape = value;
    },
  } as unknown as ExtensionAPI);
  if (!shape) throw new Error("extension registered no composer shape");
  return shape;
}

// The fakes supply only the chrome fields this shape reads.
const top = (shape: ComposerShape, overrides: Record<string, unknown> = {}) =>
  shape.top?.(ctx(overrides) as unknown as ChromeContext);
const row = (shape: ComposerShape, overrides: Record<string, unknown> = {}) =>
  shape.row(ctx(overrides) as unknown as RowContext);

test("registers a box shape with the persisted id", async () => {
  const shape = await loadShape();
  expect(shape.id).toBe("dotfiles-bold-status");
  expect(shape.statusAttachment).toBe("top-border");
  expect(shape.sideWidth?.(shape.paddingX ?? 0)).toBe(3);
});

test("keeps the plain box border without a status line", async () => {
  expect(top(await loadShape())).toBe(
    "<gray>╭──</gray><gray>──────</gray><gray>──╮</gray>",
  );
});

test("bolds status content and survives its style resets", async () => {
  expect(
    top(await loadShape(), { width: 20, status: { content: "path\x1b[0m model", width: 10 } }),
  ).toBe(
    "<gray>╭──</gray>\x1b[1mpath\x1b[0m\x1b[1m model\x1b[22m<gray>────</gray><gray>──╮</gray>",
  );
});

test("truncates an overlong status line without breaking the width", async () => {
  const line = top(await loadShape(), { status: { content: "abcdefghij", width: 10 } });
  expect(line).toBe("<gray>╭──</gray>\x1b[1mabcd…\x1b[22m<gray>─</gray><gray>──╮</gray>");
  expect(stripAnsi(line ?? "").length).toBe(12);
});

test("draws box side and bottom chrome around each row", async () => {
  const shape = await loadShape();
  const [side] = row(shape, { text: "hi", pad: "    " });
  expect(side).toBe("<gray>│  </gray>hi    <gray>  │</gray>");
  expect(stripAnsi(side).length).toBe(12);
  const [bottom] = row(shape, { last: true, text: "input", pad: " " });
  expect(bottom).toBe("<gray>╰─ </gray>input <gray> ─╯</gray>");
  expect(stripAnsi(bottom).length).toBe(12);
});
