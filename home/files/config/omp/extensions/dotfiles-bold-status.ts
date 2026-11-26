import type { ComposerShape, ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { truncate, visibleWidth } from "@oh-my-pi/pi-tui/text/width";

/** Keep bold across the status line's own style resets. */
const boldStatus = (content: string) =>
  `\x1b[1m${content.replaceAll("\x1b[0m", "\x1b[0m\x1b[1m")}\x1b[22m`;

const boldStatusBox: ComposerShape = {
  id: "dotfiles-bold-status",
  label: "Bold Status Box",
  description: "Rounded box with the status line in bold",
  statusAttachment: "top-border",
  bottomBar: "none",
  sideBorders: true,
  paddingX: 2,
  sideWidth: (paddingX) => paddingX + 1,
  top(cx) {
    const { box, paddingX, width, status } = cx;
    const left = cx.border(`${box.topLeft}${box.horizontal.repeat(paddingX)}`);
    const right = cx.border(`${box.horizontal.repeat(paddingX)}${box.topRight}`);
    const span = Math.max(0, width - (paddingX + 1) * 2);
    if (!status) return left + cx.border(box.horizontal.repeat(span)) + right;
    const content =
      status.width <= span ? status.content : truncate(status.content, Math.max(0, span - 1));
    const used = status.width <= span ? status.width : visibleWidth(content);
    return (
      left +
      boldStatus(content) +
      cx.border(box.horizontal.repeat(Math.max(0, span - used))) +
      right
    );
  },
  row(cx) {
    const { box, paddingX } = cx;
    const rightPadding = Math.max(1, paddingX + 1 - cx.overflow);
    if (cx.last) {
      const left = cx.border(
        `${box.bottomLeft}${box.horizontal}${" ".repeat(Math.max(0, paddingX - 1))}`,
      );
      const right = cx.border(
        `${" ".repeat(Math.max(0, rightPadding - 2))}${rightPadding >= 2 ? box.horizontal : ""}${box.bottomRight}`,
      );
      return [`${left}${cx.text}${cx.pad}${right}`];
    }
    const left = cx.border(`${box.vertical}${" ".repeat(paddingX)}`);
    const right = cx.border(`${" ".repeat(rightPadding - 1)}${box.vertical}`);
    return [`${left}${cx.text}${cx.pad}${right}`];
  },
};

export default function (pi: ExtensionAPI) {
  pi.registerComposerShape(boldStatusBox);
}
