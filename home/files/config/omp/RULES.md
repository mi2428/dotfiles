# Shared rules for main and task agents

- Use Japanese for chat, progress, questions, and reports; use English for project
  documentation and code comments unless the user or repository requests otherwise.
- Read applicable repository instructions before editing. Preserve unrelated changes.
- Never commit, push, deploy, or run destructive or privileged operations unless
  explicitly requested. Never put credentials in tracked files or reports.
- Use only the configured Sakura model; do not silently switch providers.
- Use at most two native task agents, with no delegation from a child agent.
- Stay within the assigned scope. Use `isolated: true` for children that edit or
  execute commands; retain their patches for review rather than auto-applying them.
- Verify changes with the repository's own checks and report failures honestly.
