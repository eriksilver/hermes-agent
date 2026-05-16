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

COPY docker/SOUL.md                 /opt/hermes/docker/SOUL.md
COPY docker/atlas-config.yaml       /opt/hermes/docker/atlas-config.yaml
COPY docker/seed-memories/USER.md   /opt/hermes/docker/seed-memories/USER.md
COPY docker/seed-memories/MEMORY.md /opt/hermes/docker/seed-memories/MEMORY.md
COPY docker/entrypoint.sh           /opt/hermes/docker/entrypoint.sh
