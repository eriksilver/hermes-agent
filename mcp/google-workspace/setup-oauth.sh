#!/usr/bin/env bash
# OAuth refresh-token capture for Atlas's Google Workspace MCP servers.
#
# Run twice — once per account:
#   ./setup-oauth.sh personal quiksilvere@gmail.com
#   ./setup-oauth.sh work     hello@pksprops.com
#
# Requires: workspace-mcp installed locally (pipx install workspace-mcp),
#           GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET exported.
#
# Output: refresh-token JSON at ~/.google_workspace_mcp/credentials/<email>.json,
#         plus a base64 blob you paste into Railway as GOOGLE_CREDS_<LABEL>_B64.
#
# See SETUP.md for the full walkthrough.

set -euo pipefail

LABEL="${1:-}"
EMAIL="${2:-}"

if [[ -z "$LABEL" || -z "$EMAIL" ]]; then
    echo "usage: $0 <personal|work> <google-email>" >&2
    exit 1
fi

if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" || -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "error: export GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET first" >&2
    echo "       (copy from Google Cloud Console → Credentials → your OAuth client)" >&2
    exit 1
fi

if ! command -v workspace-mcp >/dev/null 2>&1; then
    echo "error: workspace-mcp not on PATH. Install with:" >&2
    echo "       pipx install workspace-mcp   # or: uv tool install workspace-mcp" >&2
    exit 1
fi

CREDS_DIR="$HOME/.google_workspace_mcp/credentials"
mkdir -p "$CREDS_DIR"
chmod 700 "$CREDS_DIR"

CRED_FILE="$CREDS_DIR/${EMAIL}.json"

echo
echo "Starting workspace-mcp OAuth flow for: $EMAIL"
echo "Browser will open shortly. Log in as $EMAIL (NOT the other account)."
echo "Approve the requested Gmail + Calendar scopes."
echo

# workspace-mcp's HTTP transport hosts the OAuth consent UI on localhost:8000.
# It auto-opens the browser, walks consent, captures the refresh token,
# and writes it to WORKSPACE_MCP_CREDENTIALS_DIR/<email>.json. We then kill
# the server — we only needed the token-capture side effect.
export USER_GOOGLE_EMAIL="$EMAIL"
export WORKSPACE_MCP_CREDENTIALS_DIR="$CREDS_DIR"
export OAUTHLIB_INSECURE_TRANSPORT=1   # allow http://localhost:8000 redirect

# Run server in background, wait for the cred file to appear, then stop.
workspace-mcp --transport streamable-http --port 8000 --tools gmail calendar &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

echo "Waiting for $CRED_FILE to be written by the consent flow…"
for _ in $(seq 1 120); do
    if [[ -f "$CRED_FILE" ]]; then
        sleep 1   # let the write flush
        break
    fi
    sleep 1
done

if [[ ! -f "$CRED_FILE" ]]; then
    echo "error: timed out waiting for credentials. Did you complete the browser flow?" >&2
    exit 1
fi

chmod 600 "$CRED_FILE"

LABEL_UPPER=$(echo "$LABEL" | tr '[:lower:]' '[:upper:]')
ENV_VAR="GOOGLE_CREDS_${LABEL_UPPER}_B64"
B64=$(base64 < "$CRED_FILE" | tr -d '\n')

echo
echo "✓ Captured $EMAIL refresh token at $CRED_FILE"
echo
echo "── Paste this into Railway (airy-clarity / hermes-agent service) ──"
echo "$ENV_VAR=$B64"
echo "───────────────────────────────────────────────────────────────────"
echo
echo "Filename Railway will write it as: /opt/data/google-workspace-mcp/${LABEL}-creds/${EMAIL}.json"
