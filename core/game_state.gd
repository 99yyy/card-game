class_name GameState
extends RefCounted

# 全部状态 + 状态推进（§6、§7、§10、§11）。
# 铁律 1：纯逻辑，不依赖场景树/输入/时间/引擎单例，无异步、无信号、无全局 RNG。
# 铁律 2：随机一律走 _rng（RandomNumberGenerator）。
# 铁律 5：内核不推进时间，倒计时由驱动层负责。

var _seed: int = 0
var _rng: RandomNumberGenerator

# ---------- 全局 ----------
var skills_enabled: bool = true
var phase: int = Rules.Phase.SKILL_PICK
var round_number: int = 0
var current_suit: int = -1
var suit_changed_by: int = -1        # -1 = 本轮未被改弦
var current_player: int = -1
var round_starter: int = -1
var last_player_who_played: int = -1 # 「上家」，-1 = 本轮还没人出过
var last_played_cards: Array = []    # 最近一手的真实牌面（机密）
var discard_count: int = 0           # 弃牌数（内容永不揭示，边界 29）
var deck_remaining: int = 0
var winner: int = -1                 # -1 = 未结束

var _players: Array = []             # Array[Dictionary]

# 事件缓冲区：apply()/new_game() 开始时清空，内部 _emit 写入，结束返回快照
var _pending_events: Array = []

# ---------- 构造 ----------
func _init(seed: int = 0, skills: bool = true) -> void:
	_seed = seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	skills_enabled = skills

# ---------- 玩家访问 ----------
func player_count() -> int:
	return _players.size()

func player(i: int) -> Dictionary:
	return _players[i]

func alive_count() -> int:
	var n := 0
	for p in _players:
		if p.alive:
			n += 1
	return n

# ---------- 开局 ----------
func new_game(player_names: Array, is_bot: Array) -> Array:
	_pending_events = []
	var n := player_names.size()
	if n < Rules.MIN_PLAYERS or n > Rules.MAX_PLAYERS:
		# 非法人数：静默拒绝初始化（§7.3 契约：非法输入不崩）
		return _pending_events
	_players = []
	for i in n:
		_players.append(_make_player(i, player_names[i], is_bot[i]))
	# 每人虚石位置随机确定，任何人不可见（规则 §5）
	for p in _players:
		p.hollow_index = _rng.randi_range(1, Rules.STONES)
	round_starter = _rng.randi_range(0, n - 1)
	round_number = 0
	winner = -1
	current_player = -1
	last_player_who_played = -1
	last_played_cards = []
	discard_count = 0
	deck_remaining = 0
	suit_changed_by = -1
	if skills_enabled:
		phase = Rules.Phase.SKILL_PICK
	else:
		_start_round()
	return _pending_events

func _make_player(id: int, pname: String, bot: bool) -> Dictionary:
	return {
		"id": id,
		"name": pname,
		"is_bot": bot,
		"alive": true,
		"hand": [],
		"skill": Rules.Skill.NONE,
		"skill_uses_left": 0,
		"houfa_ready_round": 0,
		"steps_taken": 0,
		"hollow_index": 0,           # 机密，稍后随机
		"has_gap": false,
		"golden_bell_used": false,
		"probe_result": {},          # {"3": true}
		"listen_result": {},         # {"7": 0} 按轮号 key
		"pending_skill_pick": Rules.Skill.NONE,
	}

