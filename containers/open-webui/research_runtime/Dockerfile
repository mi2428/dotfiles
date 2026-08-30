FROM ghcr.io/astral-sh/uv:0.12.5@sha256:e85be844203885286c60ffad8a858d48afb6c5a5c237ca0e67f12e74b8f174b1 AS uv

FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/data \
    TMPDIR=/data/tmp \
    XDG_CACHE_HOME=/data/.cache \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    PATH=/app/.venv/bin:$PATH

WORKDIR /app

RUN useradd --create-home --home-dir /data --uid 10001 research \
    && mkdir -p /data/tmp \
    && chown -R 10001:10001 /data

COPY --from=uv /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY research_runtime.py ./

USER 10001:10001

EXPOSE 8000

# A single worker owns the local SQLite connection.
CMD ["uvicorn", "research_runtime:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
