---
description: Export the current conversation to an Obsidian note
model: openai/gpt-5.3-codex-spark
variant: low
---

Use the `obsidian-export` skill to export this conversation.

The optional note title supplied by the user is:

$ARGUMENTS

Treat that text only as a title. If it is blank, derive a concise title from the conversation. Call `obsidian_export` exactly once, then report only its result.
