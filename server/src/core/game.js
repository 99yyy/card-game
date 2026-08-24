// 《绝顶》内核 —— core/game_state.gd 的逐函数移植。
// 规则唯一权威：docs/规则草案.md（v0.8，33 条边界）。
// 服务端权威五机密（§15）：hollow_index / 他人 hand / last_played_cards /
// 他人 probe_result / 他人 listen_result —— 只存在于内核，viewFor 按人裁剪。
import * as R from "./rules.js";
import { Rng } from "./rng.js";

export class Game {
  constructor(seed, skillsEnabled = true) {
    this.rng = new Rng(seed);
    this.seed = seed;
    this.skillsEnabled = skillsEnabled;
    this.phase = R.Phase.SKILL_PICK;
    this.roundNumber = 0;
    this.currentSuit = -1;
    this.suitChangedBy = -1;
    this.currentPlayer = -1;
    this.roundStarter = -1;
    this.lastPlayerWhoPlayed = -1;
    this.lastPlayedCards = [];
    this.discardCount = 0;
    this.deckRemaining = 0;
    this.winner = -1;
    this.players = [];
    this._ev = [];
  }

  newGame(names, isBot) {
    this._ev = [];
    const n = names.length;
    if (n < R.MIN_PLAYERS || n > R.MAX_PLAYERS) return this._ev; // §7.3：非法不崩
    this.players = names.map((name, i) => ({
      id: i, name, isBot: !!isBot[i], alive: true, hand: [],
      skill: R.Skill.NONE, skillUsesLeft: 0, houfaReadyRound: 0,
      stepsTaken: 0, hollowIndex: 0, hasGap: false, goldenBellUsed: false,
      probeResult: {}, listenResult: {}, pendingSkillPick: R.Skill.NONE,
      charId: i,   // 皮囊（立绘），报门户阶段可自选，纯外观
    }));
    for (const p of this.players) p.hollowIndex = this.rng.randiRange(1, R.STONES);
    this.roundStarter = this.rng.randiRange(0, n - 1);
    if (this.skillsEnabled) this.phase = R.Phase.SKILL_PICK;
    else this._startRound();
    return this._ev;
  }

  aliveCount() { return this.players.filter(p => p.alive).length; }

  // ---------- 动作入口 ----------
  apply(action) {
    this._ev = [];
    const a = JSON.parse(JSON.stringify(action));
    const t = a.type || "";
    if (t === "PASS_WINDOW") {           // 驱动层窗口推进，非玩家动作
      if (this.phase === R.Phase.SWAP_WINDOW) this.phase = R.Phase.PLAY;
      return this._ev;
    }
    if (!this._isLegal(a)) {
      this._emit({ type: "REJECTED", reason: this._rejectReason(a), action: a });
      return this._ev;
    }
    const p = this.players[a.pid];
    switch (t) {
      case "PICK_CHAR": p.charId = a.char_id; break;
      case "PICK_SKILL": p.pendingSkillPick = a.skill; break;
      case "USE_GAIXIAN": {
        p.skillUsesLeft -= 1;
        const frm = this.currentSuit;
        this.currentSuit = a.suit;
        this.suitChangedBy = a.pid;
        this._emit({ type: "SUIT_CHANGED", by: a.pid, from: frm, to: this.currentSuit });
        break;
      }
      case "USE_TINGJIN":
        p.skillUsesLeft -= 1;
        p.listenResult[String(this.roundNumber)] = this.lastPlayedCards[a.card_pos];
        this._emit({ type: "SKILL_USED", pid: a.pid, skill: R.Skill.TINGJIN });
        break;
      case "USE_BIANXUSHI":
        p.skillUsesLeft -= 1;
        p.probeResult[String(a.stone)] = a.stone === p.hollowIndex;
        this._emit({ type: "SKILL_USED", pid: a.pid, skill: R.Skill.BIANXUSHI });
        break;
      case "PLAY": this._doPlay(a); break;
      case "CHALLENGE": this._doChallenge(a); break;
      case "EMOTE": this._emit({ type: "EMOTE", pid: a.pid, emote: a.emote }); break;
    }
    if (this.phase === R.Phase.SKILL_PICK && this._allPicked()) this._resolveSkillPick();
    return this._ev;
  }

