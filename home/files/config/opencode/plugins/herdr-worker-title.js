const PREFIX = "[Subagent] ";

export const HerdrWorkerTitle = async ({ client, directory, $ }) => {
  if (process.env.HERDR_AGENT_LAYOUT_WORKER !== "1") return {};

  const happierSessionId = process.env.HERDR_HAPPIER_WORKER === "1"
    ? process.env.HAPPIER_SESSION_ID
    : undefined;
  let lastHappierTitle;

  return {
    event: async ({ event }) => {
      if (event.type !== "session.updated") return;

      const session = event.properties?.info;
      if (
        !session?.id ||
        typeof session.title !== "string" ||
        session.title.startsWith("New session - ")
      ) {
        return;
      }

      const title = session.title.startsWith(PREFIX)
        ? session.title
        : `${PREFIX}${session.title}`;

      if (title !== session.title) {
        await client.session.update({
          path: { id: session.id },
          query: { directory },
          body: { title },
        });
      }

      if (happierSessionId && title !== lastHappierTitle) {
        await $`happier session set-title ${happierSessionId} ${title}`;
        lastHappierTitle = title;
      }
    },
  };
};

export default HerdrWorkerTitle;
