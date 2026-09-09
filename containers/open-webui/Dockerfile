# syntax=docker/dockerfile:1

FROM ghcr.io/open-webui/open-webui:v0.11.3@sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175 AS patched-source

ADD --checksum=sha256:1842400661ba42eaa3e20d27dbae41468f3db0a664a4bfa0c73c796325ae40e9 \
    https://github.com/open-webui/open-webui/archive/2a960a59fe1dbbd35282f0556b3666d81102e781.tar.gz \
    /tmp/open-webui.tar.gz
COPY patches/apply_deep_research_integration.py /tmp/apply_deep_research_integration.py
RUN mkdir /tmp/open-webui-source \
 && tar -xzf /tmp/open-webui.tar.gz --strip-components=1 -C /tmp/open-webui-source \
 && sha256sum /tmp/open-webui-source/backend/open_webui/main.py | cut -d' ' -f1 > /tmp/main.py.sha256 \
 && sha256sum /tmp/open-webui-source/backend/open_webui/utils/middleware.py | cut -d' ' -f1 > /tmp/middleware.py.sha256 \
 && python /tmp/apply_deep_research_integration.py --root /tmp/open-webui-source \
 && python -m py_compile \
      /tmp/open-webui-source/backend/open_webui/main.py \
      /tmp/open-webui-source/backend/open_webui/utils/middleware.py

FROM node:22-alpine3.20@sha256:2289fb1fba0f4633b08ec47b94a89c7e20b829fc5679f9b7b298eaa2f1ed8b7e AS frontend

WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=4096
COPY --from=patched-source /tmp/open-webui-source/package.json /tmp/open-webui-source/package-lock.json ./
RUN npm ci --force
COPY --from=patched-source /tmp/open-webui-source/ ./
RUN node -e 'const fs = require("node:fs"); const path = "vite.config.ts"; const source = fs.readFileSync(path, "utf8"); const from = "\t\tsourcemap: true"; const count = source.split(from).length - 1; if (count !== 1) throw new Error(`vite sourcemap guard failed: expected 1 match, got ${count}`); fs.writeFileSync(path, source.replace(from, "\t\tsourcemap: false"));'
ENV APP_BUILD_HASH=2a960a59fe1dbbd35282f0556b3666d81102e781
RUN npm run build

FROM ghcr.io/open-webui/open-webui:v0.11.3@sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

COPY --from=patched-source /tmp/main.py.sha256 /tmp/middleware.py.sha256 /tmp/
RUN test "$(sha256sum /app/backend/open_webui/main.py | cut -d' ' -f1)" = "$(cat /tmp/main.py.sha256)" \
 && test "$(sha256sum /app/backend/open_webui/utils/middleware.py | cut -d' ' -f1)" = "$(cat /tmp/middleware.py.sha256)" \
 && rm /tmp/main.py.sha256 /tmp/middleware.py.sha256
COPY --from=patched-source /tmp/open-webui-source/backend/open_webui/main.py /app/backend/open_webui/main.py
COPY --from=patched-source /tmp/open-webui-source/backend/open_webui/utils/middleware.py /app/backend/open_webui/utils/middleware.py
COPY patches/deep_research_integration.py /app/backend/open_webui/utils/deep_research_integration.py
RUN grep -Fq 'managed_deep_research = await is_managed_deep_research_model' /app/backend/open_webui/main.py \
 && grep -Fq 'if is_trusted_deep_research(metadata):' /app/backend/open_webui/utils/middleware.py \
 && python -m py_compile \
      /app/backend/open_webui/main.py \
      /app/backend/open_webui/utils/middleware.py \
      /app/backend/open_webui/utils/deep_research_integration.py

COPY --from=frontend /app/build /app/build
RUN grep -Fq 'href="/static/custom.css"' /app/build/index.html \
 && grep -Fq 'src="/static/loader.js"' /app/build/index.html

COPY assets/catppuccin-mocha.css /app/build/static/custom.css
COPY assets/loader.js /app/build/static/loader.js