  forceResolveSkillPick() {              // 超时收尾（规则 §3.5）
    this._ev = [];
    if (this.phase === R.Phase.SKILL_PICK) this._resolveSkillPick();
    return this._ev;
  }

  // ---------- 合法性（唯一判定）----------
  _isLegal(a) {
    const t = a.type || "";
    const pid = a.pid ?? -1;
    if (pid < 0 || pid >= this.players.length) return false;
    const p = this.players[pid];
    switch (t) {
      case "PICK_CHAR": {
        const c = a.char_id ?? -1;
        return this.phase === R.Phase.SKILL_PICK && c >= 0 && c <= 5;
      }
      case "PICK_SKILL":
        return this.skillsEnabled && this.phase === R.Phase.SKILL_PICK
          && p.pendingSkillPick === R.Skill.NONE && R.ALL_SKILLS.includes(a.skill ?? R.Skill.NONE);
      case "USE_GAIXIAN":
        return this.skillsEnabled && this.phase === R.Phase.SWAP_WINDOW
          && p.skill === R.Skill.GAIXIAN && p.skillUsesLeft > 0
          && R.PLAYABLE_SUITS.includes(a.suit ?? -1) && p.alive;
      case "USE_TINGJIN":
        return this.skillsEnabled && this.phase === R.Phase.PLAY && pid === this.currentPlayer
          && p.skill === R.Skill.TINGJIN && p.skillUsesLeft > 0
          && this.lastPlayerWhoPlayed !== -1 && this.lastPlayerWhoPlayed !== pid
          && (a.card_pos ?? -1) >= 0 && (a.card_pos ?? -1) < this.lastPlayedCards.length;
      case "USE_BIANXUSHI": {
        const s = a.stone ?? 0;
        return this.skillsEnabled && this.phase === R.Phase.PLAY && pid === this.currentPlayer
          && p.skill === R.Skill.BIANXUSHI && p.skillUsesLeft > 0
          && s >= 1 && s <= R.STONES && s > p.stepsTaken;
      }
      case "PLAY": {
        if (this.phase !== R.Phase.PLAY || pid !== this.currentPlayer) return false;
        const idx = a.indices || [];
        if (idx.length < 1 || idx.length > R.MAX_PLAY_CARDS) return false;
        const seen = new Set();
        for (const i of idx) {
          if (!Number.isInteger(i) || i < 0 || i >= p.hand.length || seen.has(i)) return false;
          seen.add(i);
        }
        return true;
      }
      case "CHALLENGE":
        return this.phase === R.Phase.PLAY && pid === this.currentPlayer
          && this.lastPlayerWhoPlayed !== -1 && this.lastPlayerWhoPlayed !== pid;
      case "EMOTE":
        return p.alive;
    }
    return false;
  }

