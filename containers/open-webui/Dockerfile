FROM ghcr.io/open-webui/open-webui:v0.11.2@sha256:77ff490214a4b2699b309aa8d39bf4b42eca05f62d2742ef669ff846fcd10355

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

RUN grep -Fq 'href="/static/custom.css"' /app/build/index.html \
 && grep -Fq 'src="/static/loader.js"' /app/build/index.html

COPY assets/catppuccin-mocha.css /app/build/static/custom.css
COPY assets/loader.js /app/build/static/loader.js
