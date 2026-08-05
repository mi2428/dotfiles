# Global OpenCode instructions

- Respond in Japanese unless the user requests another language.
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
