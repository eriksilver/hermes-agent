# Google Workspace MCP — setup for Atlas

Atlas gets Gmail + Calendar across both Google accounts (`quiksilvere@gmail.com` personal, `hello@pksprops.com` work) via two stdio instances of [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp).

Why two instances: the server's stdio transport is single-user only. The HTTP transport supports multi-account via OAuth 2.1, but stdio matches our existing MCP pattern and gives a security upside — each server can only reach its one account.

## One-time setup (you, on Mac)

### 1. Google Cloud Console — one OAuth client, both accounts as test users

1. https://console.cloud.google.com → new project named `Atlas`.
2. **APIs & Services → Library** → enable **Gmail API** and **Google Calendar API**.
3. **OAuth consent screen**:
   - User type: **External**, publishing status: **Testing**.
   - App name: `Atlas`. Support email: `quiksilvere@gmail.com`.
   - **Scopes**: add (search and tick):
     - `https://www.googleapis.com/auth/gmail.readonly`
     - `https://www.googleapis.com/auth/gmail.send`
     - `https://www.googleapis.com/auth/gmail.compose`
     - `https://www.googleapis.com/auth/gmail.modify`
     - `https://www.googleapis.com/auth/calendar`
   - **Test users**: add both `quiksilvere@gmail.com` and `hello@pksprops.com`.
4. **Credentials → Create OAuth client ID → Web application**:
   - Name: `Atlas workspace-mcp`
   - **Authorised redirect URIs**: `http://localhost:8000/oauth2callback` (the default workspace-mcp listens on during local consent).
   - Click Create. Copy the **Client ID** and **Client secret**.

### 2. Capture refresh tokens locally — run the helper twice

```bash
cd ~/AIHub/Dev/hermes-deploy/mcp/google-workspace
export GOOGLE_OAUTH_CLIENT_ID=<client_id_from_console>
export GOOGLE_OAUTH_CLIENT_SECRET=<client_secret_from_console>

# Personal — opens browser, log in as quiksilvere@gmail.com, approve scopes
./setup-oauth.sh personal quiksilvere@gmail.com

# Work — opens browser, log in as hello@pksprops.com, approve scopes
./setup-oauth.sh work hello@pksprops.com
```

The script writes:
- `~/.google_workspace_mcp/credentials/quiksilvere@gmail.com.json`
- `~/.google_workspace_mcp/credentials/hello@pksprops.com.json`

…and then echoes two `GOOGLE_CREDS_*_B64` lines you'll paste into Railway in step 3.

### 3. Railway env vars — `airy-clarity / hermes-agent` service

Add these via the Railway dashboard:

| Variable | Value |
|---|---|
| `GOOGLE_OAUTH_CLIENT_ID` | from step 1.4 |
| `GOOGLE_OAUTH_CLIENT_SECRET` | from step 1.4 |
| `GOOGLE_CREDS_PERSONAL_B64` | from step 2 (base64 of personal creds JSON) |
| `GOOGLE_CREDS_WORK_B64` | from step 2 (base64 of work creds JSON) |
| `HERMES_FORCE_RESEED_MEMORIES` | `1` (one-shot — clear after the deploy lands) |

### 4. Deploy

```bash
cd ~/AIHub/Dev/hermes-deploy
git push origin atlas-deploy
```

Railway auto-redeploys (~2 min — image pull + thin layer COPY).

### 5. Clear the reseed flag

After the deploy lands and you've confirmed Atlas picked up the new MEMORY.md addendum, unset `HERMES_FORCE_RESEED_MEMORIES` in Railway so future deploys preserve Atlas's runtime memory writes.

### 6. Validate via Slack DM — the five done-criteria

1. "What's on my calendar today?" → returns events from both accounts, labeled.
2. "What's on my work calendar tomorrow?" → only `hello@pksprops.com`.
3. "Did I get anything from Bascom today?" → searches both inboxes.
4. "Draft a reply to <thread> saying I'll be there Tuesday at 10" → shows draft, awaits explicit approval before send.
5. Cron-driven morning brief shows a "📧 New since yesterday" line counting both accounts.

When all five work, append the phase-complete entry to `decisions.md`.

## Token rotation

Google refresh tokens for desktop/web apps don't expire unless explicitly revoked or unused for ~6 months. If Atlas ever loses Workspace access:

1. Re-run `./setup-oauth.sh <label> <email>` on Mac.
2. Re-base64-encode the new creds JSON.
3. Update the matching `GOOGLE_CREDS_*_B64` env var in Railway.
4. Trigger a redeploy.

The cred files in `/opt/data/google-workspace-mcp/<label>-creds/` are write-once at boot — they only get refreshed when the matching env var changes AND the volume copy is older than the env value (see `entrypoint.sh`).

## What Atlas can and cannot do

**Enabled (9 tools per namespace × 2 namespaces):**

Gmail — `search_gmail_messages`, `get_gmail_message_content`, `get_gmail_thread_content`, `draft_gmail_message`, `send_gmail_message`

Calendar — `list_calendars`, `get_events`, `manage_event`, `query_freebusy`

**Deliberately excluded** (re-enable later via `tools.include` in `atlas-config.yaml`):

- Gmail labels & filters (`manage_gmail_label`, `manage_gmail_filter`, `list_gmail_labels`, `list_gmail_filters`, `modify_gmail_message_labels`, `batch_modify_gmail_message_labels`)
- Batch read tools (`get_gmail_messages_content_batch`, `get_gmail_threads_content_batch`) — Atlas can call serial
- Calendar admin (`create_calendar`, `manage_out_of_office`, `manage_focus_time`)
- All other services (Drive, Docs, Sheets, Slides, Forms, Chat, Tasks, Contacts, Search, Apps Script) — not loaded, scopes not requested

## Security notes

- Refresh tokens never leave Railway except as base64 env-var values you paste yourself.
- They're never committed to git (the helper writes outside the repo; `.gitignore` ignores `credentials/` defensively).
- The OAuth app is in **Testing** mode with only your two emails as test users — no other Google account can grant Atlas access.
- `Atlas` Slack app's `SLACK_ALLOWED_USERS` already restricts who can trigger Atlas to your two Slack accounts.
- `send_gmail_message` is enabled but the memory addendum tells Atlas to always draft + ask for confirmation before sending. There is no programmatic enforcement of this — only the prompt-level guidance.
