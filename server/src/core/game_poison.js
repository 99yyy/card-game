// 「递毒」模式内核（五毒/蟑螂扑克）—— core/game_poison.gd 的镜像。
import * as R from "./rules.js";
import { Rng } from "./rng.js";

export class GamePoison {
  constructor(seed) {
    this.rng = new Rng(seed);
    this.phase = R.Phase.SKILL_PICK;
    this.roundNumber = 0;
    this.currentPlayer = -1;
    this.winner = -1;
    this.offerActive = false;
    this.offerCard = -1;
    this.offerClaim = -1;
    this.offerFrom = -1;
    this.offerTo = -1;
    this.offerSeen = [];
    this.players = [];
    this._ev = [];
  }

  newGame(names, isBot) {
    this._ev = [];
    const n = names.length;
    if (n < R.MIN_PLAYERS || n > R.MAX_PLAYERS) return this._ev;
    this.players = names.map((name, i) => ({
      id: i, name, isBot: !!isBot[i], alive: true,
      hand: [], collected: [0, 0, 0, 0, 0], charId: i, ready: !!isBot[i],
    }));
    const deck = [];
    for (let k = 0; k < R.POISON_KINDS; k++)
      for (let j = 0; j < R.POISON_PER_KIND; j++) deck.push(k);
    for (let i = deck.length - 1; i > 0; i--) {
      const j = this.rng.randiRange(0, i);
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    deck.forEach((c, i) => this.players[i % n].hand.push(c));
    this.currentPlayer = this.rng.randiRange(0, n - 1);
    return this._ev;
  }

  aliveCount() { return this.players.filter(p => p.alive).length; }

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
          if (this.players.every(q => !q.alive || q.ready)) {
            this.phase = R.Phase.PLAY;
            this._emit({ type: "POISON_START", starter: this.currentPlayer });
          }
        } else this._emit({ type: "REJECTED", reason: "wrong_phase", action: a });
        break;
      case "OFFER": this._doOffer(a, p); break;
      case "RESPOND": this._doRespond(a, p); break;
      case "PASS_ON": this._doPassOn(a, p); break;
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
      this.phase = R.Phase.PLAY;
      this._emit({ type: "POISON_START", starter: this.currentPlayer });
    }
    return this._ev;
  }

  _doOffer(a, p) {
    const idx = a.card_index ?? -1, target = a.target ?? -1, claim = a.claim ?? -1;
    if (this.phase !== R.Phase.PLAY || this.offerActive || p.id !== this.currentPlayer) {
      this._emit({ type: "REJECTED", reason: "wrong_phase", action: a }); return;
    }
    if (idx < 0 || idx >= p.hand.length || claim < 0 || claim >= R.POISON_KINDS
        || target < 0 || target >= this.players.length || target === p.id
        || !this.players[target].alive) {
      this._emit({ type: "REJECTED", reason: "bad_offer", action: a }); return;
    }
    this.offerActive = true;
    this.offerCard = p.hand.splice(idx, 1)[0];
    this.offerClaim = claim;
    this.offerFrom = p.id;
    this.offerTo = target;
    this.offerSeen = [p.id];
    this.currentPlayer = target;
    this.roundNumber += 1;
    this._emit({ type: "OFFER_MADE", from: p.id, to: target, claim });
  }

  _doRespond(a, p) {
    if (this.phase !== R.Phase.PLAY || !this.offerActive || p.id !== this.offerTo) {
      this._emit({ type: "REJECTED", reason: "not_receiver", action: a }); return;
    }
    const guessTrue = !!a.guess;
    const isTrue = this.offerCard === this.offerClaim;
    const correct = (guessTrue && isTrue) || (!guessTrue && !isTrue);
    const eater = correct ? this.players[this.offerFrom] : p;
    this._emit({ type: "OFFER_REVEALED", card: this.offerCard, claim: this.offerClaim,
      from: this.offerFrom, to: p.id, guess: guessTrue, eater: eater.id });
    this._eat(eater, this.offerCard);
  }

  _doPassOn(a, p) {
    if (this.phase !== R.Phase.PLAY || !this.offerActive || p.id !== this.offerTo) {
      this._emit({ type: "REJECTED", reason: "not_receiver", action: a }); return;
    }
    const claim = a.claim ?? -1, target = a.target ?? -1;
    if (claim < 0 || claim >= R.POISON_KINDS) {
      this._emit({ type: "REJECTED", reason: "bad_claim", action: a }); return;
    }
    if (target < 0 || target >= this.players.length || !this.players[target].alive
        || this.offerSeen.includes(target) || target === p.id) {
      this._emit({ type: "REJECTED", reason: "bad_target", action: a }); return;
    }
    this.offerSeen.push(p.id);
    this.offerClaim = claim;
    this.offerFrom = p.id;
    this.offerTo = target;
    this.currentPlayer = target;
    this._emit({ type: "PASSED_ON", from: p.id, to: target, claim });
  }

  _canPassOn(pid) {
    return this.players.some(q => q.alive && q.id !== pid && !this.offerSeen.includes(q.id));
  }

  _eat(eater, kind) {
    eater.collected[kind] += 1;
    this._emit({ type: "POISON_EATEN", pid: eater.id, kind, count: eater.collected[kind] });
    this.offerActive = false;
    this.offerCard = -1;
    if (eater.collected[kind] >= R.POISON_DEATH) {
      eater.alive = false;
      this._emit({ type: "POISONED_OUT", pid: eater.id });
      if (this.aliveCount() === 1) {
        this.winner = this.players.find(q => q.alive).id;
        this.phase = R.Phase.GAME_OVER;
        this._emit({ type: "GAME_OVER", winner: this.winner });
        return;
      }
    }
    let nxt = eater.id;
    if (!eater.alive || eater.hand.length === 0) nxt = this._nextWithHand(eater.id);
    if (nxt === -1) { this._finishByExhaustion(); return; }
    this.currentPlayer = nxt;
  }

  _nextWithHand(fromId) {
    const n = this.players.length;
    for (let i = 0; i < n; i++) {
      const cand = (fromId + 1 + i) % n;
      const q = this.players[cand];
      if (q.alive && q.hand.length > 0) return cand;
    }
    return -1;
  }

  _finishByExhaustion() {
    let best = -1, bestTotal = Infinity;
    for (const q of this.players) {
      if (!q.alive) continue;
      const tot = q.collected.reduce((a, b) => a + b, 0);
      if (tot < bestTotal) { bestTotal = tot; best = q.id; }
    }
    this.winner = best;
    this.phase = R.Phase.GAME_OVER;
    this._emit({ type: "GAME_OVER", winner: this.winner });
  }

  _emit(e) { this._ev.push(e); }

  legalActions(pid) {
    const out = [];
    const p = this.players[pid];
    if (this.phase === R.Phase.SKILL_PICK) { out.push({ type: "READY", pid }); return out; }
    if (this.phase !== R.Phase.PLAY || !p.alive) return out;
    if (this.offerActive && pid === this.offerTo) {
      out.push({ type: "RESPOND", pid, guess: true });
      out.push({ type: "RESPOND", pid, guess: false });
      if (this._canPassOn(pid)) out.push({ type: "PASS_ON", pid });
    } else if (!this.offerActive && pid === this.currentPlayer && p.hand.length > 0) {
      out.push({ type: "OFFER", pid });
    }
    return out;
  }

  viewFor(pid) {
    const me = this.players[pid];
    const peeked = this.offerActive && pid === this.offerTo ? this.offerCard : -1;
    return {
      mode: R.Mode.DIDU,
      you: {
        id: me.id, hand: [...me.hand], alive: me.alive,
        collected: [...me.collected], char_id: me.charId, ready: me.ready,
        steps_taken: 0, has_gap: false, peeked,
        skill: -1, skill_uses_left: 0, houfa_ready_round: 0,
        probe_result: {}, listen_result: {}, pending_skill_pick: 0,
      },
      players: this.players.map(p => ({
        id: p.id, name: p.name, is_bot: p.isBot, alive: p.alive,
        hand_count: p.hand.length, collected: [...p.collected],
        char_id: p.charId, ready: p.ready, steps_taken: 0, has_gap: false,
        skill: -1, skill_uses_left: 0, houfa_ready_round: 0, golden_bell_used: false,
      })),
      phase: this.phase, round_number: this.roundNumber,
      current_player: this.currentPlayer, round_starter: this.currentPlayer,
      offer_active: this.offerActive, offer_claim: this.offerClaim,
      offer_from: this.offerFrom, offer_to: this.offerTo,
      offer_seen: [...this.offerSeen],
      alive_count: this.aliveCount(), winner: this.winner,
      skills_enabled: false, current_suit: -1, suit_changed_by: -1,
      last_player_who_played: -1, last_played_count: 0,
      discard_count: 0, deck_remaining: 0,
      legal_actions: this.legalActions(pid),
    };
  }
}

