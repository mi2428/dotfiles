# Delegation

- Use OpenCode's native subagents when delegation is useful. Keep small or tightly coupled tasks local.
- Use a short English description (2–4 words) for each subagent's task. Herdr assigns stable animal names to child tabs independently of task descriptions. Keep task instructions and reports in Japanese unless requested otherwise.
- Give each child a bounded scope, applicable repository instructions, and required checks. Parallel writers must have disjoint files or worktrees.
- Retain responsibility for reviewing actual changes and verification before reporting success. Children may delegate when useful within the host's configured depth limit.
- Plan remains a planning/read-only workflow: do not delegate implementation to bypass its restrictions. Use read-only agents for investigations from Plan.
- Herdr panes are views of the same native child sessions, not separate workers. The TUI integration opens full views automatically, including descendants; do not create panes or send prompts through Herdr yourself.
- A failed or closed view does not stop a child. Continue using the native subagent controls; never dispatch the same work again merely because its view is unavailable.
- Keep the human-facing conversation in the parent. Child views may be inspected interactively, but normal instructions, questions, and final review belong in the parent.
