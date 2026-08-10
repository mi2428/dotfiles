const PREFIX = "[Subagent] ";

export const HerdrWorkerTitle = async ({ client, directory }) => {
  if (process.env.HERDR_AGENT_LAYOUT_WORKER !== "1") return {};

  return {
    event: async ({ event }) => {
      if (event.type !== "session.updated") return;

      const session = event.properties?.info;
      if (
        !session?.id ||
        session.title.startsWith(PREFIX) ||
        session.title.startsWith("New session - ")
      ) {
        return;
      }

      await client.session.update({
        path: { id: session.id },
        query: { directory },
        body: { title: `${PREFIX}${session.title}` },
      });
    },
  };
};

export default HerdrWorkerTitle;
