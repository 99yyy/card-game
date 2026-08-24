// 「暗器」模式内核（大话骰）—— core/game_dice.gd 的镜像。
import * as R from "./rules.js";
import { Rng } from "./rng.js";

export class GameDice {
  constructor(seed) {
    this.rng = new Rng(seed);
    this.phase = R.Phase.SKILL_PICK;
    this.roundNumber = 0;
    this.currentPlayer = -1;
    this.roundStarter = -1;
    this.winner = -1;
    this.bidN = 0; this.bidFace = -1; this.bidBy = -1;
    this.players = [];
    this._ev = [];
  }

  newGame(names, isBot) {
    this._ev = [];
    const n = names.length;
    if (n < R.MIN_PLAYERS || n > R.MAX_PLAYERS) return this._ev;
    this.players = names.map((name, i) => ({
      id: i, name, isBot: !!isBot[i], alive: true, dice: [],
      stepsTaken: 0, hollowIndex: this.rng.randiRange(1, R.STONES),
      hasGap: false, charId: i, ready: !!isBot[i],
    }));
    this.roundStarter = this.rng.randiRange(0, n - 1);
    return this._ev;
  }

  aliveCount() { return this.players.filter(p => p.alive).length; }
  _totalDice() { return this.players.reduce((s, p) => s + (p.alive ? p.dice.length : 0), 0); }

  apply(action) {
    this._ev = [];
    const a = JSON.parse(JSON.stringify(action));
    const t = a.type || "";
    const pid = a.pid ?? -1;
    if (t === "PASS_WINDOW") return this._ev;
    if (pid < 0 || pid >= this.players.length) {
      this._emit({ type: "REJECTED", reason: "bad_pid", action: a }); return this._ev;
    }
    const p = this.players[pid];
    switch (t) {
      case "PICK_CHAR": {
        const c = a.char_id ?? -1;
        if (this.phase === R.Phase.SKILL_PICK && c >= 0 && c <= 5) p.charId = c;
        else this._emit({ type: "REJECTED", reason: "wrong_phase", action: a });
        break;
      }
      case "READY":
        if (this.phase === R.Phase.SKILL_PICK) {
          p.ready = true;
          if (this.players.every(q => !q.alive || q.ready)) this._startRound();
        } else this._emit({ type: "REJECTED", reason: "wrong_phase", action: a });
        break;
      case "BID": {
        const n = a.n ?? 0, face = a.face ?? -1;
        if (!this._bidLegal(pid, n, face)) {
          this._emit({ type: "REJECTED", reason: "must_raise", action: a }); break;
        }
        this.bidN = n; this.bidFace = face; this.bidBy = pid;
        this._emit({ type: "BID", pid, n, face });
        this.currentPlayer = this._nextAlive(pid);
        break;
      }
      case "CHALLENGE":
        if (this.phase !== R.Phase.PLAY || pid !== this.currentPlayer
            || this.bidBy === -1 || this.bidBy === pid) {
          this._emit({ type: "REJECTED", reason: "no_bid", action: a }); break;
        }
        this._resolveChallenge(pid);
        break;
      case "EMOTE":
        if (p.alive) this._emit({ type: "EMOTE", pid, emote: a.emote ?? 0 });
        break;
      default:
        this._emit({ type: "REJECTED", reason: "illegal", action: a });
    }
    return this._ev;
  }

  forceResolveSkillPick() {
    this._ev = [];
    if (this.phase === R.Phase.SKILL_PICK) {
      for (const p of this.players) p.ready = true;
      this._startRound();
    }
    return this._ev;
  }

  _bidLegal(pid, n, face) {
    if (this.phase !== R.Phase.PLAY || pid !== this.currentPlayer) return false;
    if (!R.DICE_BIDDABLE.includes(face)) return false;
    if (n < 1 || n > this._totalDice()) return false;
    if (this.bidBy === -1) return true;
    return n > this.bidN || (n === this.bidN && face > this.bidFace);
  }

  _startRound() {
    this.roundNumber += 1;
    this.bidN = 0; this.bidFace = -1; this.bidBy = -1;
    this.phase = R.Phase.PLAY;
    const counts = {};
    for (const p of this.players) {
      if (!p.alive) continue;
      const n = Math.max(R.DICE_START - p.stepsTaken, 1);
      p.dice = Array.from({ length: n }, () => this.rng.randiRange(0, 5));
      counts[p.id] = n;
    }
    this.currentPlayer = this.roundStarter;
    this._emit({ type: "DICE_ROUND_START", round: this.roundNumber, starter: this.roundStarter, counts });
  }

  _resolveChallenge(challengerId) {
    let count = 0;
    const allDice = {};
    for (const p of this.players) if (p.alive) {
      allDice[String(p.id)] = [...p.dice];
      for (const d of p.dice) if (d === this.bidFace || d === R.DICE_WILD) count++;
    }
    const stands = count >= this.bidN;
    this._emit({ type: "DICE_CHALLENGE", by: challengerId, target: this.bidBy });
    this._emit({ type: "DICE_REVEALED", all_dice: allDice, count, bid_n: this.bidN, bid_face: this.bidFace, stands });
    const loser = stands ? this.players[challengerId] : this.players[this.bidBy];
    this._retreat(loser, 1);
    this._endRound(loser.id);
  }

