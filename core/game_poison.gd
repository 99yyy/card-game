class_name GamePoison
extends RefCounted

# 「递毒」模式内核（蟑螂扑克·五毒壳）。接口面与 GameState 一致。
#
# 规则（多玩法方案 §3.C）：
#   五毒各 8 张共 40 张全部发完（轮流发，允许不均）。
#   出手人盖一张递给指定的人并声称毒物种类（可撒谎）。
#   收礼人：信/不信 → 掀开判定，判错者吃下；或偷看后转赠（换声称，递给没看过的人）。
#   吃毒全场可见；同种集满 4 只毒发出局；只剩一人未毒发 → 胜。
#   全场手牌耗尽 → 吃毒总数最少者胜（罕见兜底，平手取座位序靠前）。
#
# 新机密类型：偷看过的牌只进当事人视图（服务端权威）。

var _seed: int = 0
var _rng: RandomNumberGenerator

var phase: int = Rules.Phase.SKILL_PICK
var round_number: int = 0                    # 递毒无"轮"概念，计"第几次递出"
var current_player: int = -1                 # 当前必须行动的人（出手人或收礼人）
var winner: int = -1

# 当前在途的毒盒
var offer_active: bool = false
var offer_card: int = -1                     # 机密：真实毒物
var offer_claim: int = -1                    # 公开：声称
var offer_from: int = -1                     # 公开：最近一手出手人
var offer_to: int = -1                       # 公开：当前收礼人
var offer_seen: Array = []                   # 公开：看过这张牌的人（含最初出手人）

var _players: Array = []
var _pending_events: Array = []


func _init(seed: int = 0, _skills: bool = false, _variant: bool = false) -> void:
	_seed = seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed


func new_game(names: Array, is_bot: Array) -> Array:
	_pending_events = []
	var n := names.size()
	if n < Rules.MIN_PLAYERS or n > Rules.MAX_PLAYERS:
		return _pending_events
	_players = []
	for i in n:
		_players.append({
			"id": i, "name": names[i], "is_bot": is_bot[i], "alive": true,
			"hand": [], "collected": [0, 0, 0, 0, 0],
			"char_id": i, "ready": is_bot[i],
		})
	# 40 张全发（轮流），允许 3 人局不均
	var deck := []
	for k in Rules.POISON_NAMES.size():
		for j in Rules.POISON_PER_KIND:
			deck.append(k)
	_shuffle(deck)
	var i2 := 0
	for c in deck:
		_players[i2 % n].hand.append(c)
		i2 += 1
	current_player = _rng.randi_range(0, n - 1)
	phase = Rules.Phase.SKILL_PICK
	return _pending_events


func player(i: int) -> Dictionary:
	return _players[i]


func alive_count() -> int:
	var c := 0
	for p in _players:
		if p.alive:
			c += 1
	return c


func apply(action: Dictionary) -> Array:
	_pending_events = []
	var a := action.duplicate(true)
	var t: String = a.get("type", "")
	var pid: int = a.get("pid", -1)
	if t == "PASS_WINDOW":
		return _pending_events
	if pid < 0 or pid >= _players.size():
		_emit({"type": "REJECTED", "reason": "bad_pid", "action": a})
		return _pending_events
	var p: Dictionary = _players[pid]
	match t:
		"PICK_CHAR":
			var c: int = a.get("char_id", -1)
			if phase == Rules.Phase.SKILL_PICK and c >= 0 and c <= 5:
				p.char_id = c
			else:
				_emit({"type": "REJECTED", "reason": "wrong_phase", "action": a})
		"READY":
			if phase == Rules.Phase.SKILL_PICK:
				p.ready = true
				if _all_ready():
					phase = Rules.Phase.PLAY
					_emit({"type": "POISON_START", "starter": current_player})
			else:
				_emit({"type": "REJECTED", "reason": "wrong_phase", "action": a})
		"OFFER":
			_do_offer(a, p)
		"RESPOND":
			_do_respond(a, p)
		"PASS_ON":
			_do_pass_on(a, p)
		"EMOTE":
			if p.alive:
				_emit(Event.emote(pid, a.get("emote", 0)))
		_:
			_emit({"type": "REJECTED", "reason": "illegal", "action": a})
	return _pending_events


func force_resolve_skill_pick() -> Array:
	_pending_events = []
	if phase == Rules.Phase.SKILL_PICK:
		for p in _players:
			p.ready = true
		phase = Rules.Phase.PLAY
		_emit({"type": "POISON_START", "starter": current_player})
	return _pending_events


func _all_ready() -> bool:
	for p in _players:
		if p.alive and not p.ready:
			return false
	return true


