FROM ghcr.io/open-webui/open-webui:v0.11.3@sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

RUN grep -Fq 'href="/static/custom.css"' /app/build/index.html \
 && grep -Fq 'src="/static/loader.js"' /app/build/index.html

COPY patches/apply_direct_tool_output.py /tmp/apply_direct_tool_output.py
RUN python /tmp/apply_direct_tool_output.py \
 && grep -Fq 'dotfiles: trusted external tool direct output' \
      /app/backend/open_webui/utils/middleware.py \
 && rm /tmp/apply_direct_tool_output.py

COPY assets/catppuccin-mocha.css /app/build/static/custom.css
COPY assets/loader.js /app/build/static/loader.js
