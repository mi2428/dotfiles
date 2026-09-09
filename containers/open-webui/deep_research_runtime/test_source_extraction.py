from __future__ import annotations

import asyncio
import io
import json
import os
import sys
import unittest
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

import source_extraction as extraction


class FakePage:
    def __init__(self, text: str) -> None:
        self.text = text

    def extract_text(self) -> str:
        return self.text


def fake_pypdf(pages: object) -> ModuleType:
    module = ModuleType("pypdf")

    class Reader:
        def __init__(self, _stream: object) -> None:
            self.pages = pages

    module.PdfReader = Reader  # type: ignore[attr-defined]
    return module


def synthetic_pdf() -> bytes:
    from pypdf import PdfWriter
    from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

    writer = PdfWriter()
    font = DictionaryObject(
        {
            NameObject("/BaseFont"): NameObject("/Helvetica"),
            NameObject("/Subtype"): NameObject("/Type1"),
            NameObject("/Type"): NameObject("/Font"),
        }
    )
    font_reference = writer._add_object(font)
    for text in (b"Page one", b"Page two"):
        page = writer.add_blank_page(width=612, height=792)
        page[NameObject("/Resources")] = DictionaryObject(
            {NameObject("/Font"): DictionaryObject({NameObject("/F1"): font_reference})}
        )
        stream = DecodedStreamObject()
        stream.set_data(b"BT /F1 12 Tf 72 720 Td (" + text + b") Tj ET")
        page[NameObject("/Contents")] = writer._add_object(stream)
    output = io.BytesIO()
    writer.write(output)
    return output.getvalue()


def synthetic_spawner(
    code: str,
    processes: list[asyncio.subprocess.Process],
    started: asyncio.Event | None = None,
) -> Any:
    create_subprocess_exec = asyncio.create_subprocess_exec

    async def spawn(*_args: object, **kwargs: Any) -> asyncio.subprocess.Process:
        process = await create_subprocess_exec(
            sys.executable,
            "-c",
            code,
            stdin=kwargs["stdin"],
            stdout=kwargs["stdout"],
            stderr=kwargs["stderr"],
            env=kwargs["env"],
        )
        processes.append(process)
        if started is not None:
            started.set()
        return process

    return spawn


PIPE_BURST = 256 * 1024
PIPE_SCRIPT = (
    "import sys,time;sys.stdin.buffer.read();"
    f"sys.stdout.buffer.write(b'x'*{PIPE_BURST});sys.stdout.buffer.flush();time.sleep(10)"
)
TEST_DIRECTORY = str(Path(__file__).resolve().parent)
CPU_SCRIPT = (
    "import source_extraction as e;e.CPU_SECONDS=1;e._set_resource_limits();"
    "exec('while True: pass')"
)


