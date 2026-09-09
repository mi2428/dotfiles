"""Resource-bounded HTML, plain-text, and PDF extraction subprocess."""

from __future__ import annotations

import asyncio
import io
import json
import sys
import unicodedata
from contextlib import suppress
from pathlib import Path
from typing import NoReturn

MAX_RAW_BYTES = 1_500_000
MAX_CHARS = 8_000_000
MAX_STDOUT_BYTES = 32 * 1024 * 1024
MAX_PAGES = 10_000
WALL_SECONDS = 20.0
CPU_SECONDS = 15
ADDRESS_SPACE_BYTES = 512 * 1024 * 1024
MODULE_PATH = str(Path(__file__).resolve())
SUPPORTED_MEDIA_TYPES = {
    "application/pdf",
    "application/xhtml+xml",
    "text/html",
    "text/plain",
}
SAFE_ERRORS = {
    "EXTRACTION_CHILD_FAILED",
    "EXTRACTION_EMPTY",
    "EXTRACTION_ENCODING_INVALID",
    "EXTRACTION_OUTPUT_INVALID",
    "EXTRACTION_OUTPUT_TOO_LARGE",
    "EXTRACTION_PAGE_LIMIT",
    "EXTRACTION_PARSE_FAILED",
    "EXTRACTION_RESOURCE_UNSUPPORTED",
    "EXTRACTION_TEXT_TOO_LARGE",
    "EXTRACTION_TIMEOUT",
}


class _ExtractionError(ValueError):
    pass


def _fail(code: str) -> NoReturn:
    raise _ExtractionError(code)


def _set_resource_limits() -> None:
    if sys.platform != "linux":
        _fail("EXTRACTION_RESOURCE_UNSUPPORTED")
    try:
        import resource

        resource.setrlimit(resource.RLIMIT_CPU, (CPU_SECONDS, CPU_SECONDS))
        resource.setrlimit(resource.RLIMIT_AS, (ADDRESS_SPACE_BYTES, ADDRESS_SPACE_BYTES))
        if resource.getrlimit(resource.RLIMIT_CPU)[0] != CPU_SECONDS or (
            resource.getrlimit(resource.RLIMIT_AS)[0] != ADDRESS_SPACE_BYTES
        ):
            _fail("EXTRACTION_RESOURCE_UNSUPPORTED")
    except (AttributeError, OSError, ValueError):
        _fail("EXTRACTION_RESOURCE_UNSUPPORTED")


def _bounded_text(text: str, max_chars: int) -> str:
    normalized = unicodedata.normalize("NFC", text).strip()
    if not normalized:
        _fail("EXTRACTION_EMPTY")
    if len(normalized) > max_chars:
        _fail("EXTRACTION_TEXT_TOO_LARGE")
    return normalized


def _extract_child(
    raw: bytes, media_type: str, max_chars: int
) -> tuple[str, list[dict[str, int]], list[str]]:
    if media_type == "application/pdf":
        from pypdf import PdfReader

        try:
            reader = PdfReader(io.BytesIO(raw))
            if len(reader.pages) > MAX_PAGES:
                _fail("EXTRACTION_PAGE_LIMIT")
            parts: list[str] = []
            pages: list[dict[str, int]] = []
            cursor = 0
            for number, page in enumerate(reader.pages, 1):
                page_text = unicodedata.normalize("NFC", page.extract_text() or "").strip()
                if page_text:
                    if parts:
                        cursor += 2
                    start = cursor
                    parts.append(page_text)
                    cursor += len(page_text)
                    if cursor > max_chars:
                        _fail("EXTRACTION_TEXT_TOO_LARGE")
                else:
                    start = cursor
                pages.append({"page": number, "start": start, "end": cursor})
        except _ExtractionError:
            raise
        except Exception:
            _fail("EXTRACTION_PARSE_FAILED")
        text = _bounded_text("\n\n".join(parts), max_chars)
        return (
            text,
            pages,
            ["PDF tables, figures, footnotes, or layout may not be fully represented."],
        )
    if media_type == "text/plain":
        try:
            decoded = raw.decode("utf-8")
        except UnicodeDecodeError:
            _fail("EXTRACTION_ENCODING_INVALID")
        text = _bounded_text(decoded, max_chars)
        return text, [{"page": 1, "start": 0, "end": len(text)}], []

    import trafilatura

    try:
        extracted = trafilatura.bare_extraction(
            raw,
            include_comments=False,
            include_tables=True,
            include_links=False,
            favor_precision=True,
            with_metadata=True,
        )
        if extracted is None:
            _fail("EXTRACTION_PARSE_FAILED")
        document = extracted if isinstance(extracted, dict) else extracted.as_dict()
        text = _bounded_text(str(document.get("text") or ""), max_chars)
    except _ExtractionError:
        raise
    except Exception:
        _fail("EXTRACTION_PARSE_FAILED")
    return (
        text,
        [{"page": 1, "start": 0, "end": len(text)}],
        ["HTML extraction may omit scripts, styling, or non-text media."],
    )


