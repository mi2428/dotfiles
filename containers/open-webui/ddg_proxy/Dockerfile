FROM python:3.14-alpine@sha256:05b2b8b732ecd268fee8727a369f936f022d1321b59befd13c30ede22769dcdc

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

RUN pip install --no-cache-dir primp==2.0.0

WORKDIR /app
COPY ddg_proxy.py .

USER 65534

CMD ["python", "ddg_proxy.py"]