class SourceExtractionTests(unittest.IsolatedAsyncioTestCase):
    def test_html_text_and_full_pdf_page_map_without_truncation(self) -> None:
        html = (
            b'<html><head><meta charset="iso-8859-1"></head><body><article>'
            b"<h1>Public title</h1><p>Caf\xe9 public evidence paragraph with enough words.</p>"
            b"<p>Second public evidence paragraph remains available.</p></article></body></html>"
        )
        text, pages, limitations = extraction._extract_child(html, "text/html", 10_000)
        self.assertIn("Café public evidence", text)
        self.assertEqual(pages, [{"page": 1, "start": 0, "end": len(text)}])
        self.assertEqual(len(limitations), 1)

        page_fixture = [FakePage("Cafe\u0301"), FakePage(""), FakePage("Page three")]
        with patch.dict(sys.modules, {"pypdf": fake_pypdf(page_fixture)}):
            text, pages, limitations = extraction._extract_child(
                b"synthetic-pdf", "application/pdf", 10_000
            )
        self.assertEqual(text, "Café\n\nPage three")
        self.assertEqual(
            pages,
            [
                {"page": 1, "start": 0, "end": 4},
                {"page": 2, "start": 4, "end": 4},
                {"page": 3, "start": 6, "end": 16},
            ],
        )
        self.assertEqual(len(limitations), 1)

    def test_parser_text_and_page_caps_fail_without_fallback(self) -> None:
        with self.assertRaisesRegex(ValueError, "EXTRACTION_TEXT_TOO_LARGE"):
            extraction._extract_child(b"too long", "text/plain", 3)
        with self.assertRaisesRegex(ValueError, "EXTRACTION_ENCODING_INVALID"):
            extraction._extract_child(b"\xff", "text/plain", 100)
        text, pages, _limitations = extraction._extract_child(
            "Cafe\u0301".encode(), "text/plain", 100
        )
        self.assertEqual((text, pages[0]["end"]), ("Café", 4))
        with self.assertRaisesRegex(ValueError, "EXTRACTION_PARSE_FAILED"):
            extraction._extract_child(b"", "text/html", 100)

        class TooManyPages:
            def __len__(self) -> int:
                return extraction.MAX_PAGES + 1

        with (
            patch.dict(sys.modules, {"pypdf": fake_pypdf(TooManyPages())}),
            self.assertRaisesRegex(ValueError, "EXTRACTION_PAGE_LIMIT"),
        ):
            extraction._extract_child(b"synthetic-pdf", "application/pdf", 100)

    async def test_public_input_bounds_and_platform_limit_are_visible(self) -> None:
        for raw, media_type, max_chars, code in (
            (b"", "text/plain", 10, "EXTRACTION_INPUT_INVALID"),
            (b"x" * (extraction.MAX_RAW_BYTES + 1), "text/plain", 10, "EXTRACTION_INPUT_INVALID"),
            (b"x", "image/png", 10, "EXTRACTION_MEDIA_TYPE_UNSUPPORTED"),
            (b"x", "text/plain", 0, "EXTRACTION_MAX_CHARS_INVALID"),
        ):
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, code):
                await extraction.extract_document(raw, media_type, max_chars)

        if sys.platform == "linux":
            text, pages, limitations = await extraction.extract_document(
                b"public text", "text/plain", 100
            )
            self.assertEqual(
                (text, pages, limitations),
                ("public text", [{"page": 1, "start": 0, "end": 11}], []),
            )
        else:
            with self.assertRaisesRegex(ValueError, "EXTRACTION_RESOURCE_UNSUPPORTED"):
                await extraction.extract_document(b"public text", "text/plain", 100)

    @unittest.skipUnless(sys.platform == "linux", "Linux resource contract")
    async def test_linux_public_child_imports_real_html_and_pdf_parsers(self) -> None:
        html = (
            b"<html><body><article><h1>Public title</h1>"
            b"<p>Public evidence paragraph with enough words for extraction.</p>"
            b"<p>Second public evidence paragraph remains available.</p></article></body></html>"
        )
        text, pages, limitations = await extraction.extract_document(html, "text/html", 10_000)
        self.assertIn("Public evidence paragraph", text)
        self.assertEqual(pages, [{"page": 1, "start": 0, "end": len(text)}])
        self.assertEqual(len(limitations), 1)

        text, pages, limitations = await extraction.extract_document(
            synthetic_pdf(), "application/pdf", 10_000
        )
        self.assertEqual(text, "Page one\n\nPage two")
        self.assertEqual(
            pages,
            [
                {"page": 1, "start": 0, "end": 8},
                {"page": 2, "start": 10, "end": 18},
            ],
        )
        self.assertEqual(len(limitations), 1)

    @unittest.skipUnless(sys.platform == "linux", "Linux resource contract")
    async def test_linux_child_enforces_address_space_and_cpu_limits(self) -> None:
        memory_code = (
            "import source_extraction as e;e._set_resource_limits();"
            "\ntry: bytearray(e.ADDRESS_SPACE_BYTES)"
            "\nexcept MemoryError: raise SystemExit(73)"
            "\nraise SystemExit(0)"
        )
        memory = await asyncio.create_subprocess_exec(
            sys.executable,
            "-c",
            memory_code,
            cwd=TEST_DIRECTORY,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            env=extraction._child_environment(),
        )
        try:
            returncode = await asyncio.wait_for(memory.wait(), 3)
        finally:
            if memory.returncode is None:
                memory.kill()
                await memory.wait()
        self.assertEqual(returncode, 73)

        cpu = await asyncio.create_subprocess_exec(
            sys.executable,
            "-c",
            CPU_SCRIPT,
            cwd=TEST_DIRECTORY,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            env=extraction._child_environment(),
        )
        try:
            returncode = await asyncio.wait_for(cpu.wait(), 4)
        finally:
            if cpu.returncode is None:
                cpu.kill()
                await cpu.wait()
        self.assertLess(returncode, 0)

    def test_secret_environment_is_not_in_child_environment(self) -> None:
        with patch.dict(os.environ, {"PRIVATE_MARKER": "dummy-public-value"}):
            self.assertEqual(
                extraction._child_environment(),
                {"PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"},
            )
            self.assertNotIn("PRIVATE_MARKER", extraction._child_environment())
        self.assertIn("Café".encode(), extraction._json_bytes({"text": "Café"}))
        self.assertNotIn(b"\\u00e9", extraction._json_bytes({"text": "Café"}))

    def test_resource_limit_failure_is_fixed_and_visible(self) -> None:
        with (
            patch.object(extraction.sys, "platform", "unsupported"),
            self.assertRaisesRegex(ValueError, "EXTRACTION_RESOURCE_UNSUPPORTED"),
        ):
            extraction._set_resource_limits()

    async def test_timeout_drains_large_pipe_and_waits_for_real_child(self) -> None:
        processes: list[asyncio.subprocess.Process] = []
        with (
            patch.object(extraction, "WALL_SECONDS", 0.05),
            patch.object(extraction, "MAX_STDOUT_BYTES", PIPE_BURST * 2),
            patch.object(
                extraction.asyncio,
                "create_subprocess_exec",
                side_effect=synthetic_spawner(PIPE_SCRIPT, processes),
            ),
            self.assertRaisesRegex(ValueError, "EXTRACTION_TIMEOUT"),
        ):
            await extraction.extract_document(b"public", "text/plain", 100)
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].returncode)

    async def test_cancellation_drains_large_pipe_and_waits_for_real_child(self) -> None:
        processes: list[asyncio.subprocess.Process] = []
        started = asyncio.Event()
        with patch.object(
            extraction.asyncio,
            "create_subprocess_exec",
            side_effect=synthetic_spawner(PIPE_SCRIPT, processes, started),
        ):
            task = asyncio.create_task(extraction.extract_document(b"public", "text/plain", 100))
            await started.wait()
            await asyncio.sleep(0.02)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertIsNotNone(processes[0].returncode)

    async def test_oversize_output_drains_and_waits_for_real_child(self) -> None:
        processes: list[asyncio.subprocess.Process] = []
        with (
            patch.object(extraction, "MAX_STDOUT_BYTES", 1024),
            patch.object(
                extraction.asyncio,
                "create_subprocess_exec",
                side_effect=synthetic_spawner(PIPE_SCRIPT, processes),
            ),
            self.assertRaisesRegex(ValueError, "EXTRACTION_OUTPUT_TOO_LARGE"),
        ):
            await extraction.extract_document(b"public", "text/plain", 100)
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].returncode)

    async def test_invalid_output_and_abnormal_exit_are_rejected(self) -> None:
        invalid = json.dumps({"text": "public"}).encode()
        with self.assertRaisesRegex(ValueError, "EXTRACTION_OUTPUT_INVALID"):
            extraction._validate_result(invalid, 100, 0)
        valid = json.dumps(
            {"limitations": [], "page_map": [{"end": 1, "page": 1, "start": 0}], "text": "x"}
        ).encode()
        with self.assertRaisesRegex(ValueError, "EXTRACTION_CHILD_FAILED"):
            extraction._validate_result(valid, 100, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