  _rejectReason(a) {
    const t = a.type || "";
    const pid = a.pid ?? -1;
    if (pid < 0 || pid >= this.players.length) return "bad_pid";
    const p = this.players[pid];
    switch (t) {
      case "PICK_CHAR":
        if (this.phase !== R.Phase.SKILL_PICK) return "wrong_phase";
        return "bad_char";
      case "PICK_SKILL":
        if (!this.skillsEnabled) return "skills_off";
        if (this.phase !== R.Phase.SKILL_PICK) return "wrong_phase";
        if (p.pendingSkillPick !== R.Skill.NONE) return "already_picked";
        return "bad_skill";
      case "USE_GAIXIAN":
        if (!this.skillsEnabled) return "skills_off";
        if (this.phase !== R.Phase.SWAP_WINDOW) return "wrong_phase";
        if (p.skill !== R.Skill.GAIXIAN) return "no_skill";
        if (p.skillUsesLeft <= 0) return "no_uses";
        if (!p.alive) return "dead";
        return "bad_suit";
      case "USE_TINGJIN":
        if (!this.skillsEnabled) return "skills_off";
        if (this.phase !== R.Phase.PLAY) return "wrong_phase";
        if (pid !== this.currentPlayer) return "not_your_turn";
        if (p.skill !== R.Skill.TINGJIN) return "no_skill";
        if (p.skillUsesLeft <= 0) return "no_uses";
        if (this.lastPlayerWhoPlayed === -1) return "no_last_play";
        if (this.lastPlayerWhoPlayed === pid) return "self_is_last";
        return "bad_card_pos";
      case "USE_BIANXUSHI": {
        if (!this.skillsEnabled) return "skills_off";
        if (this.phase !== R.Phase.PLAY) return "wrong_phase";
        if (pid !== this.currentPlayer) return "not_your_turn";
        if (p.skill !== R.Skill.BIANXUSHI) return "no_skill";
        if (p.skillUsesLeft <= 0) return "no_uses";
        const s = a.stone ?? 0;
        if (s < 1 || s > R.STONES) return "bad_stone";
        return "already_stepped";
      }
      case "PLAY": {
        if (this.phase !== R.Phase.PLAY) return "wrong_phase";
        if (pid !== this.currentPlayer) return "not_your_turn";
        const idx = a.indices || [];
        if (idx.length < 1 || idx.length > R.MAX_PLAY_CARDS) return "bad_count";
        return "bad_indices";
      }
      case "CHALLENGE":
        if (this.phase !== R.Phase.PLAY) return "wrong_phase";
        if (pid !== this.currentPlayer) return "not_your_turn";
        if (this.lastPlayerWhoPlayed === -1) return "no_last_play";
        return "self_is_last";
      case "EMOTE": return "dead";
    }
    return "illegal";
  }

  // ---------- 阶段推进 ----------
  _allPicked() {
    return this.players.every(p => !p.alive || p.pendingSkillPick !== R.Skill.NONE);
  }

  _startRound() {
    this.roundNumber += 1;
    this.suitChangedBy = -1;
    this.currentSuit = R.PLAYABLE_SUITS[this.rng.randiRange(0, R.PLAYABLE_SUITS.length - 1)];
    const deck = R.buildDeck();
    this._shuffle(deck);                              // 边界 32：每轮全洗
    const alive = this.players.filter(p => p.alive);
    const counts = {};
    let k = 0;
    for (const p of alive) {
      p.hand = deck.slice(k, k + R.HAND_SIZE);
      counts[p.id] = p.hand.length;
      k += R.HAND_SIZE;
    }
    this.deckRemaining = R.DECK_SIZE - alive.length * R.HAND_SIZE;
    this.lastPlayerWhoPlayed = -1;
    this.lastPlayedCards = [];
    this.discardCount = 0;
    this.currentPlayer = this.roundStarter;
    let swapPending = false;
    if (this.skillsEnabled)
      swapPending = alive.some(p => p.skill === R.Skill.GAIXIAN && p.skillUsesLeft > 0);
    this.phase = swapPending ? R.Phase.SWAP_WINDOW : R.Phase.PLAY;
    this._emit({ type: "ROUND_START", round: this.roundNumber, suit: this.currentSuit, starter: this.roundStarter });
    this._emit({ type: "DEALT", counts });
  }

