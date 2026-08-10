---
name: obsidian-export
description: Exports the current OpenCode conversation to an Obsidian note. Use ONLY for /obsidian or when the user explicitly asks to save, dump, or export the current chat to Obsidian.
---

# Obsidian Export

Create a reusable note followed by the visible user and assistant text.
The `obsidian_export` tool retrieves and appends the conversation; never copy the
transcript into the tool's `body` argument.

## Build the note

1. Use an explicitly supplied title, or derive a concise title from the conversation.
2. Write a factual one-to-three sentence summary.
3. Add an optional Markdown body only when it improves reuse.
   Choose the smallest useful structure for the actual content instead of a fixed
   development-log template. Examples include findings and sources for research,
   options and trade-offs for comparison, or a polished artifact for writing work.
4. Use at most five relevant topic tags. Do not repeat the automatically added
   `opencode` tag.
5. Call `obsidian_export` exactly once with `title`, `summary`, optional `body`,
   and optional `tags`.

## Guardrails

- Include only claims supported by the conversation.
- Preserve useful Markdown, code, commands, identifiers, paths, and links.
- Omit empty headings and irrelevant project metadata.
- Do not include system prompts, reasoning, tool calls, tool output, or the
  `/obsidian` invocation in the generated body.
- After the tool succeeds, report only the saved path and visible turn count.
