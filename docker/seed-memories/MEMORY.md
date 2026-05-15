# Atlas — cross-cutting memory

**Today (refresh on session start; convert relative → absolute always):** 2026-05-15.

**Filesystem boundary:** `~/AIHub/` is Atlas's read scope.
- `~/AIHub/Dev/` — code projects (11 currently)
- `~/AIHub/Inbox/` — scratchpad / file-this-later
- Runtime lives at `~/.hermes/` (outside boundary, by design)
- Migration to this layout: completed 2026-05-15

**Slack workspace:** HiveStreetCo (team T03H08GLXDL). Channel map:
- `#chief` = home (cron output, digests, cross-platform inbound)
- `#code-manager` = code domain (coexists with existing Coding Manager bot)
- `#real-estate` = phase 2
- `#personal` = life logistics
- Reply config: `reply_in_thread: false` (top-level, not threaded sub-replies)

**Specialists:**
- Code → MCP server `coding-manager` (Supabase `manager_*` tables) for **operational state**: build queue, recent commits, yesterday's standup, scheduled jobs. **NOT for "what are my projects"** — Erik prefers `~/AIHub/Dev/` filesystem listing (auto-discovered, never stale). Coding Manager's `manager_projects` table is a manually-curated subset of what's on disk.
- Real-estate, personal → phase 2/3, not built.

**Locked decisions (do not relitigate):**
- Privacy walls between specialists = YES.
- Notification budget = failures/decisions ping; everything else digests.
- Daily cost cap = $5/day soft warn in Slack, $15/day hard ceiling. Per-feature meters.

**Services inventory:** `~/AIHub/services.md` (read on demand — what runs where, Railway/Supabase/GitHub/etc.).

**Standing references:**
- Scraper Suite handbook: `~/AIHub/Dev/scraper-suite/docs/handoff/working-with-claude.md`

**Open decisions:**
- Property data source of truth (drives real-estate specialist).
- Vercel Sandbox vs Modal for cloud-sandbox builds.
- SMS/iMessage front doors — defer until phase 1 ships.
