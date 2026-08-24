class_name GameDice
extends RefCounted

# 「暗器」模式内核（大话骰武侠壳）。与 GameState 同一接口面：
# new_game / apply / view_for / legal_actions / force_resolve_skill_pick / phase / winner。
# 铁律 1–5 全部适用：纯逻辑、带种子 RNG、按人裁剪视图、可序列化、不推进时间。
#
# 规则（多玩法方案 §3.B）：
#   每人暗器囊 5 枚（六面：0..4 兵器，5=无影针百搭），只有自己可见。
#   轮流叫价「全场至少 N 枚 X」，必须加码（N 更大，或 N 相同兵器序号更大）。
#   拆招 → 全场亮囊清点（百搭计入）：叫价成立拆招者退步，否则叫价者退步。
#   每退一步，下一轮囊中少一枚（min 1）。石板/虚石与论招同规。

var _seed: int = 0
var _rng: RandomNumberGenerator

var phase: int = Rules.Phase.SKILL_PICK      # 0=选皮囊 2=对局 4=终局
var round_number: int = 0
var current_player: int = -1
var round_starter: int = -1
var winner: int = -1
var bid_n: int = 0                            # 当前叫价（0 = 本轮尚无叫价）
var bid_face: int = -1
var bid_by: int = -1

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
			"dice": [], "steps_taken": 0, "hollow_index": _rng.randi_range(1, Rules.STONES),
			"has_gap": false, "char_id": i, "ready": is_bot[i],
		})
	round_starter = _rng.randi_range(0, n - 1)
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
					_start_round()
			else:
				_emit({"type": "REJECTED", "reason": "wrong_phase", "action": a})
		"BID":
			var n: int = a.get("n", 0)
			var face: int = a.get("face", -1)
			if not _bid_legal(pid, n, face):
				_emit({"type": "REJECTED", "reason": _bid_reason(pid, n, face), "action": a})
				return _pending_events
			bid_n = n
			bid_face = face
			bid_by = pid
			_emit({"type": "BID", "pid": pid, "n": n, "face": face})
			current_player = _next_alive(pid)
		"CHALLENGE":
			if phase != Rules.Phase.PLAY or pid != current_player:
				_emit({"type": "REJECTED", "reason": "not_your_turn", "action": a})
				return _pending_events
			if bid_by == -1 or bid_by == pid:
				_emit({"type": "REJECTED", "reason": "no_bid", "action": a})
				return _pending_events
			_resolve_challenge(pid)
		"EMOTE":
			if p.alive:
				_emit(Event.emote(pid, a.get("emote", 0)))
		_:
			_emit({"type": "REJECTED", "reason": "illegal", "action": a})
	return _pending_events


func force_resolve_skill_pick() -> Array:
	# 选皮囊阶段超时收尾：全员视为已准备
	_pending_events = []
	if phase == Rules.Phase.SKILL_PICK:
		for p in _players:
			p.ready = true
		_start_round()
	return _pending_events


func _all_ready() -> bool:
	for p in _players:
		if p.alive and not p.ready:
			return false
	return true


func _bid_legal(pid: int, n: int, face: int) -> bool:
	if phase != Rules.Phase.PLAY or pid != current_player:
		return false
	if not Rules.DICE_BIDDABLE.has(face):
		return false
	if n < 1 or n > _total_dice():
		return false
	if bid_by == -1:
		return true
	return n > bid_n or (n == bid_n and face > bid_face)


func _bid_reason(pid: int, n: int, face: int) -> String:
	if phase != Rules.Phase.PLAY:
		return "wrong_phase"
	if pid != current_player:
		return "not_your_turn"
	if not Rules.DICE_BIDDABLE.has(face):
		return "bad_face"
	if n < 1 or n > _total_dice():
		return "bad_n"
	return "must_raise"


func _total_dice() -> int:
	var t := 0
	for p in _players:
		if p.alive:
			t += p.dice.size()
	return t


func _start_round() -> void:
	round_number += 1
	bid_n = 0
	bid_face = -1
	bid_by = -1
	phase = Rules.Phase.PLAY
	var counts := {}
	for p in _players:
		if not p.alive:
			continue
		var n: int = maxi(Rules.DICE_START - p.steps_taken, 1)   # 越输囊里越少
		p.dice = []
		for i in n:
			p.dice.append(_rng.randi_range(0, 5))
		counts[p.id] = n
	current_player = round_starter
	_emit({"type": "DICE_ROUND_START", "round": round_number, "starter": round_starter, "counts": counts})


func _resolve_challenge(challenger_id: int) -> void:
	var count := 0
	var all_dice := {}
	for p in _players:
		if p.alive:
			all_dice[str(p.id)] = p.dice.duplicate()
			for d in p.dice:
				if d == bid_face or d == Rules.DICE_WILD:
					count += 1
	var stands := count >= bid_n
	_emit({"type": "DICE_CHALLENGE", "by": challenger_id, "target": bid_by})
	_emit({"type": "DICE_REVEALED", "all_dice": all_dice, "count": count,
		"bid_n": bid_n, "bid_face": bid_face, "stands": stands})
	var loser: Dictionary = _players[challenger_id] if stands else _players[bid_by]
	_retreat(loser, 1)
	_end_round(loser.id)


