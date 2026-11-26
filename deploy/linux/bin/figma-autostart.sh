#!/bin/bash
# Keeps the plugin usable on a headless Linux server: figma-linux on the virtual display,
# the target file open, and the plugin running and joined to the relay.
# Idempotent: exits at once if the plugin already answers. Run by figma-autostart.service
# at boot and by figma-watchdog.timer every 5 minutes.
set -u
. "$HOME/.config/claude-code-figma/env"
export DISPLAY="$FIGMA_DISPLAY"
D="$REPO_DIR/deploy/linux/bin"; BUN="${BUN:-$HOME/.bun/bin/bun}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-figma"; mkdir -p "$STATE"
log() { echo "$(date -Is) $*"; }
channel() { journalctl --user -u figma-relay --since -7d --no-pager 2>/dev/null | grep -o 'joined channel "[A-Za-z0-9_-]*"' | tail -1 | cut -d'"' -f2; }
probe() { local ch; ch=$(channel); [ -n "$ch" ] && timeout 25 "$BUN" "$D/probe.ts" "$ch" "$RELAY_PORT" >/dev/null 2>&1; }
publish() {
  local ch; ch=$(channel); [ -z "$ch" ] && return 0
  [ "$ch" != "$(cat "$STATE/channel" 2>/dev/null)" ] && echo "$ch" > "$STATE/channel" && log "channel $ch"
  [ -n "${CHANNEL_FILE:-}" ] && [ "$ch" != "$(cat "$CHANNEL_FILE" 2>/dev/null)" ] && echo "$ch" > "$CHANNEL_FILE"
  return 0
}
pages() { curl -s http://127.0.0.1:9222/json/list; }

if probe; then publish; exit 0; fi
log "plugin not answering; starting it"
systemctl --user is-active -q figma-relay || systemctl --user start figma-relay
systemctl --user is-active -q figma-headless || systemctl --user start figma-headless
for i in $(seq 1 60); do pages | grep -q figma.com && break; sleep 3; done
if pages | grep -q "figma.com/login"; then log "figma-linux is signed out: run deploy/linux/bin/figma-login.sh url"; exit 1; fi
KEY=$(printf %s "${FIGMA_FILE_URL:-}" | grep -o '/\(design\|file\)/[A-Za-z0-9]*' | cut -d/ -f3)
if [ -n "$KEY" ] && ! pages | grep -q "/$KEY"; then
  T=$(pages | python3 -I -c "import json,sys;l=[t['id'] for t in json.load(sys.stdin) if t['type']=='page' and 'figma.com' in t['url']];print(l[0] if l else '')")
  "$BUN" "$D/cdp.ts" "$T" "location.href=\"https://www.figma.com/design/$KEY\";\"ok\"" >/dev/null
  for i in $(seq 1 40); do pages | grep -q "/design/$KEY" && break; sleep 3; done
  sleep 20
fi
W=$(xdotool search --onlyvisible --class figma 2>/dev/null | head -1)
[ -z "$W" ] && { log "no Figma window on $DISPLAY"; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$W")"
for attempt in 1 2 3; do
  [ -n "$KEY" ] && { xdotool mousemove $((X+157)) $((Y+20)) click 1; sleep 8; }   # the file's tab
  xdotool mousemove $((X+620)) $((Y+810)) click 1; sleep 1                           # focus the canvas
  xdotool key Escape; xdotool key ctrl+slash; sleep 2                                # quick actions
  xdotool type --delay 60 "$PLUGIN_NAME"; sleep 3; xdotool key Return
  for i in $(seq 1 10); do sleep 3; if probe; then publish; log "plugin connected (attempt $attempt)"; exit 0; fi; done
  xdotool key Escape
done
log "plugin did not connect"; exit 1