def _json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()


def _child_main(media_type: str, max_chars_text: str) -> int:
    try:
        _set_resource_limits()
        max_chars = int(max_chars_text)
        if media_type not in SUPPORTED_MEDIA_TYPES or not 1 <= max_chars <= MAX_CHARS:
            _fail("EXTRACTION_CHILD_FAILED")
        raw = sys.stdin.buffer.read(MAX_RAW_BYTES + 1)
        if len(raw) > MAX_RAW_BYTES:
            _fail("EXTRACTION_CHILD_FAILED")
        text, page_map, limitations = _extract_child(raw, media_type, max_chars)
        output = _json_bytes({"limitations": limitations, "page_map": page_map, "text": text})
        if len(output) > MAX_STDOUT_BYTES:
            _fail("EXTRACTION_OUTPUT_TOO_LARGE")
    except _ExtractionError as error:
        output = _json_bytes({"error": str(error)})
        status = 2
    except BaseException:
        output = _json_bytes({"error": "EXTRACTION_CHILD_FAILED"})
        status = 2
    else:
        status = 0
    sys.stdout.buffer.write(output)
    sys.stdout.buffer.flush()
    return status


async def _write_stdin(process: asyncio.subprocess.Process, raw: bytes) -> None:
    if process.stdin is None:
        _fail("EXTRACTION_CHILD_FAILED")
    process.stdin.write(raw)
    try:
        await process.stdin.drain()
    except (BrokenPipeError, ConnectionResetError):
        return
    finally:
        process.stdin.close()
        with suppress(BrokenPipeError, ConnectionResetError):
            await process.stdin.wait_closed()


async def _read_stdout(process: asyncio.subprocess.Process) -> bytes:
    if process.stdout is None:
        _fail("EXTRACTION_CHILD_FAILED")
    output = bytearray()
    while chunk := await process.stdout.read(min(64 * 1024, MAX_STDOUT_BYTES + 1 - len(output))):
        output.extend(chunk)
        if len(output) > MAX_STDOUT_BYTES:
            _fail("EXTRACTION_OUTPUT_TOO_LARGE")
    return bytes(output)


async def _discard_stdout(process: asyncio.subprocess.Process) -> None:
    if process.stdout is not None:
        while await process.stdout.read(64 * 1024):
            pass


async def _clean_failed_process(
    process: asyncio.subprocess.Process | None, writer: asyncio.Task[None] | None
) -> None:
    if process is None:
        if writer is not None:
            writer.cancel()
            await asyncio.gather(writer, return_exceptions=True)
        return
    if process.returncode is None:
        with suppress(ProcessLookupError):
            process.kill()
    if writer is not None:
        writer.cancel()
    cleanup = [asyncio.create_task(_discard_stdout(process)), asyncio.create_task(process.wait())]
    if writer is not None:
        cleanup.append(writer)
    await asyncio.gather(*cleanup, return_exceptions=True)


def _child_environment() -> dict[str, str]:
    return {"PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"}


