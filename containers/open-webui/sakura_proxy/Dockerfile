FROM python:3.13-alpine@sha256:540c7d91f98ff6880174c40e99067bf5941eb54d818a7a5e094d188b196a934d

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

WORKDIR /app
COPY sakura_retry_proxy.py .

USER 65534

CMD ["python", "sakura_retry_proxy.py"]
