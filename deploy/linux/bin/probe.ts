// Health check: join the plugin's channel through the relay and ask Figma for the document.
// Exits 0 if the plugin answers. usage: bun probe.ts <channel> [port]
const [channel, port = process.env.RELAY_PORT ?? "3055"] = process.argv.slice(2);
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const id = crypto.randomUUID();
const t = setTimeout(() => process.exit(2), 20000);
ws.onopen = () => {
  ws.send(JSON.stringify({ id: crypto.randomUUID(), type: "join", channel }));
  setTimeout(() => ws.send(JSON.stringify({ id, type: "message", channel, message: { id, command: "get_document_info", params: { commandId: id } } })), 500);
};
ws.onmessage = (e) => {
  const m = JSON.parse(String(e.data)).message;
  if (m && m.id === id && (m.result !== undefined || m.error)) { clearTimeout(t); ws.close(); process.exit(m.error ? 1 : 0); }
};