def _validate_result(
    output: bytes, max_chars: int, status: int
) -> tuple[str, list[dict[str, int]], list[str]]:
    try:
        value = json.loads(output)
    except (ValueError, UnicodeDecodeError, RecursionError):
        _fail("EXTRACTION_OUTPUT_INVALID")
    if type(value) is not dict:
        _fail("EXTRACTION_OUTPUT_INVALID")
    if set(value) == {"error"}:
        if status == 0:
            _fail("EXTRACTION_OUTPUT_INVALID")
        code = value["error"]
        _fail(code if type(code) is str and code in SAFE_ERRORS else "EXTRACTION_CHILD_FAILED")
    if status != 0:
        _fail("EXTRACTION_CHILD_FAILED")
    if set(value) != {"limitations", "page_map", "text"}:
        _fail("EXTRACTION_OUTPUT_INVALID")
    text, page_map, limitations = value["text"], value["page_map"], value["limitations"]
    if type(text) is not str or not text.strip() or len(text) > max_chars:
        _fail("EXTRACTION_OUTPUT_INVALID")
    if type(page_map) is not list or not page_map or len(page_map) > MAX_PAGES:
        _fail("EXTRACTION_OUTPUT_INVALID")
    previous_end = 0
    for number, page in enumerate(page_map, 1):
        if (
            type(page) is not dict
            or set(page) != {"end", "page", "start"}
            or type(page.get("page")) is not int
            or page.get("page") != number
            or type(page.get("start")) is not int
            or type(page.get("end")) is not int
            or not previous_end <= page["start"] <= page["end"] <= len(text)
        ):
            _fail("EXTRACTION_OUTPUT_INVALID")
        previous_end = page["end"]
    if page_map[0]["start"] != 0 or page_map[-1]["end"] != len(text):
        _fail("EXTRACTION_OUTPUT_INVALID")
    if (
        type(limitations) is not list
        or len(limitations) > 16
        or any(type(item) is not str or len(item) > 200 for item in limitations)
    ):
        _fail("EXTRACTION_OUTPUT_INVALID")
    return text, page_map, limitations


async def extract_document(
    raw: bytes, media_type: str, max_chars: int
) -> tuple[str, list[dict[str, int]], list[str]]:
    """Extract one document in a fixed, resource-bounded child process."""
    if type(raw) is not bytes or not raw or len(raw) > MAX_RAW_BYTES:
        raise ValueError("EXTRACTION_INPUT_INVALID")
    if type(media_type) is not str or media_type not in SUPPORTED_MEDIA_TYPES:
        raise ValueError("EXTRACTION_MEDIA_TYPE_UNSUPPORTED")
    if type(max_chars) is not int or not 1 <= max_chars <= MAX_CHARS:
        raise ValueError("EXTRACTION_MAX_CHARS_INVALID")
    process: asyncio.subprocess.Process | None = None
    writer: asyncio.Task[None] | None = None
    try:
        async with asyncio.timeout(WALL_SECONDS):
            process = await asyncio.create_subprocess_exec(
                sys.executable,
                MODULE_PATH,
                "--child",
                media_type,
                str(max_chars),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
                env=_child_environment(),
            )
            writer = asyncio.create_task(_write_stdin(process, raw))
            output = await _read_stdout(process)
            await writer
            status = await process.wait()
        return _validate_result(output, max_chars, status)
    except asyncio.CancelledError:
        await _clean_failed_process(process, writer)
        raise
    except TimeoutError:
        await _clean_failed_process(process, writer)
        raise ValueError("EXTRACTION_TIMEOUT") from None
    except _ExtractionError as error:
        await _clean_failed_process(process, writer)
        raise ValueError(str(error)) from None
    except (OSError, ValueError):
        await _clean_failed_process(process, writer)
        raise ValueError("EXTRACTION_CHILD_FAILED") from None


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] != "--child":
        raise SystemExit(2)
    raise SystemExit(_child_main(sys.argv[2], sys.argv[3]))