# ---------- 动作入口 ----------
func apply(action: Dictionary) -> Array:
	_pending_events = []
	var a := action.duplicate(true)
	var t: String = a.get("type", "")
	# 驱动层的窗口推进（§14），不是玩家动作
	if t == "PASS_WINDOW":
		if phase == Rules.Phase.SWAP_WINDOW:
			phase = Rules.Phase.PLAY
		return _pending_events
	if not _is_legal(a):
		_emit({"type": "REJECTED", "reason": _reject_reason(a), "action": a})
		return _pending_events
	match t:
		"PICK_SKILL":
			var p: Dictionary = _players[a.pid]
			p.pending_skill_pick = a.skill
		"USE_GAIXIAN":
			var p: Dictionary = _players[a.pid]
			p.skill_uses_left -= 1
			var frm: int = current_suit
			current_suit = a.suit
			suit_changed_by = a.pid
			_emit(Event.suit_changed(a.pid, frm, current_suit))
		"USE_TINGJIN":
			var p: Dictionary = _players[a.pid]
			p.skill_uses_left -= 1
			var card: int = last_played_cards[a.card_pos]
			p.listen_result[str(round_number)] = card
			_emit(Event.skill_used(a.pid, Rules.Skill.TINGJIN))
		"USE_BIANXUSHI":
			var p: Dictionary = _players[a.pid]
			p.skill_uses_left -= 1
			p.probe_result[str(a.stone)] = (a.stone == p.hollow_index)
			_emit(Event.skill_used(a.pid, Rules.Skill.BIANXUSHI))
		"PLAY":
			_do_play(a)
		"CHALLENGE":
			_do_challenge(a)
		"EMOTE":
			_emit(Event.emote(a.pid, a.emote))
	# 收齐全部 PICK_SKILL → 裁决
	if phase == Rules.Phase.SKILL_PICK and _all_picked():
		_resolve_skill_pick()
	return _pending_events

# 驱动层在真人超时后调用：把未决定的存活玩家当作放弃（进落选池随机分配，规则 §3.5）。
# 这不是玩家动作，是对「超时放弃」的收尾（§14 阶段超时）。
func force_resolve_skill_pick() -> Array:
	_pending_events = []
	if phase == Rules.Phase.SKILL_PICK:
		_resolve_skill_pick()
	return _pending_events

# ---------- 合法性（唯一判定，§7.2 / 坑 6）----------
func _is_legal(a: Dictionary) -> bool:
	var t: String = a.get("type", "")
	var pid: int = a.get("pid", -1)
	if pid < 0 or pid >= _players.size():
		return false
	var p: Dictionary = _players[pid]
	match t:
		"PICK_SKILL":
			return skills_enabled \
				and phase == Rules.Phase.SKILL_PICK \
				and p.pending_skill_pick == Rules.Skill.NONE \
				and Rules.ALL_SKILLS.has(a.get("skill", Rules.Skill.NONE))
		"USE_GAIXIAN":
			return skills_enabled \
				and phase == Rules.Phase.SWAP_WINDOW \
				and p.skill == Rules.Skill.GAIXIAN \
				and p.skill_uses_left > 0 \
				and Rules.PLAYABLE_SUITS.has(a.get("suit", -1)) \
				and p.alive
		"USE_TINGJIN":
			return skills_enabled \
				and phase == Rules.Phase.PLAY \
				and pid == current_player \
				and p.skill == Rules.Skill.TINGJIN \
				and p.skill_uses_left > 0 \
				and last_player_who_played != -1 \
				and last_player_who_played != pid \
				and a.get("card_pos", -1) >= 0 \
				and a.get("card_pos", -1) < last_played_cards.size()
		"USE_BIANXUSHI":
			return skills_enabled \
				and phase == Rules.Phase.PLAY \
				and pid == current_player \
				and p.skill == Rules.Skill.BIANXUSHI \
				and p.skill_uses_left > 0 \
				and a.get("stone", 0) >= 1 \
				and a.get("stone", 0) <= Rules.STONES \
				and a.get("stone", 0) > p.steps_taken
		"PLAY":
			if phase != Rules.Phase.PLAY or pid != current_player:
				return false
			var idx: Array = a.get("indices", [])
			if idx.size() < 1 or idx.size() > Rules.MAX_PLAY_CARDS:
				return false
			var seen := {}
			for i in idx:
				if typeof(i) != TYPE_INT:
					return false
				if i < 0 or i >= p.hand.size():
					return false
				if seen.has(i):
					return false
				seen[i] = true
			return true
		"CHALLENGE":
			return phase == Rules.Phase.PLAY \
				and pid == current_player \
				and last_player_who_played != -1 \
				and last_player_who_played != pid
		"EMOTE":
			return p.alive
	return false