  // ---------- 出招 / 拆招 ----------
  _doPlay(a) {
    const p = this.players[a.pid];
    this.discardCount += this.lastPlayedCards.length;  // 边界 29
    const played = a.indices.map(i => p.hand[i]);
    const sorted = [...a.indices].sort((x, y) => x - y);
    for (let i = sorted.length - 1; i >= 0; i--) p.hand.splice(sorted[i], 1);
    this.lastPlayedCards = played;
    this.lastPlayerWhoPlayed = a.pid;
    this._emit({ type: "PLAYED", pid: a.pid, count: played.length });
    // 天道检验（边界 33）
    const othersHaveCards = this.players.some(q => q.alive && q.id !== a.pid && q.hand.length > 0);
    if (!othersHaveCards) {
      this._emit({ type: "HEAVEN_CHECK", pid: a.pid });
      const honest = this.lastPlayedCards.every(c => R.isTruthful(c, this.currentSuit));
      this._emit({ type: "REVEALED", pid: a.pid, cards: [...this.lastPlayedCards], suit: this.currentSuit, honest });
      if (honest) {
        this.discardCount += this.lastPlayedCards.length;
        this.lastPlayedCards = [];
        this.lastPlayerWhoPlayed = -1;
        if (p.hand.length === 0) this._endRound(-1);
        return;
      }
      this._retreat(p, 1);               // 天道拆穿不触发后发制人
      this._endRound(p.id);
      return;
    }
    if (!this._advanceTurn()) this._endRound(-1);
  }

  _doChallenge(a) {
    const target = this.players[this.lastPlayerWhoPlayed];
    this._emit({ type: "CHALLENGED", by: a.pid, target: target.id });
    this.phase = R.Phase.REVEAL;
    this._resolveReveal(a.pid, target);
  }

  _resolveReveal(challengerId, target) {
    const honest = this.lastPlayedCards.every(c => R.isTruthful(c, this.currentSuit));
    this._emit({ type: "REVEALED", pid: target.id, cards: [...this.lastPlayedCards], suit: this.currentSuit, honest });
    if (honest) {
      const victim = this.players[challengerId];
      if (this.skillsEnabled && target.skill === R.Skill.HOUFA && this.roundNumber >= target.houfaReadyRound) {
        target.houfaReadyRound = this.roundNumber + R.HOUFA_COOLDOWN_ROUNDS;
        this._emit({ type: "HOUFA_TRIGGERED", pid: target.id, victim: victim.id });
        this._retreat(victim, R.HOUFA_TOTAL_STEPS);
      } else {
        this._retreat(victim, 1);
      }
    } else {
      this._retreat(target, 1);
    }
    this._endRound(honest ? challengerId : target.id);  // 边界 27（含 v0.7 修复）
  }

  // ---------- 退步（唯一实现）----------
  _retreat(p, steps) {
    for (let i = 0; i < steps; i++) {
      if (!p.alive) return;
      if (p.hasGap) {                    // 豁口判定必须在 stepsTaken+1 之前
        p.alive = false;
        this._emit({ type: "FALL", pid: p.id });
        return;
      }
      const from = p.stepsTaken;
      p.stepsTaken += 1;
      this._emit({ type: "RETREAT", pid: p.id, from_step: from, to_step: p.stepsTaken });
      if (p.stepsTaken === p.hollowIndex) {
        if (this.skillsEnabled && p.skill === R.Skill.JINZHONGZHAO && !p.goldenBellUsed) {
          p.goldenBellUsed = true;
          p.skillUsesLeft = 0;
          p.hasGap = true;
          this._emit({ type: "GOLDEN_BELL", pid: p.id });
        } else {
          p.alive = false;
          this._emit({ type: "FALL", pid: p.id });
          return;
        }
      }
    }
  }

  _advanceTurn() {
    const n = this.players.length;
    for (let i = 1; i <= n; i++) {
      const cand = (this.currentPlayer + i) % n;
      const p = this.players[cand];
      if (p.alive && p.hand.length > 0) { this.currentPlayer = cand; return true; }
      if (p.alive && p.hand.length === 0 && cand !== this.currentPlayer)
        this._emit({ type: "SKIPPED", pid: cand, reason: "empty_hand" });
    }
    return false;
  }

