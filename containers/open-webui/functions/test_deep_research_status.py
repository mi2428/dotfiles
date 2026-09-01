import unittest

from deep_research_status import Filter


class DeepResearchStatusTest(unittest.IsolatedAsyncioTestCase):
    async def test_status_lifecycle_does_not_modify_body(self) -> None:
        events = []

        async def emit(event):
            events.append(event)

        body = {"messages": [{"role": "user", "content": "調査して"}]}
        filter_ = Filter()

        self.assertIs(await filter_.inlet(body, emit), body)
        self.assertIs(await filter_.outlet(body, emit), body)
        self.assertEqual(
            events[0]["data"]["description"], "Deep Researchを実行しています…"
        )
        self.assertEqual(events[0]["data"]["done"], False)
        self.assertEqual(events[1]["data"]["done"], True)
        self.assertEqual(events[1]["data"]["hidden"], True)


if __name__ == "__main__":
    unittest.main()
