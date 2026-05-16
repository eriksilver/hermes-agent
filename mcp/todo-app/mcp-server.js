// MCP server exposing the personal productivity tables to Atlas.
// Read-heavy. Idea capture is the one mutation; everything else read-only.
// Different domain from coding-manager (different specialist, eventually).
//
// Transport: stdio. Hermes spawns this as a subprocess.
// IMPORTANT: stdout is the MCP protocol channel. All human logging → stderr.

import "./mcp-load-env.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY,
);

const server = new McpServer({
  name: "todo-app",
  version: "0.1.0",
});

const asText = (value) => ({
  content: [{ type: "text", text: JSON.stringify(value, null, 2) }],
});

const throwIf = ({ data, error }) => {
  if (error) throw error;
  return data;
};

// ── Ideas ─────────────────────────────────────────────────────────────────────

server.registerTool(
  "list_ideas",
  {
    title: "List ideas",
    description:
      "Return ideas from the inbox. Defaults to active (not-archived), newest first.",
    inputSchema: {
      limit: z.number().int().positive().max(200).default(50).optional(),
      include_archived: z.boolean().default(false).optional(),
    },
  },
  async ({ limit = 50, include_archived = false }) => {
    let q = supabase
      .from("ideas")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(limit);
    if (!include_archived) q = q.eq("archived", false);
    return asText(throwIf(await q));
  },
);

server.registerTool(
  "add_idea",
  {
    title: "Capture an idea",
    description:
      "Append a new idea to the inbox. Use this when Erik mentions something he wants to remember — a future project, a small task, a note. NOT for active builds (use coding-manager.enqueue_build for code work). Source defaults to 'atlas'.",
    inputSchema: {
      text: z.string().describe("The idea, in one sentence"),
      source: z
        .string()
        .describe(
          "Where the idea came from. Default 'atlas'. Use 'slack' for Slack-originated.",
        )
        .default("atlas")
        .optional(),
    },
  },
  async ({ text, source = "atlas" }) =>
    asText(
      throwIf(
        await supabase
          .from("ideas")
          .insert({ text, source })
          .select()
          .single(),
      ),
    ),
);

server.registerTool(
  "archive_idea",
  {
    title: "Archive an idea",
    description:
      "Mark an idea as archived (with archived_at timestamp). Soft delete — auto-pruned after 30 days.",
    inputSchema: {
      id: z.string().uuid().describe("ideas.id"),
    },
  },
  async ({ id }) =>
    asText(
      throwIf(
        await supabase
          .from("ideas")
          .update({ archived: true, archived_at: new Date().toISOString() })
          .eq("id", id)
          .select()
          .single(),
      ),
    ),
);

// ── Real Estate Projects ──────────────────────────────────────────────────────

server.registerTool(
  "list_real_estate_projects",
  {
    title: "List real estate projects",
    description:
      "Return real estate projects (flips, rentals, etc.). Defaults to active. Includes address, type, status, next_date, phases.",
    inputSchema: {
      status: z
        .enum(["active", "pending", "closed", "all"])
        .describe("Filter by status. 'all' returns everything.")
        .default("active")
        .optional(),
    },
  },
  async ({ status = "active" }) => {
    let q = supabase
      .from("projects")
      .select("*")
      .order("next_date", { ascending: true, nullsFirst: false });
    if (status !== "all") q = q.eq("status", status);
    return asText(throwIf(await q));
  },
);

// ── Dev Projects (todo-app's own, separate from manager_projects) ─────────────

server.registerTool(
  "list_dev_projects",
  {
    title: "List dev projects (todo-app)",
    description:
      "Return dev projects from the todo app's own table (NOT the same as manager_projects in the coding-manager MCP). These are Erik's curated dev priorities with subtasks. Defaults to non-archived.",
    inputSchema: {
      status: z
        .string()
        .describe("Filter by status (e.g. 'active', 'backlog'). Omit for all.")
        .optional(),
      include_archived: z.boolean().default(false).optional(),
    },
  },
  async ({ status, include_archived = false }) => {
    let q = supabase
      .from("dev_projects")
      .select("*")
      .order("sort_order", { ascending: true });
    if (status) q = q.eq("status", status);
    if (!include_archived) q = q.eq("archived", false);
    return asText(throwIf(await q));
  },
);

// ── Grass Properties (lawn-care recurrence) ───────────────────────────────────

server.registerTool(
  "list_grass_properties",
  {
    title: "List grass properties + due flag",
    description:
      "Return lawn-care properties with a computed 'due_now' boolean (last_cut + interval_days <= today). Useful for 'what needs cutting this week'.",
    inputSchema: { include_archived: z.boolean().default(false).optional() },
  },
  async ({ include_archived = false }) => {
    let q = supabase
      .from("grass_properties")
      .select("*")
      .order("sort_order", { ascending: true });
    if (!include_archived) q = q.eq("archived", false);
    const rows = throwIf(await q);
    const today = new Date();
    const annotated = rows.map((r) => {
      let due_now = !r.last_cut;
      if (r.last_cut) {
        const last = new Date(r.last_cut);
        const dueDate = new Date(last);
        dueDate.setDate(dueDate.getDate() + (r.interval_days || 14));
        due_now = dueDate <= today;
      }
      return { ...r, due_now };
    });
    return asText(annotated);
  },
);

// ── Daily focus synthesis ─────────────────────────────────────────────────────

server.registerTool(
  "today_focus",
  {
    title: "What's on my plate today",
    description:
      "Blended view across all domains: recent ideas, active real-estate projects with upcoming next_date, active dev projects, and grass properties due now. Use this for 'what should I focus on today' questions.",
    inputSchema: { idea_limit: z.number().int().positive().max(50).default(10).optional() },
  },
  async ({ idea_limit = 10 }) => {
    const [ideas, realEstate, dev, grass] = await Promise.all([
      supabase
        .from("ideas")
        .select("id, text, source, created_at")
        .eq("archived", false)
        .order("created_at", { ascending: false })
        .limit(idea_limit),
      supabase
        .from("projects")
        .select("id, address, type, status, next_date")
        .eq("status", "active")
        .order("next_date", { ascending: true, nullsFirst: false }),
      supabase
        .from("dev_projects")
        .select("id, name, status, subtasks, sort_order")
        .eq("archived", false)
        .neq("status", "backlog")
        .order("sort_order", { ascending: true }),
      supabase
        .from("grass_properties")
        .select("id, address, interval_days, last_cut")
        .eq("archived", false)
        .order("sort_order", { ascending: true }),
    ]);
    const today = new Date();
    const grassDue = (grass.data || []).filter((g) => {
      if (!g.last_cut) return true;
      const next = new Date(g.last_cut);
      next.setDate(next.getDate() + (g.interval_days || 14));
      return next <= today;
    });
    return asText({
      recent_ideas: ideas.data || [],
      real_estate_active: realEstate.data || [],
      dev_active: dev.data || [],
      grass_due_now: grassDue,
    });
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("[todo-app-mcp] ready (stdio)");
