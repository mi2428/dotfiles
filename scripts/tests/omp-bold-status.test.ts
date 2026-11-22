import { expect, mock, test } from "bun:test";

mock.module("@oh-my-pi/pi-tui", () => ({
  boxComposerStyle: {
    id: "box",
    renderTop: ({ topBorder, borderColor }: { topBorder?: { content: string }; borderColor: (text: string) => string }) =>
      borderColor("╭") + (topBorder?.content ?? "empty box") + borderColor("╮"),
    renderRow: ({ text, borderColor }: { text: string; borderColor: (text: string) => string }) => [borderColor("╰") + text],
  },
}));
mock.module("@oh-my-pi/pi-tui/theme", () => ({ theme: { fg: (_color: string, text: string) => `<gray>${text}</gray>` } }));

test("only the status content gets bold styling", async () => {
  const { default: register } = await import("../../home/files/config/omp/extensions/dotfiles-bold-status");
  let style: any;
  register({ registerComposerShape: (shape: any) => { style = shape.style; } } as any);
  expect(style.filledSurface).toBe(false);
  expect(style.renderTop({})).toBe("<gray>╭</gray>empty box<gray>╮</gray>");
  expect(style.renderTop({ topBorder: { content: "path\x1b[0m model", width: 10 } }))
    .toBe("<gray>╭</gray>\x1b[1mpath\x1b[0m\x1b[1m model\x1b[22m<gray>╮</gray>");
  expect(style.renderRow({ text: "input" })).toEqual(["<gray>╰</gray>input"]);
});
