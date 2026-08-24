// 房间 Durable Object —— 规则草案 §11.2 的五条硬保证在此落实。
// 同码必同房：Worker 用 idFromName("room:" + 房号) 寻址（保证 1）。
// 等待厅唯一真相：本 DO 广播的完整状态包（保证 2）。
// 重连令牌（保证 3）、拒绝给原因（保证 4）、机器人填位（保证 5）。
import * as R from "./core/rules.js";
import { Rng } from "./core/rng.js";
import { Game } from "./core/game.js";
import { botDecide } from "./core/bot.js";

const MAX_SEATS = R.MAX_PLAYERS;

export class Room {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.mode = "lobby";              // lobby | playing | over
    this.seats = [];                  // {seat,name,isBot,token,ws,connected}
    this.game = null;
    this.driverRng = new Rng((Date.now() ^ 0x5DEECE66) >>> 0);
    this.timers = { turn: null, bot: null, pick: null, swap: null };
    this.turnDeadline = 0;            // epoch ms，随状态广播
    this.roomCode = "";
  }

  // ---------- HTTP/WS 入口 ----------
  async fetch(req) {
    const url = new URL(req.url);
    this.roomCode = url.searchParams.get("room") || this.roomCode;
    if (url.pathname === "/ws") {
      if (req.headers.get("Upgrade") !== "websocket")
        return new Response("expected websocket", { status: 426 });
      const pair = new WebSocketPair();
      await this._accept(pair[1], url);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === "/occupancy")
      return Response.json({ seats: this.seats.length, mode: this.mode });
    return new Response("not found", { status: 404 });
  }

  async _accept(ws, url) {
    ws.accept();
    const name = (url.searchParams.get("name") || "侠客").slice(0, 12);
    const token = url.searchParams.get("token") || "";

    // 重连：凭令牌回原座位（保证 3）
    const back = this.seats.find(s => !s.isBot && s.token === token && token !== "");
    if (back) {
      if (back.ws) { try { back.ws.close(4000, "replaced"); } catch {} }
      back.ws = ws; back.connected = true; back.name = name || back.name;
      this._wire(ws, back);
      this._send(back, { t: "joined", seat: back.seat, token: back.token, room: this.roomCode });
      if (this.mode === "playing") this._pushGameTo(back, []);
      this._broadcastLobby();
      return;
    }
    // 新加入：只在等待厅接受（保证 4：拒绝给原因）
    if (this.mode === "playing") { ws.close(4001, "in_progress"); return; }
    if (this.seats.filter(s => !s.isBot).length + this.seats.filter(s => s.isBot).length >= MAX_SEATS) {
      ws.close(4002, "room_full"); return;
    }
    const seat = {
      seat: this.seats.length, name, isBot: false,
      token: crypto.randomUUID(), ws, connected: true,
    };
    this.seats.push(seat);
    this._wire(ws, seat);
    this._send(seat, { t: "joined", seat: seat.seat, token: seat.token, room: this.roomCode });
    this._broadcastLobby();
  }

  _wire(ws, seat) {
    ws.addEventListener("message", ev => {
      let m;
      try { m = JSON.parse(ev.data); } catch { return; }
      this._onMessage(seat, m);
    });
    const drop = () => {
      seat.connected = false;
      seat.ws = null;
      if (this.mode === "lobby") {
        // 等待厅里离开 = 让座（重连令牌在 60 秒内仍可回来占新座）
        this.seats = this.seats.filter(s => s !== seat);
        this.seats.forEach((s, i) => s.seat = i);
        if (this.game === null) this._broadcastLobby();
      } else {
        this._broadcastLobby();       // 对局中：座位保留，托管为机器人（边界 17）
        this._maybeBotAct();
      }
    };
    ws.addEventListener("close", drop);
    ws.addEventListener("error", drop);
  }

  _onMessage(seat, m) {
    switch (m.t) {
      case "ping": this._send(seat, { t: "pong" }); break;
      case "add_bot":
        if (this._hostSeat() !== seat || this.mode !== "lobby") return;
        if (this.seats.length >= MAX_SEATS) return;
        this.seats.push({
          seat: this.seats.length, name: "侠影·" + "甲乙丙丁"[this.seats.length % 4],
          isBot: true, token: "", ws: null, connected: true,
        });
        this._broadcastLobby();
        break;
      case "remove_bot": {
        if (this._hostSeat() !== seat || this.mode !== "lobby") return;
        const i = this.seats.findLastIndex(s => s.isBot);
        if (i >= 0) { this.seats.splice(i, 1); this.seats.forEach((s, j) => s.seat = j); }
        this._broadcastLobby();
        break;
      }
      case "start":
        if (this._hostSeat() !== seat || this.mode !== "lobby") return;
        if (!this._canStart()) return;
        this._startGame(m.skills !== false);
        break;
      case "action":
        if (this.mode !== "playing" || !this.game) return;
        if (!m.action || m.action.pid !== seat.seat) return;   // 只能替自己行动
        this._applyAndBroadcast(m.action);
        break;
      case "rematch":
        if (this._hostSeat() !== seat || this.mode !== "over") return;
        this.mode = "lobby";
        this.game = null;
        this._broadcastLobby();
        break;
    }
  }

  // ---------- 等待厅 ----------
  _hostSeat() { return this.seats.find(s => !s.isBot && s.connected) || null; }
  _canStart() {
    return this.seats.length >= R.MIN_PLAYERS && this.seats.length <= MAX_SEATS
      && this._hostSeat() !== null;
  }

  _broadcastLobby() {
    const host = this._hostSeat();
    const pack = {
      t: "lobby",
      room: this.roomCode,
      mode: this.mode,
      seats: this.seats.map(s => ({
        seat: s.seat, name: s.name, is_bot: s.isBot, connected: s.connected,
      })),
      host: host ? host.seat : -1,
      can_start: this._canStart(),
      min_players: R.MIN_PLAYERS, max_players: MAX_SEATS,
    };
    for (const s of this.seats) this._send(s, pack);
  }

  // ---------- 开局与推进 ----------
  _startGame(skillsEnabled) {
    this.mode = "playing";
    const seed = (Date.now() ^ (Math.random() * 0x7fffffff)) >>> 0;
    this.game = new Game(seed, skillsEnabled);
    const evs = this.game.newGame(this.seats.map(s => s.name), this.seats.map(s => s.isBot));
    this._broadcastLobby();
    this._pushGameAll(evs);
    this._armPhaseTimers();
    this._maybeBotAct();
  }

  _applyAndBroadcast(action) {
    const evs = this.game.apply(action);
    // REJECTED 只回给动作发起者，不广播
    if (evs.length === 1 && evs[0].type === "REJECTED") {
      const s = this.seats[action.pid];
      if (s) this._send(s, { t: "rejected", reason: evs[0].reason, action });
      return;
    }
    this._pushGameAll(evs);
    if (this.game.phase === R.Phase.GAME_OVER) {
      this.mode = "over";
      this._clearTimers();
      this._broadcastLobby();
      return;
    }
    this._armPhaseTimers();
    this._maybeBotAct();
  }

  _pushGameAll(evs) {
    for (const s of this.seats) this._pushGameTo(s, evs);
  }
  _pushGameTo(s, evs) {
    if (s.isBot || !s.ws) return;
    this._send(s, {
      t: "game",
      view: this.game.viewFor(s.seat),
      events: evs,
      turn_deadline: this.turnDeadline,
      server_now: Date.now(),
    });
  }

  // ---------- 计时（铁律 5：时间全在驱动层 = 本 DO）----------
  _clearTimers() {
    for (const k of Object.keys(this.timers)) {
      if (this.timers[k]) { clearTimeout(this.timers[k]); this.timers[k] = null; }
    }
  }

  _armPhaseTimers() {
    this._clearTimers();
    const g = this.game;
    if (g.phase === R.Phase.SKILL_PICK) {
      this.turnDeadline = Date.now() + R.SKILL_PICK_MS;
      this.timers.pick = setTimeout(() => {
        const evs = g.forceResolveSkillPick();
        this._pushGameAll(evs);
        this._armPhaseTimers();
        this._maybeBotAct();
      }, R.SKILL_PICK_MS);
      // 机器人立刻随机选
      for (const s of this.seats)
        if (s.isBot) g.apply({ type: "PICK_SKILL", pid: s.seat, skill: this.driverRng.randiRange(0, 5) });
      if (g.phase !== R.Phase.SKILL_PICK) {  // 全是机器人时可能已裁决
        this._pushGameAll([]);
        this._armPhaseTimers();
      }
      return;
    }
    if (g.phase === R.Phase.SWAP_WINDOW) {
      this.turnDeadline = Date.now() + R.SWAP_WINDOW_MS;
      this.timers.swap = setTimeout(() => {
        const evs = g.apply({ type: "PASS_WINDOW" });
        this._pushGameAll(evs);
        this._armPhaseTimers();
        this._maybeBotAct();
      }, R.SWAP_WINDOW_MS);
      return;
    }
    if (g.phase === R.Phase.PLAY) {
      this.turnDeadline = Date.now() + R.PLAY_TIMEOUT_MS;
      this.timers.turn = setTimeout(() => this._timeoutPlay(), R.PLAY_TIMEOUT_MS);
    }
  }

  _timeoutPlay() {
    const g = this.game;
    if (!g || g.phase !== R.Phase.PLAY) return;
    const p = g.players[g.currentPlayer];
    if (p.hand.length > 0) {
      const idx = this.driverRng.randiRange(0, p.hand.length - 1);
      this._applyAndBroadcast({ type: "PLAY", pid: p.id, indices: [idx] });
    }
  }

  _maybeBotAct() {
    const g = this.game;
    if (!g || this.mode !== "playing") return;
    if (g.phase === R.Phase.SWAP_WINDOW) {
      const holder = g.players.find(p => p.alive && p.skill === R.Skill.GAIXIAN && p.skillUsesLeft > 0);
      const hs = holder ? this.seats[holder.id] : null;
      const botHolder = hs && (hs.isBot || !hs.connected);
      if (!holder || botHolder) {
        if (this.timers.bot) clearTimeout(this.timers.bot);
        this.timers.bot = setTimeout(() => {
          if (g.phase !== R.Phase.SWAP_WINDOW) return;
          const act = holder ? botDecide(g.viewFor(holder.id), this.driverRng) : { type: "PASS_WINDOW" };
          this._applyAndBroadcast(act.type === "USE_GAIXIAN" ? act : { type: "PASS_WINDOW" });
        }, 1200);
      }
      return;
    }
    if (g.phase !== R.Phase.PLAY) return;
    const cp = g.currentPlayer;
    if (cp < 0) return;
    const s = this.seats[cp];
    const isBotTurn = s && (s.isBot || !s.connected);   // 掉线托管（边界 17）
    if (!isBotTurn) return;
    if (this.timers.bot) clearTimeout(this.timers.bot);
    const think = this.driverRng.randiRange(R.BOT_THINK_MIN_MS, R.BOT_THINK_MAX_MS);
    this.timers.bot = setTimeout(() => {
      if (g.phase !== R.Phase.PLAY || g.currentPlayer !== cp) return;
      this._applyAndBroadcast(botDecide(g.viewFor(cp), this.driverRng));
    }, think);
  }

  _send(seat, obj) {
    if (seat.isBot || !seat.ws) return;
    try { seat.ws.send(JSON.stringify(obj)); } catch {}
  }
}
