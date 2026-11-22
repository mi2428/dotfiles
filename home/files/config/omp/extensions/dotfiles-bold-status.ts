import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { boxComposerStyle } from "@oh-my-pi/pi-tui";
import { theme } from "@oh-my-pi/pi-tui/theme";

const borderColor = (text: string) => theme.fg("border", text);

export default function (pi: ExtensionAPI) {
  pi.registerComposerShape({
    label: "Bold Status Box",
    style: {
      ...boxComposerStyle,
      id: "dotfiles-bold-status",
      filledSurface: false,
      renderTop(ctx) {
        const topBorder = ctx.topBorder;
        if (!topBorder) return boxComposerStyle.renderTop({ ...ctx, borderColor });
        const content = topBorder.content.replaceAll("\x1b[0m", "\x1b[0m\x1b[1m");
        return boxComposerStyle.renderTop({
          ...ctx,
          borderColor,
          topBorder: { ...topBorder, content: `\x1b[1m${content}\x1b[22m` },
        });
      },
      renderRow(ctx) {
        return boxComposerStyle.renderRow({ ...ctx, borderColor });
      },
    },
  });
}
