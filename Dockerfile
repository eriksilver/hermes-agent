# Atlas-deploy thin image.
# Replaces our source-build (which took ~33 min and hung post-banner on first
# deploy attempt) with a layer on top of the official Hermes image. The
# upstream image is what NousResearch tests and publishes — inherits their
# lazy-deps fixes, Playwright cache, venv layout, all of it.
#
# This image only adds Atlas-specific customizations:
#   - SOUL.md (Atlas persona, replaces default Hermes persona)
#   - atlas-config.yaml (sanitized config: reply_in_thread:false, etc.)
#   - seed-memories/ (USER.md + MEMORY.md seeds for first boot)
#   - entrypoint.sh (patched to seed memories + prefer atlas-config.yaml)
#
# Build time target: ~1-2 min (image pull + 5 COPY layers).

FROM nousresearch/hermes-agent:latest

# Pre-install the platform.slack lazy-deps stack so first gateway boot doesn't
# need network for `lazy_deps.ensure("platform.slack")`. The official image
# leaves slack-bolt off the `[all]` extra (deliberately lazy). On Railway this
# subprocess-pip-install can hang silently after the gateway banner. Baking
# it in turns lazy_deps.ensure() into a no-op.
# Match upstream's venv layout (/opt/hermes/.venv) via uv from /usr/local/bin.
RUN /usr/local/bin/uv pip install --no-cache-dir \
    --python /opt/hermes/.venv/bin/python \
    slack-bolt slack-sdk aiohttp

# workspace-mcp — taylorwilsdon/google_workspace_mcp. Two stdio instances run
# at gateway boot (one per Google account, see atlas-config.yaml). Installed
# into Hermes' venv so the `workspace-mcp` console script is on PATH.
RUN /usr/local/bin/uv pip install --no-cache-dir \
    --python /opt/hermes/.venv/bin/python \
    workspace-mcp

# github-mcp-server (R2.A) — pinned to v1.0.4 to match Erik's local install.
# Provides GitHub source-of-truth tools (list_commits, search_code, etc.).
# Single static binary, ~15 MB. PAT comes from GITHUB_PERSONAL_ACCESS_TOKEN env.
ARG GITHUB_MCP_VERSION=v1.0.4
RUN curl -fsSL "https://github.com/github/github-mcp-server/releases/download/${GITHUB_MCP_VERSION}/github-mcp-server_Linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin github-mcp-server \
    && chmod +x /usr/local/bin/github-mcp-server

# todo-app MCP (R2.B) — vendored copy of custom-to-do-app/mcp-server.js. The
# source of truth lives at ~/AIHub/Dev/custom-to-do-app/ on Erik's Mac; this is
# the deployable mirror. npm install in its own layer so a code-only change to
# mcp-server.js doesn't bust the node_modules cache.
COPY mcp/todo-app/package.json /opt/hermes/mcp/todo-app/package.json
RUN cd /opt/hermes/mcp/todo-app \
    && npm install --omit=dev --no-audit --no-fund \
    && npm cache clean --force
COPY mcp/todo-app/mcp-server.js   /opt/hermes/mcp/todo-app/mcp-server.js
COPY mcp/todo-app/mcp-load-env.js /opt/hermes/mcp/todo-app/mcp-load-env.js

COPY docker/SOUL.md                 /opt/hermes/docker/SOUL.md
COPY docker/atlas-config.yaml       /opt/hermes/docker/atlas-config.yaml
COPY docker/seed-memories/USER.md   /opt/hermes/docker/seed-memories/USER.md
COPY docker/seed-memories/MEMORY.md /opt/hermes/docker/seed-memories/MEMORY.md
COPY docker/seed-cron/jobs.json     /opt/hermes/docker/seed-cron/jobs.json
COPY docker/merge_cron_seed.py      /opt/hermes/docker/merge_cron_seed.py
COPY docker/entrypoint.sh           /opt/hermes/docker/entrypoint.sh
