#!/bin/bash
# Docker/Podman entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

# --- Privilege dropping via gosu ---
# When started as root (the default for Docker, or fakeroot in rootless Podman),
# optionally remap the hermes user/group to match host-side ownership, fix volume
# permissions, then re-exec as hermes.
if [ "$(id -u)" = "0" ]; then
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi

    if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to $HERMES_GID"
        # -o allows non-unique GID (e.g. macOS GID 20 "staff" may already exist
        # as "dialout" in the Debian-based container image)
        groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
    fi

    # Fix ownership of the data volume. When HERMES_UID remaps the hermes user,
    # files created by previous runs (under the old UID) become inaccessible.
    # Always chown -R when UID was remapped; otherwise only if top-level is wrong.
    actual_hermes_uid=$(id -u hermes)
    needs_chown=false
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "10000" ]; then
        needs_chown=true
    elif [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null)" != "$actual_hermes_uid" ]; then
        needs_chown=true
    fi
    if [ "$needs_chown" = true ]; then
        echo "Fixing ownership of $HERMES_HOME to hermes ($actual_hermes_uid)"
        # In rootless Podman the container's "root" is mapped to an unprivileged
        # host UID — chown will fail.  That's fine: the volume is already owned
        # by the mapped user on the host side.
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "Warning: chown failed (rootless container?) — continuing anyway"
        # The .venv must also be re-chowned when UID is remapped, otherwise
        # lazy_deps.py cannot install platform packages (discord.py, etc.).
        chown -R hermes:hermes "$INSTALL_DIR/.venv" 2>/dev/null || \
            echo "Warning: chown .venv failed (rootless container?) — continuing anyway"
    fi

    # Ensure config.yaml is readable by the hermes runtime user even if it was
    # edited on the host after initial ownership setup. Must run here (as root)
    # rather than after the gosu drop, otherwise a non-root caller like
    # `docker run -u $(id -u):$(id -g)` hits "Operation not permitted" (#15865).
    if [ -f "$HERMES_HOME/config.yaml" ]; then
        chown hermes:hermes "$HERMES_HOME/config.yaml" 2>/dev/null || true
        chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
    fi

    echo "Dropping root privileges"
    exec gosu hermes "$0" "$@"
fi

# --- Running as hermes from here ---
source "${INSTALL_DIR}/.venv/bin/activate"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_hermes_dir().
# The "home/" subdirectory is a per-profile HOME for subprocesses (git,
# ssh, gh, npm …).  Without it those tools write to /root which is
# ephemeral and shared across profiles.  See issue #4426.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

# .env
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# config.yaml — on atlas-deploy we treat the seed as authoritative on every
# boot (IaC: edit atlas-config.yaml, push, redeploy). Any in-container edits
# are erased by the next deploy. The non-atlas fallback (cli-config.yaml.example)
# stays write-once so an upstream-image run keeps the original behaviour.
if [ -f "$INSTALL_DIR/docker/atlas-config.yaml" ]; then
    cp "$INSTALL_DIR/docker/atlas-config.yaml" "$HERMES_HOME/config.yaml"
