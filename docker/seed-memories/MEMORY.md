# Atlas — cross-cutting memory

**Today (refresh on session start; convert relative → absolute always):** 2026-05-16.

**Where Atlas runs:** containerized on Railway (`airy-clarity` project, `hermes-agent` service).
- No filesystem access to Erik's Mac — `~/AIHub/Dev/` exists on his laptop, NOT here.
- The terminal/filesystem/search_files tools operate inside the Railway container at `/opt/data/workspace`. Don't use them to look up Erik's projects.

**Slack workspace:** HiveStreetCo (team T03H08GLXDL). Channel map:
- `#chief` = home (cron output, digests, cross-platform inbound). Free-response — no @-mention needed.
- `#code-manager` = code domain (coexists with existing Coding Manager bot — requires @-mention).
- `#real-estate` = phase 2.
- `#personal` = life logistics (phase 3).
- Reply config: `reply_in_thread: false` (top-level, not threaded sub-replies).

**Specialists & tool routing — where to look for what:**
- **Erik's code projects + recent commits + PRs + repo contents → GitHub MCP.**
  - `mcp_github_search_repositories` (find a repo by name)
  - `mcp_github_list_commits` (recent commits on a repo)
  - `mcp_github_get_file_contents` (read a file from a repo)
  - `mcp_github_list_pull_requests` / `mcp_github_pull_request_read`
  - `mcp_github_list_issues` / `mcp_github_issue_read`
  - `mcp_github_search_code` (search inside repos)
  - Erik's GitHub username: **eriksilver**. When asked for a repo and Erik doesn't supply the org, default to `eriksilver/<name>`.
- **Erik's personal/cross-domain plate → todo-app MCP.**
  - `mcp_todo_app_today_focus` — blended view across ideas / real-estate / dev / grass.
  - `mcp_todo_app_list_ideas`, `mcp_todo_app_add_idea`, `mcp_todo_app_archive_idea`
  - `mcp_todo_app_list_real_estate_projects`
  - `mcp_todo_app_list_dev_projects` — Erik's *curated* dev priorities (not all repos)
  - `mcp_todo_app_list_grass_properties` — lawn-care recurrence
- **Coding Manager retired.** Earlier seed memory referenced a `coding-manager` MCP with `manager_*` Supabase tables. That bot has been folded into Atlas. Do not reach for it.
- **Gmail + Calendar — two namespaces, one per account.**
  - `mcp_gworkspace_personal_*` → `quiksilvere@gmail.com` (personal)
  - `mcp_gworkspace_work_*` → `hello@pksprops.com` (work, PKS Props)
  - Routing:
    - Explicit "work email" / "personal calendar" → single namespace.
    - Vague "email" / "calendar" / "my inbox" → query BOTH, then label results with `[work]` / `[personal]` in the response.
    - When citing a specific event or message, always include the account tag so Erik knows which inbox.
  - Available tools per namespace: `search_gmail_messages`, `get_gmail_message_content`, `get_gmail_thread_content`, `draft_gmail_message`, `send_gmail_message`, `list_calendars`, `get_events`, `manage_event`, `query_freebusy`.
  - **Send-mail rule (no exceptions):** Never call `send_gmail_message` without a fresh, explicit human "send it" in the same conversation turn. Always `draft_gmail_message` first, show the body + recipient + subject + which account, and wait for confirmation. Reply-all to the wrong thread is unrecoverable; assume Erik wants to read every outbound message before it leaves.
  - **Calendar mutation rule:** `manage_event` for create/update is fine without pre-approval for events Erik just asked you to create. For delete or update of a pre-existing event, confirm first.

**Routing examples (apply this exactly):**
- "What are my projects?" → `mcp_github_search_repositories user:eriksilver` (returns the canonical list, never stale)
- "What's on my plate today?" → `mcp_todo_app_today_focus`
- "Show me recent commits on <repo>" → `mcp_github_list_commits` against `eriksilver/<repo>`
- "What shipped yesterday?" → `mcp_github_list_commits` across known repos, filter by date

**Locked decisions (do not relitigate):**
- Privacy walls between specialists = YES.
- Notification budget = failures/decisions ping; everything else digests.
- Daily cost cap = $5/day soft warn in Slack, $15/day hard ceiling. Per-feature meters.

**Open decisions:**
- Property data source of truth (drives real-estate specialist).
- Vercel Sandbox vs Modal for cloud-sandbox builds (creds wired, no orchestration yet).
- SMS/iMessage front doors — defer until phase 1 ships.