# 机器可读的短标识（§7.3），与 _is_legal 的条件一一对应
func _reject_reason(a: Dictionary) -> String:
	var t: String = a.get("type", "")
	var pid: int = a.get("pid", -1)
	if pid < 0 or pid >= _players.size():
		return "bad_pid"
	var p: Dictionary = _players[pid]
	match t:
		"PICK_SKILL":
			if not skills_enabled: return "skills_off"
			if phase != Rules.Phase.SKILL_PICK: return "wrong_phase"
			if p.pending_skill_pick != Rules.Skill.NONE: return "already_picked"
			return "bad_skill"
		"USE_GAIXIAN":
			if not skills_enabled: return "skills_off"
			if phase != Rules.Phase.SWAP_WINDOW: return "wrong_phase"
			if p.skill != Rules.Skill.GAIXIAN: return "no_skill"
			if p.skill_uses_left <= 0: return "no_uses"
			if not p.alive: return "dead"
			return "bad_suit"
		"USE_TINGJIN":
			if not skills_enabled: return "skills_off"
			if phase != Rules.Phase.PLAY: return "wrong_phase"
			if pid != current_player: return "not_your_turn"
			if p.skill != Rules.Skill.TINGJIN: return "no_skill"
			if p.skill_uses_left <= 0: return "no_uses"
			if last_player_who_played == -1: return "no_last_play"
			if last_player_who_played == pid: return "self_is_last"
			return "bad_card_pos"
		"USE_BIANXUSHI":
			if not skills_enabled: return "skills_off"
			if phase != Rules.Phase.PLAY: return "wrong_phase"
			if pid != current_player: return "not_your_turn"
			if p.skill != Rules.Skill.BIANXUSHI: return "no_skill"
			if p.skill_uses_left <= 0: return "no_uses"
			var s: int = a.get("stone", 0)
			if s < 1 or s > Rules.STONES: return "bad_stone"
			return "already_stepped"
		"PLAY":
			if phase != Rules.Phase.PLAY: return "wrong_phase"
			if pid != current_player: return "not_your_turn"
			var idx: Array = a.get("indices", [])
			if idx.size() < 1 or idx.size() > Rules.MAX_PLAY_CARDS: return "bad_count"
			return "bad_indices"
		"CHALLENGE":
			if phase != Rules.Phase.PLAY: return "wrong_phase"
			if pid != current_player: return "not_your_turn"
			if last_player_who_played == -1: return "no_last_play"
			return "self_is_last"
		"EMOTE":
			return "dead"
	return "illegal"

# ---------- 阶段推进 ----------
func _all_picked() -> bool:
	for p in _players:
		if p.alive and p.pending_skill_pick == Rules.Skill.NONE:
			return false
	return true

func _start_round() -> void:
	round_number += 1
	suit_changed_by = -1
	current_suit = Rules.PLAYABLE_SUITS[_rng.randi_range(0, Rules.PLAYABLE_SUITS.size() - 1)]
	# 洗全部 30 张（Fisher–Yates 走 _rng），给每个存活玩家发 5 张（边界 32）
	var deck := Rules.build_deck()
	_shuffle(deck)
	var alive := _alive_players()
	var counts := {}
	var k := 0
	for p in alive:
		p.hand = deck.slice(k, k + Rules.HAND_SIZE)
		counts[p.id] = p.hand.size()
		k += Rules.HAND_SIZE
	deck_remaining = Rules.DECK_SIZE - alive.size() * Rules.HAND_SIZE
	last_player_who_played = -1
	last_played_cards = []
	discard_count = 0
	current_player = round_starter
	var swap_pending := false
	if skills_enabled:
		for p in alive:
			if p.skill == Rules.Skill.GAIXIAN and p.skill_uses_left > 0:
				swap_pending = true
				break
	phase = Rules.Phase.SWAP_WINDOW if swap_pending else Rules.Phase.PLAY
	_emit(Event.round_start(round_number, current_suit, round_starter))
	_emit(Event.dealt(counts))

func _alive_players() -> Array:
	var out := []
	for p in _players:
		if p.alive:
			out.append(p)
	return out

