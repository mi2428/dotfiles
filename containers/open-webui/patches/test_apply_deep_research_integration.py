import unittest

from apply_deep_research_integration import (
    CHAT_REPLACEMENTS,
    MAIN_REPLACEMENTS,
    MIDDLEWARE_REPLACEMENTS,
    patch_source,
    replace_once,
)


class DeepResearchPatchTests(unittest.TestCase):
    def test_guards_reject_missing_and_ambiguous_source(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "patch guard failed"):
            replace_once("source", "missing", "new", "test")
        with self.assertRaisesRegex(RuntimeError, "patch guard failed"):
            replace_once("old old", "old", "new", "test")

    def test_backend_guards_and_async_task_boundary_are_connected(self) -> None:
        main = patch_source(
            "\n".join(old for old, _ in MAIN_REPLACEMENTS), MAIN_REPLACEMENTS, "main"
        )
        middleware = patch_source(
            "\n".join(old for old, _ in MIDDLEWARE_REPLACEMENTS),
            MIDDLEWARE_REPLACEMENTS,
            "middleware",
        )
        self.assertIn("await persist_deep_research_intent(metadata)", main)
        self.assertIn("missing_base_model=missing_base_model", main)
        self.assertIn("require_registry=True", main)
        self.assertIn("direct=True", main)
        self.assertLess(
            main.index("managed_deep_research = await is_managed_deep_research_model"),
            main.index("if missing_base_model and ENABLE_CUSTOM_MODEL_FALLBACK"),
        )
        self.assertIn("trusted_research['completed']", main)
        self.assertIn("request_deep_research_stop", main)
        self.assertIn("not is_trusted_deep_research(metadata)", main)
        self.assertIn(
            "return managed_pipe_payload(form_data, metadata), metadata, []", middleware
        )
        self.assertIn(
            "if is_trusted_deep_research(metadata):\n        return", middleware
        )
        # The patch leaves upstream create_task fan-out intact: POST does not await the long Pipe.
        self.assertNotIn("await process_chat(", main)

    def test_frontend_reattaches_same_action_and_omits_managed_defaults(self) -> None:
        chat = patch_source(
            "\n".join(old for old, _ in CHAT_REPLACEMENTS), CHAT_REPLACEMENTS, "chat"
        )
        self.assertIn("message_id: message.id", chat)
        self.assertIn("reattachResponse: true", chat)
        self.assertIn(
            "typeof message.meta?.deep_research?.intent_signature === 'string'", chat
        )
        self.assertIn("!['delivered', 'needs_review', 'paused'", chat)
        self.assertIn(
            "!hasPendingAssistantLeaf() && !getReattachableDeepResearchMessage()", chat
        )
        self.assertIn("let messages: any[] = managedDeepResearch\n\t\t\t? []", chat)
        self.assertIn("params: managedDeepResearch", chat)
        self.assertIn("variables: managedDeepResearch", chat)
        self.assertIn("tool_servers: managedDeepResearch", chat)
        self.assertIn("continueResponse || reattachResponse", chat)
        self.assertIn("if (!managedDeepResearch && $settings?.userLocation)", chat)
        self.assertIn("if (!stopped) return", chat)


if __name__ == "__main__":
    unittest.main()
