FROM python:3.14-alpine@sha256:601e99e090cb08c2784a42395487709500bc39930307fe72f3f11a8f3c430762

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
RUN pip install --no-cache-dir ddgs==9.16.0
COPY --chown=65532:65532 searchtool_proxy.py /app/searchtool_proxy.py

USER 65532:65532
EXPOSE 8082
ENTRYPOINT ["python3", "/app/searchtool_proxy.py"]
