const POLICY = `<session-title>
On the first user request in a top-level session, use the model answering this conversation to summarize that first question as a short, specific title in the conversation's language. Call session_title with that summary during your normal response; do not quote or truncate the question, use a separate title-only model call, or mention the title to the user. After that, call session_title only if the main topic substantially changes and the old title becomes misleading, not for follow-ups or brief asides. Never include secrets or sensitive details. Do not call it in child sessions.
</session-title>`;

export const SessionTitle = async ({ client }) => ({
  "experimental.chat.system.transform": async ({ sessionID }, output) => {
    if (sessionID) output.system.unshift(POLICY);
  },
  tool: {
    session_title: {
      description: "Set the current conversation's title. Call once during the first response with an AI summary of the first user question; call again only when the main topic substantially changes.",
      args: {
        title: { type: "string", minLength: 1, maxLength: 80, description: "A short, descriptive title without secrets" },
      },
      async execute({ title }, { sessionID, directory }) {
        if (typeof title !== "string" || !title.trim() || title.length > 80) throw new Error("Invalid session title");
        const current = await client.session.get({ path: { id: sessionID }, query: { directory } });
        if (current.error || !current.data) throw new Error("Could not read the current session");
        if (current.data.parentID) return "Child session title unchanged";

        const normalized = title.replace(/\s+/g, " ").trim();
        if (normalized === current.data.title) return "Session title unchanged";
        const updated = await client.session.update({
          path: { id: sessionID },
          query: { directory },
          body: { title: normalized },
        });
        if (updated.error || !updated.data) throw new Error("Could not update the session title");
        return "Session title updated";
      },
    },
  },
});

export default SessionTitle;
