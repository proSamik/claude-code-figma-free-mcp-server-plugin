// Evaluate JavaScript in a figma-linux page over the local Chrome DevTools port.
// usage: bun cdp.ts <targetId> '<js expression>'
const [id, expr] = process.argv.slice(2);
const port = process.env.CDP_PORT ?? "9222";
const ws = new WebSocket(`ws://127.0.0.1:${port}/devtools/page/${id}`);
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression: expr, awaitPromise: true, returnByValue: true, userGesture: true } }));
ws.onmessage = (e) => { const m = JSON.parse(String(e.data)); if (m.id === 1) { console.log(JSON.stringify(m.result?.result?.value ?? m.result ?? m.error)); process.exit(0); } };
setTimeout(() => { console.log("timeout"); process.exit(1); }, 15000);
