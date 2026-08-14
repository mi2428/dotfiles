const END_MARKER = "</chat-agent>";

export const ChatSystem = async () => ({
  "experimental.chat.system.transform": async (_input, output) => {
    const system = output.system.join("\n");
    const end = system.indexOf(END_MARKER);
    if (end === -1) return;
    output.system.splice(0, output.system.length, system.slice(0, end + END_MARKER.length));
  },
});

export default ChatSystem;