# ---------- 出招 / 拆招 ----------
func _do_play(a: Dictionary) -> void:
	var p: Dictionary = _players[a.pid]
	var indices: Array = a.indices
	# 旧的 last_played_cards 进弃牌堆（边界 29）
	discard_count += last_played_cards.size()
	var played := []
	for i in indices:
		played.append(p.hand[i])
	# 从手牌移除（按降序避免下标漂移）
	var sorted := indices.duplicate()
	sorted.sort()
	for i in range(sorted.size() - 1, -1, -1):
		p.hand.remove_at(sorted[i])
	last_played_cards = played
	last_player_who_played = a.pid
	_emit(Event.played(a.pid, played.size()))
	# 天道检验（边界 33，原版规则）：本手打出后，若其他存活玩家均已出尽，
	# 这一手无人可拆 → 自动亮招。堵住"熬到别人出完就能白扔假牌"的反高潮漏洞。
	var others_have_cards := false
	for q in _players:
		if q.alive and q.id != a.pid and q.hand.size() > 0:
			others_have_cards = true
			break
	if not others_have_cards:
		_emit(Event.heaven_check(a.pid))
		var honest := true
		for c in last_played_cards:
			if not Rules.is_truthful(c, current_suit):
				honest = false
				break
		_emit(Event.revealed(a.pid, last_played_cards.duplicate(), current_suit, honest))
		if honest:
			# 真招：弃掉这一手，若还有牌继续由他出（每手都会被检验）
			discard_count += last_played_cards.size()
			last_played_cards = []
			last_player_who_played = -1
			if p.hand.is_empty():
				_end_round(-1)
			return
		# 虚招被天道拆穿：不触发后发制人（没有拆招者），退步并结束本轮
		_retreat(p, 1)
		_end_round(p.id)
		return
	if not _advance_turn():
		_end_round(-1)

func _do_challenge(a: Dictionary) -> void:
	var target: Dictionary = _players[last_player_who_played]
	_emit(Event.challenged(a.pid, target.id))
	phase = Rules.Phase.REVEAL
	_resolve_reveal(a.pid, target)

func _resolve_reveal(challenger_id: int, target: Dictionary) -> void:
	var honest := true
	for c in last_played_cards:
		if not Rules.is_truthful(c, current_suit):
			honest = false
			break
	_emit(Event.revealed(target.id, last_played_cards.duplicate(), current_suit, honest))
	if honest:
		# 拆招的人冤枉了人 → 拆招者退步
		var victim: Dictionary = _players[challenger_id]
		if skills_enabled \
			and target.skill == Rules.Skill.HOUFA \
			and round_number >= target.houfa_ready_round:
			target.houfa_ready_round = round_number + Rules.HOUFA_COOLDOWN_ROUNDS
			_emit(Event.houfa_triggered(target.id, victim.id))
			_retreat(victim, Rules.HOUFA_TOTAL_STEPS)
		else:
			_retreat(victim, 1)
	else:
		# 上家使的是虚招 → 上家退步
		_retreat(target, 1)
	# 边界 27：下一轮由"退步者"开始。honest 时退步的是拆招者，不是被拆者——
	# 旧版这里恒传 target.id 是 bug（起始者会定错人），一并修正
	_end_round(challenger_id if honest else target.id)

# ---------- 退步（唯一的实现，§11.1 / 坑 1）----------
func _retreat(p: Dictionary, steps: int) -> void:
	for i in steps:
		if not p.alive:
			return
		# 豁口判定必须在 steps_taken += 1 之前！
		if p.has_gap:
			p.alive = false
			_emit(Event.fall(p.id))
			return
		var from_step: int = p.steps_taken
		p.steps_taken += 1
		_emit(Event.retreat(p.id, from_step, p.steps_taken))
		if p.steps_taken == p.hollow_index:
			if skills_enabled and p.skill == Rules.Skill.JINZHONGZHAO and not p.golden_bell_used:
				p.golden_bell_used = true
				p.skill_uses_left = 0
				p.has_gap = true
				_emit(Event.golden_bell(p.id))
			else:
				p.alive = false
				_emit(Event.fall(p.id))
				return