elif [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Atlas seed memories — default write-once so Hermes' runtime memory writes
# (auto-appends to USER.md / MEMORY.md as Erik chats) are preserved across
# deploys. Set HERMES_FORCE_RESEED_MEMORIES=1 in Railway env for a single
# deploy when the seed needs to replace the volume copy (e.g. a substantive
# rewrite of MEMORY.md), then clear the var after the deploy.
if [ -d "$INSTALL_DIR/docker/seed-memories" ]; then
    mkdir -p "$HERMES_HOME/memories"
    for f in "$INSTALL_DIR/docker/seed-memories"/*.md; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        if [ ! -f "$HERMES_HOME/memories/$name" ] \
           || [ "${HERMES_FORCE_RESEED_MEMORIES:-0}" = "1" ]; then
            cp "$f" "$HERMES_HOME/memories/$name"
        fi
    done
fi

# Atlas seed cron jobs — same pattern as memories. Hermes mutates jobs.json
# on every run (last_run_at, next_run_at, repeat.completed), so write-once
# protects that runtime state. HERMES_FORCE_RESEED_CRON=1 forces a one-shot
# replace when the prompt or schedule needs to change.
if [ -d "$INSTALL_DIR/docker/seed-cron" ]; then
    mkdir -p "$HERMES_HOME/cron"
    for f in "$INSTALL_DIR/docker/seed-cron"/*.json; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        if [ ! -f "$HERMES_HOME/cron/$name" ] \
           || [ "${HERMES_FORCE_RESEED_CRON:-0}" = "1" ]; then
            cp "$f" "$HERMES_HOME/cron/$name"
        fi
    done
fi

# Google Workspace MCP credentials — seed per-account refresh tokens from
# Railway env vars on first boot. Each GOOGLE_CREDS_<LABEL>_B64 is the
# base64 of the JSON file workspace-mcp wrote during local OAuth consent
# (see mcp/google-workspace/SETUP.md).
#
# Files are write-once: a cred file on the volume is preserved across
# deploys so workspace-mcp can rotate its access token in place. If you
# need to force a re-seed (e.g. after re-running OAuth consent on the Mac
# to get a new refresh token), bump GOOGLE_CREDS_RESEED in Railway to any
# truthy value for one deploy, then clear it.
gws_seed() {
    local label="$1" email="$2" b64="$3"
    local dir="$HERMES_HOME/google-workspace-mcp/${label}-creds"
    local file="$dir/${email}.json"
    if [ -z "$b64" ]; then
        return
    fi
    mkdir -p "$dir"
    chmod 700 "$dir"
    if [ ! -f "$file" ] || [ "${GOOGLE_CREDS_RESEED:-0}" = "1" ]; then
        echo "Seeding google-workspace-mcp creds: $file"
        printf '%s' "$b64" | base64 -d > "$file"
        chmod 600 "$file"
    fi
}
gws_seed personal "quiksilvere@gmail.com" "${GOOGLE_CREDS_PERSONAL_B64:-}"
gws_seed work     "hello@pksprops.com"    "${GOOGLE_CREDS_WORK_B64:-}"

# auth.json: bootstrap from env on first boot only.  Used by orchestrators
# (e.g. provisioning a Hermes VPS from an account-management service) that
# need to seed the OAuth refresh credential non-interactively, instead of
# walking the user through `hermes setup` + the device-flow login dance.
# Subsequent token rotations write back to the same file, which lives on a
# persistent volume — so this env var is consumed exactly once at first
# boot.  The `[ ! -f ... ]` guard is critical: without it, a container
# restart would clobber a rotated refresh token with the now-stale value
# the orchestrator originally seeded.
if [ ! -f "$HERMES_HOME/auth.json" ] && [ -n "$HERMES_AUTH_JSON_BOOTSTRAP" ]; then
    printf '%s' "$HERMES_AUTH_JSON_BOOTSTRAP" > "$HERMES_HOME/auth.json"
    chmod 600 "$HERMES_HOME/auth.json"
fi

# Sync bundled skills (manifest-based so user edits are preserved)
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# Optionally start `hermes dashboard` as a side-process.
#
# Toggled by HERMES_DASHBOARD=1 (also accepts "true"/"yes", case-insensitive).
# Host/port/TUI can be overridden via:
#   HERMES_DASHBOARD_HOST  (default 0.0.0.0 — exposed outside the container)
#   HERMES_DASHBOARD_PORT  (default 9119, matches `hermes dashboard` default)
#   HERMES_DASHBOARD_TUI   (already honored by `hermes dashboard` itself)
#
# The dashboard is a long-lived server.  We background it *before* the final
# `exec hermes "$@"` so the user's chosen foreground command (chat, gateway,
# sleep infinity, …) remains PID-of-interest for the container runtime.  When
# the container stops the whole process tree is torn down, so no explicit
# cleanup is needed.
case "${HERMES_DASHBOARD:-}" in
    1|true|TRUE|True|yes|YES|Yes)
        dash_host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
        dash_port="${HERMES_DASHBOARD_PORT:-9119}"
        dash_args=(--host "$dash_host" --port "$dash_port" --no-open)
        # Binding to anything other than localhost requires --insecure — the
        # dashboard refuses otherwise because it exposes API keys.  Inside a
        # container this is the expected deployment (host reaches it via
        # published port), so opt in automatically.
        if [ "$dash_host" != "127.0.0.1" ] && [ "$dash_host" != "localhost" ]; then
            dash_args+=(--insecure)
        fi
        echo "Starting hermes dashboard on ${dash_host}:${dash_port} (background)"
        # Prefix dashboard output so it's distinguishable from the main
        # process in `docker logs`.  stdbuf keeps the pipe line-buffered.
        (
            stdbuf -oL -eL hermes dashboard "${dash_args[@]}" 2>&1 \
                | sed -u 's/^/[dashboard] /'
        ) &
        ;;
esac

# Final exec: two supported invocation patterns.
#
#   docker run <image>                 -> exec `hermes` with no args (legacy default)
#   docker run <image> chat -q "..."   -> exec `hermes chat -q "..."` (legacy wrap)
#   docker run <image> sleep infinity  -> exec `sleep infinity` directly
#   docker run <image> bash            -> exec `bash` directly
#
# If the first positional arg resolves to an executable on PATH, we assume the
# caller wants to run it directly (needed by the launcher which runs long-lived
# `sleep infinity` sandbox containers — see tools/environments/docker.py).
# Otherwise we treat the args as a hermes subcommand and wrap with `hermes`,
# preserving the documented `docker run <image> <subcommand>` behavior.
if [ $# -gt 0 ] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi

# VERIFICATION MODE — temporarily dropped `exec` so the shell can capture
# hermes's exit code and log it. We're diagnosing "Deploy Crashed!" emails
# that fire every redeploy: the new container boots fine but Railway sees
# the displaced container's gateway exiting non-zero on SIGTERM. This
# logs the actual code so we know whether to (a) fix Hermes shutdown,
# (b) trap and translate it in the entrypoint, or (c) silence emails.
# Restore `exec hermes "$@"` once we have the data.
set +e
hermes "$@"
EXIT_CODE=$?
echo "[entrypoint] hermes exited code=$EXIT_CODE" >&2
exit "$EXIT_CODE"
