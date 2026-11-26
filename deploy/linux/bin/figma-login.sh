#!/bin/bash
# Sign headless figma-linux in to Figma without a screen.
#   figma-login.sh url                  -> prints a sign-in link; open it in any browser and approve
#   figma-login.sh redeem 'figma://...' -> finishes sign-in with the figma:// link the browser tried to open
# The browser on your own computer will try to hand the figma:// link to a local Figma app.
# Cancel that prompt, or copy the link from the browser console/network tab, and pass it here.
set -euo pipefail
. "$HOME/.config/claude-code-figma/env"
D="$REPO_DIR/deploy/linux/bin"; BUN="${BUN:-$HOME/.bun/bin/bun}"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-figma/opened-urls.log"
page() { curl -s http://127.0.0.1:9222/json/list | python3 -I -c "import json,sys;l=[t['id'] for t in json.load(sys.stdin) if t['type']=='page' and 'figma.com' in t['url']];print(l[0] if l else '')"; }
case "${1:-}" in
  url)
    T=$(page); [ -z "$T" ] && { echo "figma-linux is not running (systemctl --user start figma-headless)"; exit 1; }
    "$BUN" "$D/cdp.ts" "$T" 'location.href="https://www.figma.com/login?is_not_gen_0=true";"ok"' >/dev/null; sleep 8
    "$BUN" "$D/cdp.ts" "$T" '(()=>{const b=[...document.querySelectorAll("button,a,[role=button]")].find(x=>(x.innerText||"").trim()==="Log in with browser");if(!b)return "no button";b.click();return "ok"})()' >/dev/null
    sleep 4; grep -o 'https://www.figma.com/app_auth/[^ ]*' "$LOG" | tail -1 ;;
  redeem)
    U="${2:?pass the figma://app_auth/redeem?... link}"; H="https://www.figma.com/${U#figma://}"
    T=$(page); "$BUN" "$D/cdp.ts" "$T" "location.href=$(printf %s "$H" | python3 -I -c 'import json,sys;print(json.dumps(sys.stdin.read()))');\"ok\"" >/dev/null
    sleep 10; T=$(page)
    "$BUN" "$D/cdp.ts" "$T" 'fetch("/api/session/state").then(r=>r.json()).then(j=>((j.meta&&j.meta.users)||[]).map(u=>u.handle||u.name).join(",")||"NOT signed in")' ;;
  *) echo "usage: $0 url | redeem 'figma://app_auth/redeem?...'"; exit 2 ;;
esac
