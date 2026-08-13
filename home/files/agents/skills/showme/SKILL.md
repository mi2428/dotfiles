---
name: showme
description: Explains the current topic as a rich HTML visualization in terminal-browser. Use ONLY for /showme or when the user explicitly asks to see, visualize, diagram, visually compare, 図解, or 可視化 the current topic.
---

# Showme

Explain the current topic as a rich, focused HTML visualization shown beside
the conversation. Skip the preamble and keep any accompanying prose brief.

Choose the visual form that makes the key point clearest:

1. Pseudocode for logic or algorithms.
2. A call tree for runtime flow.
3. A component tree for UI structure and relevant state boundaries.
4. A shallow file tree for ownership or broad refactors.
5. A `diff` when the point is what changes.
6. A flow diagram for interactions or data movement.

Keep only the calls, files, props, states, and boundaries needed for the current
question.

## HTML artifacts

For every invocation:

1. Create one polished, self-contained HTML artifact. Write it beside the
   repository only when it is an intentional project deliverable; otherwise use
   a temporary file under `${TMPDIR:-/tmp}`.
2. Use semantic HTML, inline CSS, and SVG where useful. Do not add dependencies,
   load remote scripts, or use external assets unless the user explicitly asks.
3. Use real labels and data from the conversation. Give the page clear visual
   hierarchy, high contrast, responsive layout, and useful detail rather than a
   prose document placed in cards. Avoid animation unless motion is the topic.
4. Open it beside the conversation with `terminal-browser`, even when an inline
   diagram would have been sufficient. Outside Herdr, use:

   ```bash
   terminal-browser open "/absolute/path/to/showme-topic.html" --split right
   ```

   Inside Herdr (`HERDR_ENV=1`), the OpenCode TUI may overwrite the terminal title
   that `terminal-browser --split` uses to find its parent pane. Instead, inspect
   the current pane dimensions and split through Herdr. Use a right split only
   when both resulting panes can remain at least 70 columns wide. Otherwise use a
   down split when both panes can remain at least 24 rows tall:

   ```bash
   layout="$(herdr pane layout --current)"
   width="$(printf '%s\n' "$layout" | jq -r --arg pane "$HERDR_PANE_ID" '.result.layout.panes[] | select(.pane_id == $pane) | .rect.width')"
   height="$(printf '%s\n' "$layout" | jq -r --arg pane "$HERDR_PANE_ID" '.result.layout.panes[] | select(.pane_id == $pane) | .rect.height')"
   if [ "$width" -ge 140 ]; then
     direction=right
   elif [ "$height" -ge 48 ]; then
     direction=down
   elif [ "$((width * 48))" -ge "$((height * 140))" ]; then
     direction=right
   else
     direction=down
   fi
   result="$(herdr pane split "$HERDR_PANE_ID" --direction "$direction" --ratio 0.5)"
   browser_pane="$(printf '%s\n' "$result" | jq -r '.result.pane.pane_id')"
   herdr pane run "$browser_pane" 'terminal-browser open "/absolute/path/to/showme-topic.html"'
   ```

   Do not focus the new pane or send raw keys to it.
5. Outside Herdr, verify with `terminal-browser ls --all --json` and inspect the
   page using explicit `--browser`/`--tab` selectors with `terminal-browser
   action` when practical. Inside Herdr, verify the returned pane with `herdr
   pane get`; its terminal title should start with `terminal-browser:`. Do not
   call `terminal-browser ls` from the OpenCode pane because it has the same
   terminal-title discovery limitation as `--split`.
6. Report the artifact path in one short line. Do not leave generated files in
   the repository unless the user requested a durable artifact.

If `terminal-browser` is unavailable or opening fails, report that limitation
and provide the best inline visualization instead of installing dependencies.
