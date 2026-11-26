#!/bin/bash

MCP_CONFIG='{
  "mcpServers": {
    "TalkToFigma": {
      "command": "bun",
      "args": [
        "run", "dist/server.js"
      ]
    }
  }
}'

bun install
bun run build

# Cursor: write .cursor/mcp.json
mkdir -p .cursor
echo "$MCP_CONFIG" > .cursor/mcp.json
echo "✓ Cursor MCP config written to .cursor/mcp.json"

# Claude Code: write .mcp.json in project root
echo "$MCP_CONFIG" > .mcp.json
echo "✓ Claude Code MCP config written to .mcp.json"

echo "✓ Claude Code (all projects): claude mcp add --scope user TalkToFigma -- bun run $(pwd)/dist/server.js"
echo "✓ Codex: codex mcp add TalkToFigma -- bun run $(pwd)/dist/server.js"