# ---------- 找下一个能行动的人（§11.2 / 坑 2）----------
func _advance_turn() -> bool:
	var n := _players.size()
	for i in range(1, n + 1):
		var cand := (current_player + i) % n
		var p: Dictionary = _players[cand]
		if p.alive and p.hand.size() > 0:
			current_player = cand
			return true
		if p.alive and p.hand.is_empty() and cand != current_player:
			_emit(Event.skipped(cand, "empty_hand"))
	return false

# ---------- 结束一轮 ----------
func _end_round(retreater_id: int) -> void:
	# 确定下一轮起始者（边界 27）
	if retreater_id == -1:
		round_starter = _next_alive(round_starter)
	else:
		var r: Dictionary = _players[retreater_id]
		if r.alive:
			round_starter = r.id
		else:
			round_starter = _next_alive(r.id)
	_emit(Event.round_end(retreater_id))
	if alive_count() == 1:
		for p in _players:
			if p.alive:
				winner = p.id
				break
		phase = Rules.Phase.GAME_OVER
		_emit(Event.game_over(winner))
		return
	_start_round()

func _next_alive(from_id: int) -> int:
	var n := _players.size()
	for i in range(1, n + 1):
		var cand := (from_id + i) % n
		if _players[cand].alive:
			return cand
	return from_id

# ---------- 技能裁决（§11.3 / 坑 4）----------
func _resolve_skill_pick() -> void:
	var by_skill := {}
	var losers := []
	for p in _players:
		var s: int = p.pending_skill_pick
		if s == Rules.Skill.NONE:
			losers.append(p.id)
		else:
			if not by_skill.has(s):
				by_skill[s] = []
			by_skill[s].append(p.id)

	var taken := {}
	var skills_sorted := by_skill.keys()
	skills_sorted.sort()
	for s in skills_sorted:
		var claimants: Array = by_skill[s]
		claimants.sort()
		var winner_idx := _rng.randi_range(0, claimants.size() - 1)
		var w: int = claimants[winner_idx]
		taken[s] = w
		for c in claimants:
			if c != w:
				losers.append(c)

	var remaining := []
	for s in Rules.ALL_SKILLS:
		if not taken.has(s):
			remaining.append(s)

	losers.sort()
	_shuffle(losers)
	var randomized := []
	for pid in losers:
		var idx := _rng.randi_range(0, remaining.size() - 1)
		var s: int = remaining[idx]
		remaining.remove_at(idx)
		taken[s] = pid
		randomized.append(pid)

	var assignments := {}
	for s in taken:
		var p: Dictionary = _players[taken[s]]
		p.skill = s
		p.skill_uses_left = Rules.SKILL_USES[s]
		p.houfa_ready_round = 0
		assignments[p.id] = s
	_emit(Event.skills_assigned(assignments, randomized))
	_start_round()

# ---------- 洗牌（§11.4 / 坑 3）----------
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

# ---------- 事件写入 ----------
func _emit(e: Dictionary) -> void:
	_pending_events.append(e)

# ---------- 视图裁剪（§9 / 铁律 3 / 坑 9）----------
func view_for(pid: int) -> Dictionary:
	var me: Dictionary = _players[pid]
	var you := {
		"id": me.id,
		"hand": me.hand.duplicate(),
		"skill": me.skill,
		"skill_uses_left": me.skill_uses_left,
		"houfa_ready_round": me.houfa_ready_round,
		"steps_taken": me.steps_taken,
		"has_gap": me.has_gap,
		"alive": me.alive,
		"probe_result": me.probe_result.duplicate(),
		"listen_result": me.listen_result.duplicate(),
		"pending_skill_pick": me.pending_skill_pick,   # 仅本人可见（SKILL_PICK 阶段用，P3）
	}
	var plist := []
	for p in _players:
		plist.append({
			"id": p.id,
			"name": p.name,
			"is_bot": p.is_bot,
			"alive": p.alive,
			"hand_count": p.hand.size(),
			"skill": p.skill,
			"skill_uses_left": p.skill_uses_left,
			"houfa_ready_round": p.houfa_ready_round,
			"steps_taken": p.steps_taken,
			"has_gap": p.has_gap,
			"golden_bell_used": p.golden_bell_used,
		})
	return {
		"you": you,
		"players": plist,
		"phase": phase,
		"round_number": round_number,
		"current_suit": current_suit,
		"suit_changed_by": suit_changed_by,
		"current_player": current_player,
		"round_starter": round_starter,
		"last_player_who_played": last_player_who_played,
		"last_played_count": last_played_cards.size(),
		"discard_count": discard_count,
		"deck_remaining": deck_remaining,
		"alive_count": alive_count(),
		"winner": winner,
		"skills_enabled": skills_enabled,
		"legal_actions": legal_actions(pid),
	}

