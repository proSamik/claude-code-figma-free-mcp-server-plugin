#!/bin/bash
# Builds a self-contained release into release/ and zips it:
#   server.js      MCP server with all libraries bundled; runs with `node server.js` or `bun server.js`
#   relay.js       WebSocket relay, bundled; runs with `bun relay.js` (uses Bun's WebSocket server)
#   figma-plugin/  import figma-plugin/manifest.json in Figma (Plugins > Development > Import plugin from manifest)
# Usage: scripts/release.sh [version]   (default: version from package.json)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(python3 -I -c 'import json;print(json.load(open("package.json"))["version"])')}"
VERSION="${VERSION#v}"
NAME="claude-code-figma-mcp-v$VERSION"
OUT="release/$NAME"
rm -rf release && mkdir -p "$OUT/figma-plugin"
bun build src/talk_to_figma_mcp/server.ts --target=node --outfile "$OUT/server.js"
bun build src/socket.ts --target=bun --outfile "$OUT/relay.js"
cp src/cursor_mcp_plugin/manifest.json src/cursor_mcp_plugin/code.js src/cursor_mcp_plugin/ui.html "$OUT/figma-plugin/"
cp LICENSE "$OUT/"
cat > "$OUT/README.md" <<MD
# Claude Code Figma MCP v$VERSION

Self-contained build of https://github.com/proSamik/claude-code-figma-free-mcp-server-plugin
(no \`npm install\` needed). Needs [Bun](https://bun.sh) for the relay; the MCP server runs on Node 18+ or Bun.

1. Start the relay and leave it running:  \`bun relay.js\`
   (settings: \`HOST\` default 127.0.0.1, \`PORT\` default 3055, \`ALLOWED_ORIGINS\`)
2. In Figma desktop: Plugins > Development > Import plugin from manifest > \`figma-plugin/manifest.json\`
3. Add the MCP server to your agent, using the full path to this folder:
   - Claude Code: \`claude mcp add --scope user TalkToFigma -- node /path/to/$NAME/server.js\`
   - Codex: \`codex mcp add TalkToFigma -- node /path/to/$NAME/server.js\`
   - Other clients: command \`node\`, args \`["/path/to/$NAME/server.js"]\`
4. In Figma run Plugins > Development > Claude Code Figma MCP, then tell your agent the channel it shows.

For the 24/7 headless Linux server setup, clone the repo and see its README (deploy/linux).
MD
(cd release && zip -qr "$NAME.zip" "$NAME")
cp "$OUT/server.js" "release/claude-code-figma-mcp-server-v$VERSION.js"
echo "release/$NAME.zip"