func _retreat(p: Dictionary, steps: int) -> void:
	for i in steps:
		if not p.alive:
			return
		if p.has_gap:
			p.alive = false
			_emit(Event.fall(p.id))
			return
		var from_step: int = p.steps_taken
		p.steps_taken += 1
		_emit(Event.retreat(p.id, from_step, p.steps_taken))
		if p.steps_taken == p.hollow_index:
			p.alive = false
			_emit(Event.fall(p.id))
			return


func _end_round(retreater_id: int) -> void:
	var r: Dictionary = _players[retreater_id]
	round_starter = r.id if r.alive else _next_alive(r.id)
	_emit({"type": "ROUND_END", "retreater": retreater_id})
	if alive_count() == 1:
		for p in _players:
			if p.alive:
				winner = p.id
				break
		phase = Rules.Phase.GAME_OVER
		_emit({"type": "GAME_OVER", "winner": winner})
		return
	_start_round()


func _next_alive(from_id: int) -> int:
	var n := _players.size()
	for i in range(1, n + 1):
		var cand := (from_id + i) % n
		if _players[cand].alive:
			return cand
	return from_id


func _emit(e: Dictionary) -> void:
	_pending_events.append(e)


func legal_actions(pid: int) -> Array:
	var out := []
	if phase == Rules.Phase.SKILL_PICK:
		out.append({"type": "READY", "pid": pid})
		return out
	if phase == Rules.Phase.PLAY and pid == current_player:
		if bid_by != -1 and bid_by != pid:
			out.append({"type": "CHALLENGE", "pid": pid})
		# 最小加码示例（UI/机器人可自行构造更高叫价）
		if bid_by == -1:
			out.append({"type": "BID", "pid": pid, "n": 1, "face": 0})
		elif bid_face < 4:
			out.append({"type": "BID", "pid": pid, "n": bid_n, "face": bid_face + 1})
		elif bid_n < _total_dice():
			out.append({"type": "BID", "pid": pid, "n": bid_n + 1, "face": 0})
	return out


func view_for(pid: int) -> Dictionary:
	var me: Dictionary = _players[pid]
	var plist := []
	for p in _players:
		plist.append({
			"id": p.id, "name": p.name, "is_bot": p.is_bot, "alive": p.alive,
			"hand_count": p.dice.size(), "steps_taken": p.steps_taken,
			"has_gap": p.has_gap, "char_id": p.char_id, "ready": p.ready,
			"skill": Rules.Skill.NONE, "skill_uses_left": 0, "houfa_ready_round": 0,
			"golden_bell_used": false,
		})
	return {
		"mode": Rules.Mode.ANQI,
		"you": {
			"id": me.id, "dice": me.dice.duplicate(), "hand": [],
			"steps_taken": me.steps_taken, "has_gap": me.has_gap, "alive": me.alive,
			"char_id": me.char_id, "ready": me.ready,
			"skill": Rules.Skill.NONE, "skill_uses_left": 0, "houfa_ready_round": 0,
			"probe_result": {}, "listen_result": {}, "pending_skill_pick": 0,
		},
		"players": plist,
		"phase": phase, "round_number": round_number,
		"current_player": current_player, "round_starter": round_starter,
		"bid_n": bid_n, "bid_face": bid_face, "bid_by": bid_by,
		"total_dice": _total_dice(),
		"alive_count": alive_count(), "winner": winner,
		"skills_enabled": false,
		"current_suit": -1, "suit_changed_by": -1,
		"last_player_who_played": -1, "last_played_count": 0,
		"discard_count": 0, "deck_remaining": 0,
		"legal_actions": legal_actions(pid),
	}


# 机器人决策（只读 view，铁律 3）
static func bot_decide(view: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var me: Dictionary = view.you
	if int(view.phase) == Rules.Phase.SKILL_PICK:
		return {"type": "READY", "pid": me.id}
	var total: int = view.total_dice
	var others: int = total - me.dice.size()
	if int(view.bid_by) != -1 and int(view.bid_by) != int(me.id):
		# 评估当前叫价：我有几枚 + 别人期望（每面≈1/6，加百搭≈1/3）
		var mine := 0
		for d in me.dice:
			if d == int(view.bid_face) or d == Rules.DICE_WILD:
				mine += 1
		var expect := float(mine) + float(others) / 3.0
		var over := float(view.bid_n) - expect
		var pch := clampf(0.18 + over * 0.32, 0.05, 0.92)
		if rng.randf() < pch:
			return {"type": "CHALLENGE", "pid": me.id}
	# 加码：优先叫自己最多的面
	var best_face := 0
	var best_cnt := -1
	for f in Rules.DICE_BIDDABLE:
		var c := 0
		for d in me.dice:
			if d == f or d == Rules.DICE_WILD:
				c += 1
		if c > best_cnt:
			best_cnt = c
			best_face = f
	var n: int
	var face: int
	if int(view.bid_by) == -1:
		n = maxi(1, best_cnt)
		face = best_face
	elif best_face > int(view.bid_face):
		n = int(view.bid_n)
		face = best_face
	elif int(view.bid_face) < 4:
		n = int(view.bid_n)
		face = int(view.bid_face) + 1
	else:
		n = int(view.bid_n) + 1
		face = best_face
	if n > total:
		return {"type": "CHALLENGE", "pid": me.id}
	return {"type": "BID", "pid": me.id, "n": n, "face": face}
