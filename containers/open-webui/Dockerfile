FROM ghcr.io/open-webui/open-webui:v0.12.3@sha256:a537bbe1e6b428820f52ed4a029d7fff97062e24d5cf32c365fba36fd0542def

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

RUN grep -Fq 'href="/static/custom.css"' /app/build/index.html \
 && grep -Fq 'src="/static/loader.js"' /app/build/index.html \
 && for selector in \
      assistant-message-profile-image \
      chat-container \
      response-content-container \
      note-content-container \
      message-input-container \
      response-message-model-name \
      markdown-prose \
      cm-editor \
      cm-gutters; do \
      grep -R -Fq "$selector" /app/build/_app/immutable \
        || { printf 'Open WebUI shim selector missing: %s\n' "$selector" >&2; exit 1; }; \
    done

COPY assets/catppuccin-mocha.css /app/build/static/custom.css
COPY assets/loader.js /app/build/static/loader.js
COPY assets/ /app/backend/declarative/assets/
COPY config/ /app/backend/declarative/config/
COPY scripts/reconcile.sh scripts/render-declarations.jq /app/backend/declarative-scripts/
