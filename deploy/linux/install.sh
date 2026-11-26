#!/bin/bash
# One-time setup for a headless Ubuntu/Debian server (x86_64 or arm64).
# Run as the normal user that will own the services (not root); it uses sudo for packages.
# Expects this repo at ~/claude-code-figma-free-mcp-server-plugin.
set -euo pipefail
REPO="$HOME/claude-code-figma-free-mcp-server-plugin"
[ -d "$REPO/deploy/linux" ] || { echo "Clone the repo to $REPO first"; exit 1; }

echo "== packages (Xvfb, xdotool, curl, python3, unzip)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xvfb xdotool curl python3 unzip ca-certificates

if ! command -v figma-linux >/dev/null; then
  echo "== figma-linux (community desktop client; browser Figma cannot run local plugins)"
  arch=$(dpkg --print-architecture)   # amd64 | arm64
  url=$(curl -fsSL https://api.github.com/repos/Figma-Linux/figma-linux/releases/latest \
    | python3 -I -c "import json,sys;a=sys.argv[1];print([x['browser_download_url'] for x in json.load(sys.stdin)['assets'] if x['name'].endswith(f'_linux_{a}.deb')][0])" "$arch")
  tmp=$(mktemp -d); curl -fsSL -o "$tmp/figma-linux.deb" "$url"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/figma-linux.deb"; rm -rf "$tmp"
fi

if [ ! -x "$HOME/.bun/bin/bun" ]; then echo "== bun"; curl -fsSL https://bun.sh/install | bash; fi
(cd "$REPO" && "$HOME/.bun/bin/bun" install && "$HOME/.bun/bin/bun" run build)

echo "== config"
mkdir -p "$HOME/.config/claude-code-figma" "$HOME/.local/state/claude-code-figma" "$HOME/.config/systemd/user"
[ -f "$HOME/.config/claude-code-figma/env" ] || cp "$REPO/deploy/linux/env.example" "$HOME/.config/claude-code-figma/env"

echo "== register the plugin with figma-linux"
python3 -I - "$REPO" <<'PY'
import json, os, sys
repo = sys.argv[1]; p = os.path.expanduser("~/.config/figma-linux/settings.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
d = json.load(open(p)) if os.path.exists(p) else {}
ext = d.setdefault("app", {}).setdefault("savedExtensions", [])
path = f"{repo}/src/cursor_mcp_plugin"
if not any(e.get("path") == path for e in ext):
    ext.append({"id": max([e.get("id", 0) for e in ext] + [0]) + 1, "path": path,
                "lastKnownName": "Claude Code Figma MCP", "files": ["manifest.json", "code.js", "ui.html"]})
json.dump(d, open(p, "w"), indent=2)
PY

echo "== services"
cp "$REPO"/deploy/linux/systemd/* "$HOME/.config/systemd/user/"
sudo loginctl enable-linger "$USER"     # start user services at boot without a login
systemctl --user daemon-reload
systemctl --user enable --now figma-relay figma-xvfb figma-headless
systemctl --user enable figma-autostart figma-watchdog.timer
systemctl --user start figma-watchdog.timer

cat <<MSG

Done. Next:
  1. Edit ~/.config/claude-code-figma/env (FIGMA_FILE_URL, RELAY_HOST if containers need it).
  2. Sign in:   $REPO/deploy/linux/bin/figma-login.sh url
                (open the link, approve, then:)  figma-login.sh redeem 'figma://app_auth/redeem?...'
  3. Start:     systemctl --user start figma-autostart
  4. Channel:   cat ~/.local/state/claude-code-figma/channel
MSG
