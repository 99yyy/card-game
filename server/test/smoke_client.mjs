// 端到端冒烟：两个 WS 客户端 + 2 机器人，走完 建房→加入→补机器人→开局→打完整局
const BASE = process.env.BASE || "http://127.0.0.1:8787";
const WS_BASE = BASE.replace("http", "ws");

const res = await fetch(BASE + "/create", { method: "POST" });
const { room } = await res.json();
console.log("room =", room);

function client(name) {
  const ws = new WebSocket(`${WS_BASE}/ws?room=${room}&name=${encodeURIComponent(name)}`);
  const c = { name, ws, seat: -1, view: null, lobby: null, over: false, rejected: 0 };
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.t === "joined") { c.seat = m.seat; c.token = m.token; }
    if (m.t === "lobby") c.lobby = m;
    if (m.t === "rejected") { c.rejected++; console.log(name, "REJECTED", m.reason); }
    if (m.t === "game") {
      c.view = m.view;
      for (const e of m.events) if (e.type === "GAME_OVER") { c.over = true; c.winner = e.winner; }
      act(c);
    }
  };
  return c;
}

function act(c) {
  const v = c.view;
  if (!v || c.over) return;
  // 选技能
  if (v.phase === 0 && v.you.pending_skill_pick === -1) {
    send(c, { type: "PICK_SKILL", pid: c.seat, skill: (c.seat * 2) % 6 });
    return;
  }
  // 改弦窗口：直接跳过（服务端 5 秒也会自动过，这里不抢）
  // 出招：轮到我就出第一张（简单策略，验证流程而非智力）
  if (v.phase === 2 && v.current_player === c.seat && v.you.hand.length > 0) {
    setTimeout(() => {
      if (c.view && c.view.phase === 2 && c.view.current_player === c.seat)
        send(c, { type: "PLAY", pid: c.seat, indices: [0] });
    }, 150);
  }
}
function send(c, action) { c.ws.send(JSON.stringify({ t: "action", action })); }

const a = client("甲");
await new Promise(r => setTimeout(r, 400));
const b = client("乙");
await new Promise(r => setTimeout(r, 600));

// 由真正的房主（lobby.host）补机器人并开局 —— 并发加入时座位顺序不保证
while (!a.lobby) await new Promise(r => setTimeout(r, 100));
const host = a.lobby.host === a.seat ? a : b;
host.ws.send(JSON.stringify({ t: "add_bot" }));
host.ws.send(JSON.stringify({ t: "add_bot" }));
await new Promise(r => setTimeout(r, 800));
console.log("lobby:", JSON.stringify(host.lobby?.seats), "can_start:", host.lobby?.can_start, "host:", host.lobby?.host);
host.ws.send(JSON.stringify({ t: "start" }));

// 最多等 150 秒打完
const t0 = Date.now();
while (!(a.over || b.over) && Date.now() - t0 < 150000)
  await new Promise(r => setTimeout(r, 500));

console.log("over:", a.over || b.over, "winner:", a.winner ?? b.winner);
console.log("甲 view round:", a.view?.round_number, "乙 view round:", b.view?.round_number);
// 机密检查：view 里不得含他人 hand
const leak = s => s.includes('"hollow') || /"players":\[[^\]]*"hand":/.test(s);
console.log("机密泄漏:", leak(JSON.stringify(a.view)) || leak(JSON.stringify(b.view)));
console.log("REJECTED 次数:", a.rejected + b.rejected);
process.exit(a.over || b.over ? 0 : 1);