  _retreat(p, steps) {
    for (let i = 0; i < steps; i++) {
      if (!p.alive) return;
      if (p.hasGap) { p.alive = false; this._emit({ type: "FALL", pid: p.id }); return; }
      const from = p.stepsTaken;
      p.stepsTaken += 1;
      this._emit({ type: "RETREAT", pid: p.id, from_step: from, to_step: p.stepsTaken });
      if (p.stepsTaken === p.hollowIndex) {
        p.alive = false; this._emit({ type: "FALL", pid: p.id }); return;
      }
    }
  }

  _endRound(retreaterId) {
    const r = this.players[retreaterId];
    this.roundStarter = r.alive ? r.id : this._nextAlive(r.id);
    this._emit({ type: "ROUND_END", retreater: retreaterId });
    if (this.aliveCount() === 1) {
      this.winner = this.players.find(p => p.alive).id;
      this.phase = R.Phase.GAME_OVER;
      this._emit({ type: "GAME_OVER", winner: this.winner });
      return;
    }
    this._startRound();
  }

  _nextAlive(fromId) {
    const n = this.players.length;
    for (let i = 1; i <= n; i++) {
      const cand = (fromId + i) % n;
      if (this.players[cand].alive) return cand;
    }
    return fromId;
  }

  _emit(e) { this._ev.push(e); }

  legalActions(pid) {
    const out = [];
    if (this.phase === R.Phase.SKILL_PICK) { out.push({ type: "READY", pid }); return out; }
    if (this.phase === R.Phase.PLAY && pid === this.currentPlayer) {
      if (this.bidBy !== -1 && this.bidBy !== pid) out.push({ type: "CHALLENGE", pid });
      if (this.bidBy === -1) out.push({ type: "BID", pid, n: 1, face: 0 });
      else if (this.bidFace < 4) out.push({ type: "BID", pid, n: this.bidN, face: this.bidFace + 1 });
      else if (this.bidN < this._totalDice()) out.push({ type: "BID", pid, n: this.bidN + 1, face: 0 });
    }
    return out;
  }

  viewFor(pid) {
    const me = this.players[pid];
    return {
      mode: R.Mode.ANQI,
      you: {
        id: me.id, dice: [...me.dice], hand: [], steps_taken: me.stepsTaken,
        has_gap: me.hasGap, alive: me.alive, char_id: me.charId, ready: me.ready,
        skill: -1, skill_uses_left: 0, houfa_ready_round: 0,
        probe_result: {}, listen_result: {}, pending_skill_pick: 0,
      },
      players: this.players.map(p => ({
        id: p.id, name: p.name, is_bot: p.isBot, alive: p.alive,
        hand_count: p.dice.length, steps_taken: p.stepsTaken, has_gap: p.hasGap,
        char_id: p.charId, ready: p.ready,
        skill: -1, skill_uses_left: 0, houfa_ready_round: 0, golden_bell_used: false,
      })),
      phase: this.phase, round_number: this.roundNumber,
      current_player: this.currentPlayer, round_starter: this.roundStarter,
      bid_n: this.bidN, bid_face: this.bidFace, bid_by: this.bidBy,
      total_dice: this._totalDice(),
      alive_count: this.aliveCount(), winner: this.winner,
      skills_enabled: false, current_suit: -1, suit_changed_by: -1,
      last_player_who_played: -1, last_played_count: 0,
      discard_count: 0, deck_remaining: 0,
      legal_actions: this.legalActions(pid),
    };
  }
}

export function diceBotDecide(view, rng) {
  const me = view.you;
  if (view.phase === R.Phase.SKILL_PICK) return { type: "READY", pid: me.id };
  const total = view.total_dice;
  const others = total - me.dice.length;
  if (view.bid_by !== -1 && view.bid_by !== me.id) {
    let mine = 0;
    for (const d of me.dice) if (d === view.bid_face || d === R.DICE_WILD) mine++;
    const expect = mine + others / 3;
    const over = view.bid_n - expect;
    const pch = Math.min(Math.max(0.18 + over * 0.32, 0.05), 0.92);
    if (rng.randf() < pch) return { type: "CHALLENGE", pid: me.id };
  }
  let bestFace = 0, bestCnt = -1;
  for (const f of R.DICE_BIDDABLE) {
    let c = 0;
    for (const d of me.dice) if (d === f || d === R.DICE_WILD) c++;
    if (c > bestCnt) { bestCnt = c; bestFace = f; }
  }
  let n, face;
  if (view.bid_by === -1) { n = Math.max(1, bestCnt); face = bestFace; }
  else if (bestFace > view.bid_face) { n = view.bid_n; face = bestFace; }
  else if (view.bid_face < 4) { n = view.bid_n; face = view.bid_face + 1; }
  else { n = view.bid_n + 1; face = bestFace; }
  if (n > total) return { type: "CHALLENGE", pid: me.id };
  return { type: "BID", pid: me.id, n, face };
}
