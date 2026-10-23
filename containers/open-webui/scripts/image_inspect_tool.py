"""title: Inspect Image
description: Crop, rotate, and adjust contrast on a chat-attached image for visual inspection.
"""

# pyright: reportMissingImports=false

import base64
import io
import math

from PIL import Image, ImageEnhance, ImageOps


class Tools:
    async def inspect_image(
        self,
        left: float,
        top: float,
        right: float,
        bottom: float,
        image_index: int = 0,
        angle: float = 0,
        contrast: float = 1,
        grayscale: bool = False,
        __messages__: list | None = None,
        __files__: list | None = None,
        __user__: dict | None = None,
    ) -> str:
        """Return pixels of a processed chat image to the vision model, not just a URL.

        :param left: Left edge as a fraction of the original image width (0 to 1).
        :param top: Top edge as a fraction of the original image height (0 to 1).
        :param right: Right edge as a fraction of the original image width (0 to 1).
        :param bottom: Bottom edge as a fraction of the original image height (0 to 1).
        :param image_index: Image index in newest-first attachment order; default 0.
        :param angle: Counterclockwise rotation in degrees (-180 to 180), after cropping.
        :param contrast: Contrast multiplier from 0.5 to 3; default 1 leaves pixels unchanged.
        :param grayscale: Remove color for reading faint details; do not infer colors from this output.
        """
        from open_webui.models.users import UserModel
        from open_webui.utils.files import get_image_base64_from_file_id

        bounds = (left, top, right, bottom)
        if not all(
            math.isfinite(value) for value in (*bounds, angle, contrast)
        ) or not (
            0 <= left < right <= 1
            and 0 <= top < bottom <= 1
            and -180 <= angle <= 180
            and 0.5 <= contrast <= 3
        ):
            return "Error: invalid crop, rotation, or contrast settings."
        if not __user__:
            return "Error: user identity is required to inspect an attachment."

        attachments = [
            file
            for message in reversed(__messages__ or [])
            if isinstance(message, dict) and message.get("role") == "user"
            for file in reversed(message.get("files") or [])
        ] + list(reversed(__files__ or []))
        images = []
        for attachment in attachments:
            if not isinstance(attachment, dict):
                continue
            file = attachment.get("file") or attachment
            if not isinstance(file, dict):
                continue
            content_type = attachment.get("content_type") or file.get("content_type")
            if file.get("id") and (
                not content_type
                or isinstance(content_type, str)
                and content_type.startswith("image/")
            ):
                images.append(file["id"])
        images = list(dict.fromkeys(images))
        if image_index < 0 or image_index >= len(images):
            return f"Error: image_index is outside the {len(images)} attached images."

        encoded = await get_image_base64_from_file_id(
            images[image_index], user=UserModel(**__user__)
        )
        if not encoded or not encoded.startswith("data:image/"):
            return "Error: attached image is unavailable or is not an image."
        raw = base64.b64decode(encoded.split(",", 1)[1])
        if len(raw) > 20 * 1024 * 1024:
            return "Error: image exceeds the 20 MiB processing limit."

        with Image.open(io.BytesIO(raw)) as source:
            width, height = source.size
            if width * height > 50_000_000:
                return "Error: image exceeds the 50 megapixel processing limit."
            box = (
                int(left * width),
                int(top * height),
                min(width, math.ceil(right * width)),
                min(height, math.ceil(bottom * height)),
            )
            if box[2] - box[0] < 2 or box[3] - box[1] < 2:
                return "Error: crop contains fewer than two source pixels per side."
            crop = source.crop(box).convert("RGB")

        if angle:
            crop = crop.rotate(angle, expand=True)
        if grayscale:
            crop = ImageOps.grayscale(crop)
        if contrast != 1:
            crop = ImageEnhance.Contrast(crop).enhance(contrast)
        scale = min(3, 1536 / max(crop.size))
        if scale != 1:
            crop = crop.resize(
                (round(crop.width * scale), round(crop.height * scale)),
                Image.Resampling.LANCZOS,
            )
        output = io.BytesIO()
        crop.save(output, format="PNG")
        return "data:image/png;base64," + base64.b64encode(output.getvalue()).decode(
            "ascii"
        )