# ---------- 合法动作列表 ----------
func legal_actions(pid: int) -> Array:
	var out := []
	if pid < 0 or pid >= _players.size():
		return out
	var p: Dictionary = _players[pid]
	var a: Dictionary
	# 出招（手牌非空且轮到本人）
	if phase == Rules.Phase.PLAY and pid == current_player and p.alive and p.hand.size() > 0:
		a = Action.play(pid, [0])
		if _is_legal(a):
			out.append({"type": "PLAY"})
	# 拆招
	a = Action.challenge(pid)
	if _is_legal(a):
		out.append({"type": "CHALLENGE"})
	# 听劲
	a = Action.use_tingjin(pid, 0)
	if _is_legal(a):
		out.append({"type": "USE_TINGJIN"})
	# 辨虚实
	if p.alive:
		for s in range(1, Rules.STONES + 1):
			a = Action.use_bianxushi(pid, s)
			if _is_legal(a):
				out.append({"type": "USE_BIANXUSHI", "stone": s})
	# 改弦
	for s in Rules.PLAYABLE_SUITS:
		a = Action.use_gaixian(pid, s)
		if _is_legal(a):
			out.append({"type": "USE_GAIXIAN", "suit": s})
	# 选技能
	a = Action.pick_skill(pid, Rules.Skill.JINZHONGZHAO)
	if _is_legal(a):
		out.append({"type": "PICK_SKILL"})
	return out

# ---------- 序列化（§11.5 / 坑 5）----------
func to_dict() -> Dictionary:
	var d := {}
	d["_seed"] = _seed
	d["_rng_state"] = _rng.state
	d["skills_enabled"] = skills_enabled
	d["phase"] = phase
	d["round_number"] = round_number
	d["current_suit"] = current_suit
	d["suit_changed_by"] = suit_changed_by
	d["current_player"] = current_player
	d["round_starter"] = round_starter
	d["last_player_who_played"] = last_player_who_played
	d["last_played_cards"] = last_played_cards.duplicate()
	d["discard_count"] = discard_count
	d["deck_remaining"] = deck_remaining
	d["winner"] = winner
	var plist := []
	for p in _players:
		var pd := {}
		for k in p.keys():
			var v = p[k]
			if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
				v = v.duplicate(true)
			pd[k] = v
		plist.append(pd)
	d["_players"] = plist
	return d

func from_dict(d: Dictionary) -> void:
	_seed = int(d["_seed"])
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed
	_rng.state = d["_rng_state"]     # 必须恢复 state，只恢复 seed 会回到开局（坑 5）
	skills_enabled = bool(d["skills_enabled"])
	phase = int(d["phase"])
	round_number = int(d["round_number"])
	current_suit = int(d["current_suit"])
	suit_changed_by = int(d["suit_changed_by"])
	current_player = int(d["current_player"])
	round_starter = int(d["round_starter"])
	last_player_who_played = int(d["last_player_who_played"])
	last_played_cards = (d["last_played_cards"] as Array).duplicate()
	discard_count = int(d["discard_count"])
	deck_remaining = int(d["deck_remaining"])
	winner = int(d["winner"])
	_players = []
	for pd in d["_players"]:
		var p := {}
		for k in pd.keys():
			var v = pd[k]
			if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
				v = v.duplicate(true)
			p[k] = v
		_players.append(p)
