const PREFIX = "[Subagent] ";
const SUPERVISOR = "Herdr Supervisor";

export const HerdrWorkerTitle = async ({ client, directory, $ }) => {
  const supervisorEnvironments = new Map();
  const hooks = {
    "chat.message": async ({ sessionID, agent }) => {
      if (
        !sessionID ||
        agent !== SUPERVISOR ||
        supervisorEnvironments.has(sessionID)
      ) return;

      try {
        const response = await $`herdr pane list`.json();
        const pane = response?.result?.panes?.find(
          ({ agent_session: session }) =>
            session?.source === "herdr:opencode" && session.value === sessionID,
        );
        if (!pane) return;

        supervisorEnvironments.set(sessionID, {
          HERDR_ENV: "1",
          HERDR_PANE_ID: pane.pane_id,
          HERDR_TAB_ID: pane.tab_id,
          HERDR_WORKSPACE_ID: pane.workspace_id,
        });
      } catch {
        supervisorEnvironments.delete(sessionID);
      }
    },
    "shell.env": async ({ sessionID }, output) => {
      const environment = supervisorEnvironments.get(sessionID);
      if (environment) Object.assign(output.env, environment);
    },
  };

  if (process.env.HERDR_AGENT_LAYOUT_WORKER !== "1") return hooks;

  return {
    ...hooks,
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
    },
  };
};

export default HerdrWorkerTitle;