export function poisonBotDecide(view, rng) {
  const me = view.you;
  if (view.phase === R.Phase.SKILL_PICK) return { type: "READY", pid: me.id };
  if (view.offer_active && view.offer_to === me.id) {
    const claim = view.offer_claim;
    if (me.collected[claim] >= 2 && rng.randf() < 0.5 && view.offer_seen.length < view.alive_count) {
      const targets = view.players.filter(q =>
        q.alive && q.id !== me.id && !view.offer_seen.includes(q.id)).map(q => q.id);
      if (targets.length > 0) {
        const lie = rng.randf() < 0.5;
        const c2 = lie ? rng.randiRange(0, 4) : me.peeked;
        return { type: "PASS_ON", pid: me.id, claim: c2,
          target: targets[rng.randiRange(0, targets.length - 1)] };
      }
    }
    return { type: "RESPOND", pid: me.id, guess: rng.randf() < 0.42 };
  }
  const idx = rng.randiRange(0, me.hand.length - 1);
  const card = me.hand[idx];
  const claim = rng.randf() < 0.45 ? rng.randiRange(0, 4) : card;
  let bestT = -1, bestDanger = -1;
  for (const q of view.players) {
    if (!q.alive || q.id === me.id) continue;
    const danger = Math.max(...q.collected);
    if (danger > bestDanger) { bestDanger = danger; bestT = q.id; }
  }
  return { type: "OFFER", pid: me.id, card_index: idx, target: bestT, claim };
}