func _do_offer(a: Dictionary, p: Dictionary) -> void:
	var idx: int = a.get("card_index", -1)
	var target: int = a.get("target", -1)
	var claim: int = a.get("claim", -1)
	if phase != Rules.Phase.PLAY or offer_active or p.id != current_player:
		_emit({"type": "REJECTED", "reason": "wrong_phase", "action": a})
		return
	if idx < 0 or idx >= p.hand.size() \
			or claim < 0 or claim >= Rules.POISON_NAMES.size() \
			or target < 0 or target >= _players.size() or target == p.id \
			or not _players[target].alive:
		_emit({"type": "REJECTED", "reason": "bad_offer", "action": a})
		return
	offer_active = true
	offer_card = p.hand[idx]
	p.hand.remove_at(idx)
	offer_claim = claim
	offer_from = p.id
	offer_to = target
	offer_seen = [p.id]
	current_player = target
	round_number += 1
	_emit({"type": "OFFER_MADE", "from": p.id, "to": target, "claim": claim})


func _do_respond(a: Dictionary, p: Dictionary) -> void:
	if phase != Rules.Phase.PLAY or not offer_active or p.id != offer_to:
		_emit({"type": "REJECTED", "reason": "not_receiver", "action": a})
		return
	var guess_true: bool = a.get("guess", true)
	var is_true := offer_card == offer_claim
	var correct := (guess_true and is_true) or (not guess_true and not is_true)
	var eater: Dictionary = _players[offer_from] if correct else p
	_emit({"type": "OFFER_REVEALED", "card": offer_card, "claim": offer_claim,
		"from": offer_from, "to": p.id, "guess": guess_true, "eater": eater.id})
	_eat(eater, offer_card)


func _do_pass_on(a: Dictionary, p: Dictionary) -> void:
	if phase != Rules.Phase.PLAY or not offer_active or p.id != offer_to:
		_emit({"type": "REJECTED", "reason": "not_receiver", "action": a})
		return
	var claim: int = a.get("claim", -1)
	var target: int = a.get("target", -1)
	if claim < 0 or claim >= Rules.POISON_NAMES.size():
		_emit({"type": "REJECTED", "reason": "bad_claim", "action": a})
		return
	if target < 0 or target >= _players.size() or not _players[target].alive \
			or offer_seen.has(target) or target == p.id:
		_emit({"type": "REJECTED", "reason": "bad_target", "action": a})
		return
	offer_seen.append(p.id)
	offer_claim = claim
	offer_from = p.id
	offer_to = target
	current_player = target
	_emit({"type": "PASSED_ON", "from": p.id, "to": target, "claim": claim})


func _can_pass_on(pid: int) -> bool:
	# 还有没看过这张牌的存活玩家可递
	for q in _players:
		if q.alive and q.id != pid and not offer_seen.has(q.id):
			return true
	return false


func _eat(eater: Dictionary, kind: int) -> void:
	eater.collected[kind] += 1
	_emit({"type": "POISON_EATEN", "pid": eater.id, "kind": kind,
		"count": eater.collected[kind]})
	offer_active = false
	offer_card = -1
	if eater.collected[kind] >= Rules.POISON_DEATH:
		eater.alive = false
		_emit({"type": "POISONED_OUT", "pid": eater.id})
		if alive_count() == 1:
			for q in _players:
				if q.alive:
					winner = q.id
					break
			phase = Rules.Phase.GAME_OVER
			_emit({"type": "GAME_OVER", "winner": winner})
			return
	# 吃毒者（若存活）下一个出手；死了或手空 → 顺延到下一个有牌的存活者
	var nxt: int = eater.id
	if not eater.alive or eater.hand.is_empty():
		nxt = _next_with_hand(eater.id)
	if nxt == -1:
		_finish_by_exhaustion()
		return
	current_player = nxt


func _next_with_hand(from_id: int) -> int:
	var n := _players.size()
	for i in range(0, n):
		var cand := (from_id + 1 + i) % n
		var q: Dictionary = _players[cand]
		if q.alive and q.hand.size() > 0:
			return cand
	return -1


func _finish_by_exhaustion() -> void:
	# 兜底：全场手牌耗尽 → 吃毒总数最少者胜（平手取座位序靠前）
	var best := -1
	var best_total := 999
	for q in _players:
		if not q.alive:
			continue
		var tot := 0
		for k in q.collected:
			tot += k
		if tot < best_total:
			best_total = tot
			best = q.id
	winner = best
	phase = Rules.Phase.GAME_OVER
	_emit({"type": "GAME_OVER", "winner": winner})


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t2 = arr[i]
		arr[i] = arr[j]
		arr[j] = t2


func _emit(e: Dictionary) -> void:
	_pending_events.append(e)


