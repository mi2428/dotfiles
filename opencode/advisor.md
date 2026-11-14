# Advisor alias command

```text
/advisor sol hoge fuga poyo
```

The first word is a required alias. All remaining text is the question. `sol` is configured in `home/modules/core/opencode.nix` as `openai/gpt-6.1-sol#xhigh`. Unknown or missing aliases fail with “そのようなモデルはありません”; no model is guessed and no request is sent. A known alias without a question also fails. Add aliases under `advisorPlugin.options.aliases` in that file, then apply Home Manager.

There is one slash-command registration. It submits a durable user consultation request to the current session and asks the main assistant to call the `advisor` tool with the explicit alias and original question. The tool's labelled result is persisted by OpenCode in the same conversation. The main assistant reads it and continues; the user's consultation and the advice are no longer private to a popup. No model is switched. A configured alias remains mandatory; no model selector, fuzzy matching, saved selection or default advisor is used.

The active conversation's text and explicit question are sent via OpenCode's public experimental stateless text API. Private reasoning and image/file attachment contents are excluded automatically, including historical attachments and file-valued tool results. Attachments never block consultation and require no confirmation. An omission marker tells the advisor it did not receive attachment contents; it must not claim to have seen them. The original session and its attachments are unchanged. Model calls incur the selected provider's charges; the API does not expose advisor token usage. Do not claim that the parent session accounts for these charges.

Use `/advisor` for text-only advice that should return to the main conversation. When the other model needs to inspect images, use OpenCode's `/fork` workflow and select that model in the fork instead. That is a separate conversation; its findings are not automatically returned as an advisor tool result. The advisor plugin does not create forks or transfer structured model context.

The main assistant may also invoke the same tool at consequential decisions or repeated failures. This is model-driven, not an automatic consultation every turn. Explicit slash requests instruct it to call once with the original alias/question; actual tool invocation still depends on the main model following that instruction. The plugin does not fabricate a tool result if it does not.

No OpenCode source modifications, binary patches or custom builds are used. Apply through `task hm.switch HOST=macos` on this host.

```sh
bun test home/files/config/opencode/plugins/advisor.test.ts home/files/config/opencode/plugins/advisor.integration.test.ts
```
