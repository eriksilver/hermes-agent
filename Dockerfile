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

# Pinned by digest, not floating :latest — a floating tag is what caused the
# June 7-10 2026 outage (upstream switched to s6-overlay init under our feet
# and the old startCommand boot-looped). This deploy now targets the s6
# layout; bump the digest deliberately, and re-verify boot logs after.
# Digest = :latest as of 2026-06-10 (hermes-agent 0.16.0, s6-overlay 3.2.3.0).
FROM nousresearch/hermes-agent:latest@sha256:33c7741c4de83f6aea9f912b72703c761cff3ffaa51f7486069f29c7afb385aa

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

# Atlas volume seeding (config/memories/cron/GWS creds) as an s6 cont-init
# hook. The 00- prefix makes it run before upstream's 01-hermes-setup —
# see the header comment in the script for why that ordering matters.
# NOTE: docker/entrypoint.sh is retired. Upstream's stage2-hook.sh +
# main-wrapper.sh now own privilege drop, volume chown, .env/SOUL.md
# seeding, auth.json bootstrap, config migration, and CMD routing.
COPY --chmod=0755 docker/cont-init.d/00-atlas-seed /etc/cont-init.d/00-atlas-seed

# The gateway runs as the container's main program (s6-overlay "Architecture
# B": /init → rc.init → main-wrapper.sh routes non-executable first args to
# `hermes <args>`). Baked CMD instead of railway.toml startCommand — Railway's
# startCommand mangles the entrypoint vector (it's what exec'd a bare `-g` in
# the June outage); the image-default path is the one upstream tests.
# `-v` keeps INFO logs on stderr so Railway captures gateway activity.
CMD ["gateway", "run", "-v"]
