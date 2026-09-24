FROM python:3.14-alpine@sha256:05b2b8b732ecd268fee8727a369f936f022d1321b59befd13c30ede22769dcdc

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

WORKDIR /app
COPY sakura_retry_proxy.py .

USER 65534

CMD ["python", "sakura_retry_proxy.py"]
