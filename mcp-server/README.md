# InkList MCP server

Lets Claude Desktop or Claude Code read and manage your [InkList](../) tasks
over your local Wi-Fi network. This talks to a small HTTP bridge built into
the InkList app itself (`lib/services/mcp_bridge_service.dart`) — there's no
cloud service involved, and it only works while:

- InkList is open on your phone,
- "Enable Local API for Claude" is turned on in InkList's Settings → Claude
  Connector, and
- the computer running Claude and the phone are on the **same Wi-Fi
  network**.

## Setup

1. On your phone, open InkList → Settings → **Claude Connector**, and turn
   on **Enable Local API for Claude**. Two new rows appear:
   - **Address** — something like `http://192.168.1.42:8787`
   - **Token** — a long random string (tap to copy either one)

2. Install this server's dependencies:
   ```sh
   cd mcp-server
   npm install
   ```

3. Add it to your Claude Desktop or Claude Code MCP config, using the IP
   (without `http://` or the port) and token you copied:

   ```json
   {
     "mcpServers": {
       "inklist": {
         "command": "node",
         "args": ["/absolute/path/to/inklist/mcp-server/index.js"],
         "env": {
           "INKLIST_HOST": "192.168.1.42",
           "INKLIST_TOKEN": "the-token-from-settings"
         }
       }
     }
   }
   ```

   `INKLIST_PORT` defaults to `8787` (matches the app) — only set it if you've
   changed that.

4. Restart Claude Desktop / reload Claude Code's MCP servers. Ask it
   something like "what's on my InkList today?" to confirm it's connected.

If your phone's IP changes (common with DHCP), update `INKLIST_HOST` in the
config. If you tap "Regenerate Token" in Settings, update `INKLIST_TOKEN` too
— the old token stops working immediately.

## Tools

| Tool | Does |
|---|---|
| `inklist_list_tasks` | Lists tasks (`scope`: `today` default, `overdue`, or `all`) |
| `inklist_create_task` | Creates a task (title, optional description/dueDate/time/priority/recurrence) |
| `inklist_complete_task` | Marks a task done for a day (idempotent — safe to call twice) |
| `inklist_list_habits` | Lists habits with current streak + today's status |
| `inklist_behavior_snapshot` | The same 14-day completion-pattern summary InkList's own AI features use |

## Security

This opens a network-reachable HTTP endpoint on your phone, gated by the
bearer token above. It's designed to be **LAN-only** — never expose it to the
internet (no port forwarding, no tunneling). It's off by default and only
runs while the InkList app process is alive, not as a persistent background
service.
