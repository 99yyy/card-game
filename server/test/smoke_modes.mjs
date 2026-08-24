// 线上多模式冒烟：每个模式 建房→设模式→补3机器人→开局→真人由bot策略代打→打完
import { Rng } from "../src/core/rng.js";
import { botDecide } from "../src/core/bot.js";
import { diceBotDecide } from "../src/core/game_dice.js";
import { poisonBotDecide } from "../src/core/game_poison.js";

const BASE = process.env.BASE || "https://jueding-server.99yyy.workers.dev";
const WS_BASE = BASE.replace("http", "ws");
const rng = new Rng(42);

async function runMode(mode) {
  const res = await fetch(BASE + "/create", { method: "POST" });
  const { room } = await res.json();
  const ws = new WebSocket(`${WS_BASE}/ws?room=${room}&name=测试侠`);
  const st = { seat: -1, view: null, over: false, winner: -1, lobby: null, rejected: 0, started: false };
  let acting = false;
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.t === "joined") st.seat = m.seat;
    if (m.t === "lobby") st.lobby = m;
    if (m.t === "rejected") st.rejected++;
    if (m.t === "game") {
      st.view = m.view;
      for (const e of m.events) if (e.type === "GAME_OVER") { st.over = true; st.winner = e.winner; }
      act();
    }
  };
  function act() {
    if (acting || st.over || !st.view) return;
    acting = true;
    setTimeout(() => {
      acting = false;
      const v = st.view;
      if (!v || st.over) return;
      if (v.phase === 0) {   // PICK
        if (mode >= 2) {
          if (!v.you.ready) {
            ws.send(JSON.stringify({ t: "action", action: { type: "PICK_CHAR", pid: st.seat, char_id: 2 } }));
            ws.send(JSON.stringify({ t: "action", action: { type: "READY", pid: st.seat } }));
          }
        } else if (v.you.pending_skill_pick === -1) {
          ws.send(JSON.stringify({ t: "action", action: { type: "PICK_SKILL", pid: st.seat, skill: 1 } }));
        }
        return;
      }
      if (v.phase !== 2) return;
      const myTurn = mode === 3
        ? (v.offer_active ? v.offer_to === st.seat : v.current_player === st.seat)
        : v.current_player === st.seat;
      if (!myTurn) return;
      let a;
      if (mode === 2) a = diceBotDecide(v, rng);
      else if (mode === 3) a = poisonBotDecide(v, rng);
      else a = botDecide(v, rng);
      ws.send(JSON.stringify({ t: "action", action: a }));
    }, 250);
  }
  await new Promise(r => { const i = setInterval(() => { if (st.seat >= 0 && st.lobby) { clearInterval(i); r(); } }, 100); });
  ws.send(JSON.stringify({ t: "set_mode", mode }));
  ws.send(JSON.stringify({ t: "add_bot" }));
  ws.send(JSON.stringify({ t: "add_bot" }));
  ws.send(JSON.stringify({ t: "add_bot" }));
  await new Promise(r => setTimeout(r, 800));
  const gm = st.lobby?.game_mode;
  ws.send(JSON.stringify({ t: "start" }));
  const t0 = Date.now();
  while (!st.over && Date.now() - t0 < 240000) {
    await new Promise(r => setTimeout(r, 400));
    act();
  }
  ws.close();
  const leak = JSON.stringify(st.view || {});
  const secretLeak = leak.includes("hollow") || leak.includes("offerCard");
  console.log(`mode=${mode} lobby_mode=${gm} over=${st.over} winner=${st.winner} rejected=${st.rejected} 泄漏=${secretLeak}`);
  return st.over;
}

// 暗器/递毒并行（服务端新路径）；论招/心魔线上通路此前已验证
const results = await Promise.all([runMode(2), runMode(3)]);
process.exit(results.every(Boolean) ? 0 : 1);
