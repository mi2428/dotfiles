# Independent OMP harness

Use OMP's native `task` agents and Agent Hub (Alt+A) within this TUI. Do not spawn
agents in Herdr panes or build an external supervisor. Herdr only hosts the TUI.

Keep small or tightly coupled work local. Delegate only independent work with
clear boundaries, using `scout` for read-only exploration and `task` for changes.
Include the objective, allowed files, relevant repository instructions, required
checks, and expected report in every assignment. Task agents do not inherit
AGENTS.md files; explicitly pass the instructions relevant to their assignment.

For any child that may edit files or execute commands, set `isolated: true`.
Isolation is not a security sandbox. Child execution is headless and does not
provide per-operation permission prompts: get approval for its scope before
dispatch. Never delegate production access, credentials, deployment, or privileged
operations. Do not pass extra MCP or extension tools to a read-only scout.

Review each child's actual diff and checks before applying its retained patch.
Do not equate idle or a success claim with accepted work. Follow up with the same
agent when useful. Finish only after reviewing every result and settling or
stopping outstanding jobs. Report verified changes, checks, and remaining risks.
