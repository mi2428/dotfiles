---
description: Translate short Japanese text into Title, OSS, and Chat English
model: openai/gpt-5.3-codex-spark
variant: low
subtask: true
---

Translate the following short Japanese text into three natural English versions:

$ARGUMENTS

Output exactly in this format, without code fences:

### Title
<translation>

### OSS
<translation>

### Chat
<translation>

Rules:
- Title: A concise GitHub issue or pull request title in sentence case, with no trailing period. Prefer an imperative for a proposed change and a short noun phrase for a problem or topic, whichever is more natural.
- OSS: Natural English for GitHub issues, pull request bodies, reviews, and README files. Professional, concise, and not stiff.
- Chat: Casual internal chat. Short fragments and omitted subjects are welcome, but avoid excessive slang.
- Preserve Markdown, code, paths, identifiers, URLs, and issue references.
- Do not add information or assumptions.
- Output only the three translations without explanations.
