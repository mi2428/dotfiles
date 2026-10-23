"""Check that image inspection returns pixels and rejects invalid inputs."""

import base64
import io
import math
import sys
import types
import unittest
from unittest.mock import patch

from image_inspect_tool import Tools
from PIL import Image


class InspectImageTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        image = Image.new("RGB", (4, 3), "red")
        for x in (2, 3):
            for y in range(3):
                image.putpixel((x, y), (0, 0, 255))
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        encoded = (
            "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode()
        )

        async def get_image(file_id: str, user: types.SimpleNamespace) -> str | None:
            return encoded if file_id == "my-image" and user.id == "owner" else None

        async def accessible_chat(chat_id: str, user: types.SimpleNamespace):
            return chat_id == "my-chat" and user.id == "owner"

        async def message_files(chat_id: str, message_id: str, key: str):
            assert (chat_id, message_id, key) == ("my-chat", "my-message", "files")
            return [{"id": "my-image", "type": "file", "content_type": "image/png"}]

        modules = {
            name: types.ModuleType(name)
            for name in (
                "open_webui",
                "open_webui.models",
                "open_webui.models.users",
                "open_webui.models.chats",
                "open_webui.utils",
                "open_webui.utils.files",
            )
        }
        modules["open_webui.models.users"].__dict__["UserModel"] = lambda **data: (
            types.SimpleNamespace(**data)
        )
        modules["open_webui.utils.files"].__dict__["get_image_base64_from_file_id"] = (
            get_image
        )
        modules["open_webui.models.chats"].__dict__["Chats"] = types.SimpleNamespace(
            get_accessible_chat_by_id=accessible_chat,
            get_message_metadata=message_files,
        )
        self.module_patch = patch.dict(sys.modules, modules)
        self.module_patch.start()
        self.addCleanup(self.module_patch.stop)
        self.tool = Tools()
        self.attached = {
            "__files__": [{"file": {"id": "my-image"}}],
            "__user__": {"id": "owner"},
        }

    async def test_crop_rotate_and_adjust_contrast(self) -> None:
        output = await self.tool.inspect_image(0.5, 0, 1, 1, angle=90, **self.attached)
        self.assertTrue(output.startswith("data:image/png;base64,"))
        with Image.open(io.BytesIO(base64.b64decode(output.split(",", 1)[1]))) as crop:
            self.assertEqual(crop.size, (9, 6))
            self.assertEqual(crop.getpixel((4, 3)), (0, 0, 255))

        output = await self.tool.inspect_image(
            0, 0, 1, 1, grayscale=True, contrast=2, **self.attached
        )
        with Image.open(io.BytesIO(base64.b64decode(output.split(",", 1)[1]))) as crop:
            self.assertEqual(crop.mode, "L")
        output = await self.tool.inspect_image(
            0, 0, 1, 1, contrast=0.5, **self.attached
        )
        with Image.open(io.BytesIO(base64.b64decode(output.split(",", 1)[1]))) as crop:
            self.assertNotEqual(crop.getpixel((1, 1)), (255, 0, 0))

    async def test_saved_image_when_model_messages_and_metadata_files_are_empty(
        self,
    ) -> None:
        output = await self.tool.inspect_image(
            0.5,
            0,
            1,
            1,
            __metadata__={"chat_id": "my-chat", "user_message_id": "my-message"},
            __files__=[],
            __user__={"id": "owner"},
        )
        with Image.open(io.BytesIO(base64.b64decode(output.split(",", 1)[1]))) as crop:
            self.assertEqual(crop.getpixel((4, 3)), (0, 0, 255))
        denied = await self.tool.inspect_image(
            0,
            0,
            1,
            1,
            __metadata__={"chat_id": "my-chat", "user_message_id": "my-message"},
            __user__={"id": "other"},
        )
        self.assertEqual(denied, "Error: chat is not accessible.")

    async def test_rejects_missing_images_and_invalid_geometry(self) -> None:
        self.assertIn("Error:", await self.tool.inspect_image(0, 0, 1, 1))
        self.assertIn(
            "Error:", await self.tool.inspect_image(0.5, 0, 0.5, 1, **self.attached)
        )
        self.assertIn(
            "Error:",
            await self.tool.inspect_image(0, 0, 1, 1, angle=181, **self.attached),
        )
        self.assertIn(
            "Error:",
            await self.tool.inspect_image(
                0, 0, 1, 1, contrast=math.nan, **self.attached
            ),
        )
        self.assertIn(
            "Error:",
            await self.tool.inspect_image(0, 0, 1, 1, image_index=1, **self.attached),
        )
        self.assertIn(
            "Error:",
            await self.tool.inspect_image(
                0,
                0,
                1,
                1,
                __files__=self.attached["__files__"],
                __user__={"id": "other"},
            ),
        )


if __name__ == "__main__":
    unittest.main()
