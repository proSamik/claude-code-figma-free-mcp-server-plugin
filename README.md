# Claude Code Figma — free MCP server + plugin

Let **Claude Code, Codex, Cursor or any MCP client** read and edit your real Figma files: create and
restyle frames, change text, rename and move layers, and **bulk-export hundreds of frames to disk**.
No Figma API plan or paid seat is needed; it drives the Figma desktop app through a local plugin.

It also runs **24/7 on a headless Linux server** (no monitor, survives reboots), so cloud agents and
bots can work in Figma while your own computer is off.

```
AI agent ←(stdio)→ MCP server ←(WebSocket)→ relay :3055 ←(WebSocket)→ Figma plugin (in Figma desktop)
```

This is a fork of [grab/cursor-talk-to-figma-mcp](https://github.com/grab/cursor-talk-to-figma-mcp)
(Talk to Figma MCP by Sonny Lazuardi and contributors), MIT licensed.

## How it differs from cursor-talk-to-figma-mcp

| | cursor-talk-to-figma-mcp | This fork |
|---|---|---|
| Main target | Cursor | Claude Code, Codex, Cursor, any MCP client |
| Install | `bunx cursor-talk-to-figma-mcp@latest` (npm) | Run from this checkout (`bun run dist/server.js`); not on npm |
| Bulk export | One `export_node_as_image` call per node, base64 back into the agent's context | `start_bulk_export` / `get_bulk_export_status` / `cancel_bulk_export`: background job in the plugin, 3 at a time, files written to disk, progress + ETA, failures skipped. Measured ~1.1 s per 1280×720 frame on a 12-frame run (so 323 frames ≈ 6 min estimated, vs ~56 min before) |
| Multi-select across pages | `set_selections` fails for nodes on another page | `select_nodes` switches to the right page and reports missing IDs |
| Pages | `get_document_info` shows the current page only | `get_pages`, `set_current_page`; `get_document_info` lists every page |
| Relay security | Listens on all interfaces, accepts any web page | Listens on `127.0.0.1` by default (`HOST` to change), rejects untrusted browser `Origin`s, validates channel names, escapes logs, never logs image data |
| Fixes merged from open upstream PRs | – | grab#202, #203, #193, #189, #199, #184 (+#179, #146), #136, #187, #186 |
| `create_frame` | FILL/HUG sizing set before the frame has a parent (silently ignored) | Sizing applied after append; bad FILL/HUG requests fail with a clear error and leave no stray frame |
| Colours | Alpha 0 forced to 1 | Alpha kept |
| Scans | Temporary highlight could leave nodes recoloured | No highlight |
| Exports | `export_node_as_image` ignored the format | Uses the requested format (PNG/JPG/SVG/PDF) |
| Headless server | – | `deploy/linux/`: Xvfb + figma-linux + systemd + watchdog, sign-in without a screen |
| Tests | – | 43 unit + end-to-end tests (`bun run test`) |

## Quick start (your own computer)

Works on macOS, Windows and Linux desktops with the Figma desktop app
([figma-linux](https://github.com/Figma-Linux/figma-linux) on Linux). Browser Figma can't run local plugins.

1. Install [Bun](https://bun.sh): `curl -fsSL https://bun.sh/install | bash`
   (Windows: `powershell -c "irm bun.sh/install.ps1|iex"`).
2. Clone and build:

   ```bash
   git clone https://github.com/proSamik/claude-code-figma-free-mcp-server-plugin.git
   cd claude-code-figma-free-mcp-server-plugin
   bun install && bun run build
   ```

3. Start the relay and leave it running: `bun socket`
   (to keep it running in the background, see [Run the relay as a service](#run-the-relay-as-a-service)).
4. In Figma: **Plugins › Development › Import plugin from manifest…** and pick
   `src/cursor_mcp_plugin/manifest.json`.
5. Add the MCP server to your agent (next section). Use the full path to your checkout.
6. In Figma, open a file and run **Plugins › Development › Claude Code Figma MCP**. It connects to
   the relay and shows a **channel name**. Tell your agent: *"join Talk to Figma channel `abc123`, then …"*.

The plugin must stay open while the agent works. Closing it or the file disconnects; run it again to
get a new channel.

## Download a release (no build needed)

Every tagged version is on the [Releases page](https://github.com/proSamik/claude-code-figma-free-mcp-server-plugin/releases)
as a self-contained zip: `server.js` (MCP server with all libraries bundled; runs on Node 18+ or Bun),
`relay.js` (run with `bun relay.js`) and `figma-plugin/`. Unzip it, start the relay, import
`figma-plugin/manifest.json` in Figma and point your agent at `node /path/to/server.js`. The zip's own
README has the exact commands. To build one yourself: `bun run release`.

Maintainers: push a tag like `v0.4.1` and the Release workflow tests, builds and publishes it.

## Add the MCP server to your agent

**Claude Code** (all projects):

```bash
claude mcp add --scope user TalkToFigma -- bun run /path/to/claude-code-figma-free-mcp-server-plugin/dist/server.js
```

**Codex:**

```bash
codex mcp add TalkToFigma -- bun run /path/to/claude-code-figma-free-mcp-server-plugin/dist/server.js
```

**Cursor** (`~/.cursor/mcp.json`) or any stdio MCP client:

```json
{
  "mcpServers": {
    "TalkToFigma": {
      "command": "bun",
      "args": ["run", "/path/to/claude-code-figma-free-mcp-server-plugin/dist/server.js"]
    }
  }
}
```

`bun setup` writes `.mcp.json` and `.cursor/mcp.json` for this folder. Server options:
`--port=<port>` (relay port, default 3055) and `--server=<host>` (remote relay over `wss://`).
Start a new agent session after adding the server.

### Run the relay as a service

- **macOS** (launchd): create `~/Library/LaunchAgents/com.claudecodefigma.relay.plist` that runs
  `~/.bun/bin/bun run src/socket.ts` with `WorkingDirectory` set to the repo, `RunAtLoad` and
  `KeepAlive` true, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claudecodefigma.relay.plist`.
- **Linux desktop**: copy `deploy/linux/systemd/figma-relay.service` to `~/.config/systemd/user/`,
  create `~/.config/claude-code-figma/env` from `deploy/linux/env.example`, then
  `systemctl --user enable --now figma-relay`.
- **Windows + WSL**: run the relay so Windows can reach it: `HOST=0.0.0.0 bun socket`.

Relay settings: `HOST` (default `127.0.0.1`), `PORT` (default `3055`), `ALLOWED_ORIGINS`
(extra browser origins, comma-separated).

## Run 24/7 on a headless Linux server (VPS)

Use this to give a cloud agent or bot (for example one running in Docker on the same server) a Figma
that is always available. It packages the setup that runs on an Ubuntu 26.04 x86_64 server; any
recent Ubuntu/Debian with systemd should work (x86_64 or arm64). Figma itself runs on a virtual display, so it keeps working with no
monitor, while the desktop is locked, and after reboots.

**What runs** (all as systemd *user* services, started at boot via lingering):

| Unit | Role |
|---|---|
| `figma-relay` | The relay (`src/socket.ts`) on `RELAY_HOST:RELAY_PORT` |
| `figma-xvfb` | Virtual display `:99` |
| `figma-headless` | figma-linux on that display, Chrome DevTools on `127.0.0.1:9222` (local only) |
| `figma-autostart` | Opens `FIGMA_FILE_URL` and starts the plugin through Figma's quick actions (xdotool), then records the channel |
| `figma-watchdog.timer` | Every 5 minutes runs the same check; if the plugin stops answering it restarts Figma/the plugin |

### 1. Install

```bash
git clone https://github.com/proSamik/claude-code-figma-free-mcp-server-plugin.git ~/claude-code-figma-free-mcp-server-plugin
~/claude-code-figma-free-mcp-server-plugin/deploy/linux/install.sh
```

`install.sh` installs Xvfb, xdotool, figma-linux (latest release for your CPU) and Bun, builds the
server, registers the plugin with figma-linux, copies the units and enables lingering. The units
expect the repo at `~/claude-code-figma-free-mcp-server-plugin`.

### 2. Configure

Edit `~/.config/claude-code-figma/env`:

- `FIGMA_FILE_URL` – the file to open automatically (`https://www.figma.com/design/<key>/...`).
- `RELAY_HOST` – keep `127.0.0.1` if the agent runs on the same host. If it runs in Docker, use the
  Docker bridge address (usually `172.17.0.1`) and allow only Docker networks through the firewall,
  e.g. `sudo ufw allow from 172.16.0.0/12 to 172.17.0.1 port 3055 proto tcp`.
- `CHANNEL_FILE` – optional extra path to write the current channel to (e.g. a folder mounted into
  an agent's container).

### 3. Sign Figma in (no screen needed)

figma-linux signs in through your browser. On a server the browser hand-off can't reach Figma, so:

```bash
~/claude-code-figma-free-mcp-server-plugin/deploy/linux/bin/figma-login.sh url
```

1. Open the printed `https://www.figma.com/app_auth/.../grant` link in your own browser and approve.
2. The browser then tries to open a `figma://app_auth/redeem?...` link. **Don't let your local Figma
   app take it**: click *Cancel* on the "Open Figma?" prompt and copy the link (Chrome: DevTools ›
   Console shows `Launched external handler for 'figma://...'`). The link works once.
3. Finish on the server:

   ```bash
   ~/claude-code-figma-free-mcp-server-plugin/deploy/linux/bin/figma-login.sh redeem 'figma://app_auth/redeem?...'
   ```

   It prints your Figma name when signed in. The session survives restarts.

### 4. Start and check

```bash
systemctl --user start figma-autostart
cat ~/.local/state/claude-code-figma/channel        # the channel agents must join
journalctl --user -u figma-autostart -n 20          # what the autostart/watchdog did
```

To see the virtual screen: `DISPLAY=:99 ffmpeg -f x11grab -video_size 1920x1080 -i :99 -frames:v 1 /tmp/figma.jpg`.

### 5. Connect the agent

Point the agent's MCP config at `bun run ~/claude-code-figma-free-mcp-server-plugin/dist/server.js`
(add `--port=<RELAY_PORT>` if you changed it). Inside Docker, either install Bun in the container
and mount the repo, or forward `127.0.0.1:3055` in the container to the relay with a small `socat`
sidecar (`TCP-LISTEN:3055,bind=127.0.0.1,fork TCP:172.17.0.1:3055`) and run the server with
`npx`/`bun` there. Have the agent read the channel from the channel file and call `join_channel`.

**Good to know**

- The channel changes whenever Figma or the plugin restarts; the watchdog writes the new one.
- If Figma gets signed out, the autostart log says so; repeat step 3.
- Figma's DevTools port (9222) gives full control of the signed-in app. It only listens on
  `127.0.0.1`; never expose it.
- figma-linux can't open web links on the server; they are written to
  `~/.local/state/claude-code-figma/opened-urls.log`.

## Project structure

- `src/talk_to_figma_mcp/` – MCP server (`server.ts`, bulk export jobs in `bulk_export.ts`)
- `src/cursor_mcp_plugin/` – Figma plugin (`code.js`, `ui.html`, `manifest.json`; not bundled)
- `src/socket.ts` – WebSocket relay
- `deploy/linux/` – headless server kit (install script, systemd units, autostart/watchdog, sign-in helper)
- `tests/` – unit and end-to-end tests

## MCP Tools

The MCP server provides the following tools for interacting with Figma:

### Document & Selection

- `get_document_info` - Get current-page details plus a document-wide page index
- `get_pages` - Enumerate every page; top-level child counts are opt-in
- `set_current_page` - Switch the active page for subsequent page-scoped operations
- `get_selection` - Get information about the current selection
- `read_my_design` - Get detailed node information about the current selection without parameters
- `get_node_info` - Get detailed information about a specific node
- `get_nodes_info` - Get detailed information about multiple nodes by providing an array of node IDs
- `set_focus` - Set focus on a specific node by selecting it and scrolling viewport to it
- `set_selections` - Set selection to multiple nodes and scroll viewport to show them
- `select_nodes` - Multi-select nodes by ID; switches to the page that holds them (reports IDs that are missing or on other pages)

### Annotations

- `get_annotations` - Get all annotations in the current document or specific node
- `set_annotation` - Create or update an annotation with markdown support
- `set_multiple_annotations` - Batch create/update multiple annotations efficiently
- `scan_nodes_by_types` - Scan for nodes with specific types (useful for finding annotation targets)

### Prototyping & Connections

- `get_reactions` - Get all prototype reactions from nodes with visual highlight animation
- `set_default_connector` - Set a copied FigJam connector as the default connector style for creating connections (must be set before creating connections)
- `create_connections` - Create FigJam connector lines between nodes, based on prototype flows or custom mapping

### Creating Elements

- `create_rectangle` - Create a new rectangle with position, size, and optional name
- `create_frame` - Create a new frame with position, size, and optional name
- `create_section` - Create a section to group related content on the canvas
- `create_text` - Create a new text node with customizable font properties

### Modifying text content

- `scan_text_nodes` - Scan text nodes with intelligent chunking for large designs
- `set_text_content` - Set the text content of a single text node
- `set_multiple_text_contents` - Batch update multiple text nodes efficiently

### Auto Layout & Spacing

- `set_layout_mode` - Set the layout mode and wrap behavior of a frame (NONE, HORIZONTAL, VERTICAL)
- `set_padding` - Set padding values for an auto-layout frame (top, right, bottom, left)
- `set_axis_align` - Set primary and counter axis alignment for auto-layout frames
- `set_layout_sizing` - Set horizontal and vertical sizing modes for auto-layout frames (FIXED, HUG, FILL)
- `set_item_spacing` - Set distance between children in an auto-layout frame

### Styling

- `set_fill_color` - Set the fill color of a node (RGBA)
- `set_stroke_color` - Set the stroke color and weight of a node
- `set_corner_radius` - Set the corner radius of a node with optional per-corner control
- `set_image_fill` - Fill a node with an image from a local file path, URL, or base64 data (FILL, FIT, CROP, or TILE)

### Layout & Organization

- `move_node` - Move a node to a new position
- `resize_node` - Resize a node with new dimensions
- `delete_node` - Delete a node
- `delete_multiple_nodes` - Delete multiple nodes at once efficiently
- `clone_node` - Create a copy of an existing node with optional position offset
- `rename_node` - Rename a node
- `set_parent` - Move a node into a new parent (section, frame or group), preserving its absolute position by default

### Components & Styles

- `get_styles` - Get information about local styles
- `get_local_components` - Get information about local components
- `create_component_instance` - Create an instance of a component
- `get_instance_overrides` - Extract override properties from a selected component instance
- `set_instance_overrides` - Apply extracted overrides to target instances

### Export & Advanced

- `export_node_as_image` - Export a node as an image (PNG, JPG, SVG, or PDF) - limited support on image currently returning base64 as text
- `start_bulk_export` - Select many nodes by ID and export them all to files on disk as a background job; returns a `jobId` immediately
- `get_bulk_export_status` - Progress of a bulk export: done / left / failed (with errors), percent, current node, ETA, status
- `cancel_bulk_export` - Cancel a running bulk export (files already written are kept)

### Bulk export

Exporting many nodes with `export_node_as_image` in a loop is slow: every node is a separate
round trip, and the image comes back as base64 into the agent's context. Bulk export runs the
whole batch inside the plugin and writes files on the machine that runs the MCP server.

```text
start_bulk_export({
  nodeIds: ["12:34", "12:35", ...],
  outputDir: "/tmp/exports",        // created if missing
  format: "PNG",                    // PNG (default) | JPG | SVG | PDF
  scale: 2,                         // PNG/JPG only, default 1
  fileNames: ["home", "settings"],  // optional: array in nodeIds order, or { "12:34": "home" }
  concurrency: 3,                   // optional, default 3, falls back to 1 if Figma errors
  nodeTimeoutMs: 120000,            // optional per-node timeout
  select: true                      // optional, multi-select the nodes in Figma first
})
-> { "jobId": "bulk-...", "status": "running", "total": 323, "selectedCount": 323, ... }

get_bulk_export_status({ jobId: "bulk-..." })
-> 180/323 done (55.7%), 143 left, 2 failed, ETA ~4m
   { "status": "running", "done": 180, "left": 143, "failed": [{ "nodeId": "...", "error": "..." }], ... }
```

- Files are named `<fileName or nodeId>.<ext>`; `:` and other unsafe characters become `-`
  (node `12:34` -> `12-34.png`). Duplicate names get `_2`, `_3`, ...
- A node that fails or times out is recorded in `failed` and the batch keeps going.
- When the job ends, `bulk-export-<jobId>.json` (final status + file list) is written to `outputDir`.
- The plugin window shows a progress bar with done / left / failed, and Figma shows a
  notification when the export starts and ends.
- Status is `running`, `done`, `failed` or `cancelled`. A job that gets no events from Figma
  for 3 minutes, or loses the relay connection, is marked `failed`.
- Bulk export needs the plugin and MCP server from this repo; the relay in `src/socket.ts` relays
  image chunks without logging them.

### Connection Management

- `join_channel` - Join a specific channel to communicate with Figma

### MCP Prompts

The MCP server includes several helper prompts to guide you through complex design tasks:

- `design_strategy` - Best practices for working with Figma designs
- `read_design_strategy` - Best practices for reading Figma designs
- `text_replacement_strategy` - Systematic approach for replacing text in Figma designs
- `annotation_conversion_strategy` - Strategy for converting manual annotations to Figma's native annotations
- `swap_overrides_instances` - Strategy for transferring overrides between component instances in Figma
- `reaction_to_connector_strategy` - Strategy for converting Figma prototype reactions to connector lines using the output of 'get_reactions', and guiding the use 'create_connections' in sequence

## Development

### Building the Figma Plugin

1. Navigate to the Figma plugin directory:

   ```
   cd src/cursor_mcp_plugin
   ```

2. Edit code.js and ui.html

### Tests

```bash
bun run typecheck
bun run test   # builds, then runs unit tests and an end-to-end test
```

The end-to-end test starts the relay on a random free port, runs the built MCP server
against it, and runs the real `code.js` and `ui.html` script with a fake Figma API.

## Best Practices

When working with the Figma MCP:

1. Always join a channel before sending commands
2. Get the document page index using `get_pages`, then use `get_document_info` for the current page
3. Check current selection with `get_selection` before modifications
4. Use appropriate creation tools based on needs:
   - `create_frame` for containers
   - `create_rectangle` for basic shapes
   - `create_text` for text elements
5. Verify changes using `get_node_info`
6. Use component instances when possible for consistency
7. Handle errors appropriately as all commands can throw exceptions
8. For large designs:
   - Use chunking parameters in `scan_text_nodes`
   - Monitor progress through WebSocket updates
   - Implement appropriate error handling
9. For text operations:
   - Use batch operations when possible
   - Consider structural relationships
   - Verify changes with targeted exports
10. For converting legacy annotations:
    - Scan text nodes to identify numbered markers and descriptions
    - Use `scan_nodes_by_types` to find UI elements that annotations refer to
    - Match markers with their target elements using path, name, or proximity
    - Categorize annotations appropriately with `get_annotations`
    - Create native annotations with `set_multiple_annotations` in batches
    - Verify all annotations are properly linked to their targets
    - Delete legacy annotation nodes after successful conversion
11. Visualize prototype noodles as FigJam connectors:

- Use `get_reactions` to extract prototype flows,
- set a default connector with `set_default_connector`,
- and generate connector lines with `create_connections` for clear visual flow mapping.

## Privacy

The plugin (inherited from upstream) sends anonymous usage events (plugin opens, command names,
success/error) to Google Analytics; no file content is sent. To turn it off, remove the analytics
block in `src/cursor_mcp_plugin/ui.html` and the Google Analytics domains in `manifest.json`.

## Credits

Built on [Talk to Figma MCP](https://github.com/grab/cursor-talk-to-figma-mcp) by
[Sonny Lazuardi](https://github.com/sonnylazuardi), Grab and contributors, including the upstream
pull requests listed above. Bulk export, page-aware selection, the `create_frame` fixes and the
headless Linux kit are by [proSamik](https://github.com/proSamik).

## License

MIT