  _endRound(retreaterId) {
    if (retreaterId === -1) this.roundStarter = this._nextAlive(this.roundStarter);
    else {
      const r = this.players[retreaterId];
      this.roundStarter = r.alive ? r.id : this._nextAlive(r.id);
    }
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

  // ---------- 技能裁决（键先排序再随机，保可复现）----------
  _resolveSkillPick() {
    // v0.9：技能自由选、可重复。选了什么就是什么；超时未选者随机分配。
    const assignments = {};
    const randomized = [];
    for (const p of this.players) {
      let s = p.pendingSkillPick;
      if (s === R.Skill.NONE) {
        s = R.ALL_SKILLS[this.rng.randiRange(0, R.ALL_SKILLS.length - 1)];
        randomized.push(p.id);
      }
      p.skill = s;
      p.skillUsesLeft = R.SKILL_USES[s];
      p.houfaReadyRound = 0;
      assignments[p.id] = s;
    }
    this._emit({ type: "SKILLS_ASSIGNED", assignments, randomized });
    this._startRound();
  }

  _shuffle(arr) {                        // Fisher–Yates，走内核 RNG
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.rng.randiRange(0, i);
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
  }

  _emit(e) { this._ev.push(e); }

  // ---------- 视图裁剪（铁律 3：五机密绝不下发）----------
  viewFor(pid) {
    const me = this.players[pid];
    return {
      you: {
        id: me.id, hand: [...me.hand], skill: me.skill, skill_uses_left: me.skillUsesLeft,
        houfa_ready_round: me.houfaReadyRound, steps_taken: me.stepsTaken,
        has_gap: me.hasGap, alive: me.alive,
        probe_result: { ...me.probeResult }, listen_result: { ...me.listenResult },
        pending_skill_pick: me.pendingSkillPick,
      },
      players: this.players.map(p => ({
        id: p.id, name: p.name, is_bot: p.isBot, alive: p.alive,
        hand_count: p.hand.length, skill: p.skill, skill_uses_left: p.skillUsesLeft,
        houfa_ready_round: p.houfaReadyRound, steps_taken: p.stepsTaken,
        has_gap: p.hasGap, golden_bell_used: p.goldenBellUsed,
        char_id: p.charId,
      })),
      phase: this.phase, round_number: this.roundNumber, current_suit: this.currentSuit,
      suit_changed_by: this.suitChangedBy, current_player: this.currentPlayer,
      round_starter: this.roundStarter, last_player_who_played: this.lastPlayerWhoPlayed,
      last_played_count: this.lastPlayedCards.length, discard_count: this.discardCount,
      deck_remaining: this.deckRemaining, alive_count: this.aliveCount(),
      winner: this.winner, skills_enabled: this.skillsEnabled,
      legal_actions: this.legalActions(pid),
    };
  }

  legalActions(pid) {
    const out = [];
    const tryA = a => { if (this._isLegal(a)) out.push(a); };
    if (this.phase === R.Phase.SKILL_PICK)
      for (const s of R.ALL_SKILLS) tryA({ type: "PICK_SKILL", pid, skill: s });
    if (this.phase === R.Phase.SWAP_WINDOW)
      for (const s of R.PLAYABLE_SUITS) tryA({ type: "USE_GAIXIAN", pid, suit: s });
    if (this.phase === R.Phase.PLAY && pid === this.currentPlayer) {
      const p = this.players[pid];
      if (p.hand.length > 0) tryA({ type: "PLAY", pid, indices: [0] });
      tryA({ type: "CHALLENGE", pid });
      for (let cp = 0; cp < this.lastPlayedCards.length; cp++)
        tryA({ type: "USE_TINGJIN", pid, card_pos: cp });
      for (let st = 1; st <= R.STONES; st++) tryA({ type: "USE_BIANXUSHI", pid, stone: st });
    }
    return out;
  }
}