func legal_actions(pid: int) -> Array:
	var out := []
	var p: Dictionary = _players[pid]
	if phase == Rules.Phase.SKILL_PICK:
		out.append({"type": "READY", "pid": pid})
		return out
	if phase != Rules.Phase.PLAY or not p.alive:
		return out
	if offer_active and pid == offer_to:
		out.append({"type": "RESPOND", "pid": pid, "guess": true})
		out.append({"type": "RESPOND", "pid": pid, "guess": false})
		if _can_pass_on(pid):
			out.append({"type": "PASS_ON", "pid": pid})   # claim/target 由 UI 补
	elif not offer_active and pid == current_player and p.hand.size() > 0:
		out.append({"type": "OFFER", "pid": pid})          # 细节由 UI 补
	return out


func view_for(pid: int) -> Dictionary:
	var me: Dictionary = _players[pid]
	var plist := []
	for p in _players:
		plist.append({
			"id": p.id, "name": p.name, "is_bot": p.is_bot, "alive": p.alive,
			"hand_count": p.hand.size(), "collected": p.collected.duplicate(),
			"char_id": p.char_id, "ready": p.ready,
			"steps_taken": 0, "has_gap": false,
			"skill": Rules.Skill.NONE, "skill_uses_left": 0, "houfa_ready_round": 0,
			"golden_bell_used": false,
		})
	var peeked := -1
	# 机密裁剪：只有当前收礼人能看到牌面（这是"偷看后转赠"的知情基础）
	if offer_active and pid == offer_to:
		peeked = offer_card
	return {
		"mode": Rules.Mode.DIDU,
		"you": {
			"id": me.id, "hand": me.hand.duplicate(), "alive": me.alive,
			"collected": me.collected.duplicate(), "char_id": me.char_id, "ready": me.ready,
			"steps_taken": 0, "has_gap": false, "peeked": peeked,
			"skill": Rules.Skill.NONE, "skill_uses_left": 0, "houfa_ready_round": 0,
			"probe_result": {}, "listen_result": {}, "pending_skill_pick": 0,
		},
		"players": plist,
		"phase": phase, "round_number": round_number,
		"current_player": current_player, "round_starter": current_player,
		"offer_active": offer_active, "offer_claim": offer_claim,
		"offer_from": offer_from, "offer_to": offer_to,
		"offer_seen": offer_seen.duplicate(),
		"alive_count": alive_count(), "winner": winner,
		"skills_enabled": false,
		"current_suit": -1, "suit_changed_by": -1,
		"last_player_who_played": -1, "last_played_count": 0,
		"discard_count": 0, "deck_remaining": 0,
		"legal_actions": legal_actions(pid),
	}


# 机器人决策（只读 view）
static func bot_decide(view: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var me: Dictionary = view.you
	if int(view.phase) == Rules.Phase.SKILL_PICK:
		return {"type": "READY", "pid": me.id}
	if bool(view.offer_active) and int(view.offer_to) == int(me.id):
		var claim: int = view.offer_claim
		var my_claim_cnt: int = me.collected[claim]
		# 快毒发的种类：强烈想判对——赌"不信"偏多（撒谎率高）
		var believe := rng.randf() < 0.42
		if my_claim_cnt >= 2 and rng.randf() < 0.5 and view.offer_seen.size() < int(view.alive_count):
			# 危险牌先转赠祸水
			var targets := []
			for q in view.players:
				if bool(q.alive) and int(q.id) != int(me.id) and not view.offer_seen.has(int(q.id)):
					targets.append(int(q.id))
			if not targets.is_empty():
				var actual: int = me.peeked
				var lie := rng.randf() < 0.5
				var c2: int = actual if not lie else rng.randi_range(0, 4)
				return {"type": "PASS_ON", "pid": me.id, "claim": c2,
					"target": targets[rng.randi_range(0, targets.size() - 1)]}
		return {"type": "RESPOND", "pid": me.id, "guess": believe}
	# 出手：挑目标（毒最深的人）+ 半真半假声称
	var idx := rng.randi_range(0, me.hand.size() - 1)
	var card: int = me.hand[idx]
	var lie2 := rng.randf() < 0.45
	var claim2: int = card if not lie2 else rng.randi_range(0, 4)
	var best_t := -1
	var best_danger := -1
	for q in view.players:
		if not bool(q.alive) or int(q.id) == int(me.id):
			continue
		var danger := 0
		for k in q.collected:
			danger = maxi(danger, int(k))
		if danger > best_danger:
			best_danger = danger
			best_t = int(q.id)
	return {"type": "OFFER", "pid": me.id, "card_index": idx,
		"target": best_t, "claim": claim2}
