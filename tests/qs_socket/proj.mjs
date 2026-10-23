export function hello(x) { return "mjs-ok:" + x }
export function ack(acks, a) { const n = Object.assign({}, acks); n[a.pane_id] = Math.max(n[a.pane_id] || 0, a.state_change_seq || 0); return n }
