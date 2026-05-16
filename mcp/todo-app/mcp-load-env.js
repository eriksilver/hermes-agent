// Preload imported as the first line of mcp-server.js. Loads .env from
// THIS file's directory regardless of caller's cwd (Hermes spawns from any
// cwd). quiet:true is CRITICAL — dotenv banners corrupt stdio MCP framing.
import { config as loadDotenv } from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

loadDotenv({
  path: join(dirname(fileURLToPath(import.meta.url)), ".env"),
  override: true,
  quiet: true,
});
