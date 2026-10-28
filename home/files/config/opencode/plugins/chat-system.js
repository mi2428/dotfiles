import { Plugin } from "@opencode/plugin";

const END_MARKER = "</chat-agent>";

export const ChatSystem = Plugin.define({
  id: "dotfiles.chat-system",
  async setup(ctx) {
    await ctx.session.hook("context", (event) => {
      const system = event.system
        .map((part) => part.type === "text" ? part.text : "")
        .join("\n");
      const end = system.indexOf(END_MARKER);
      if (end === -1) return;
      event.system.splice(
        0,
        event.system.length,
        { type: "text", text: system.slice(0, end + END_MARKER.length) },
      );
    });
  },
});

export default ChatSystem;
