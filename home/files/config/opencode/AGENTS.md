# Global OpenCode instructions

- Use Japanese for all visible natural-language communication unless the user explicitly requests another language. This includes progress updates, work reports, task delegation prompts, agent-to-agent messages, worker reports, summaries, questions, and final responses.
- Preserve code, commands, identifiers, file paths, logs, error messages, and quoted source text in their original language when translating them would reduce accuracy.
- Do not expose private chain-of-thought. Provide only concise conclusions, evidence, and decision rationale in Japanese.
- Read the repository's own instructions and conventions before editing files.
- Preserve unrelated user changes and work safely in a dirty worktree.
- Prefer `rg` and `rg --files` for searching when available.
- Use the repository's own task runner, formatter, linter, and test commands.
- When creating commits, always use Conventional Commits with an appropriate type, such as `feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, or `docs:`.
- After editing, run checks proportional to the change and report their results.
- Immediately before asking the user a question that requires their response, announce it exactly once with Kyoko at rate 250. Use the fixed privacy-safe phrase below; never interpolate external or user-controlled text.

  ```sh
  if command -v say >/dev/null 2>&1; then
    say -v Kyoko -r 250 "質問があります"
  fi
  ```
