class_name Bot
extends RefCounted

# 机器人决策（§13）。只接收 view，绝不接触 GameState（铁律 3 的活体测试）。
# 机器人是测试脚手架，不是卖点（规则 §10）：首版随机时机、随机合法目标发动技能。

static func decide(view: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var me: Dictionary = view.you
	var legal: Array = view.legal_actions
	var phase: int = view.phase

	# ---- 报门户（选技能）----
	if phase == Rules.Phase.SKILL_PICK:
		if _has_type(legal, "PICK_SKILL"):
			var s: int = rng.randi_range(0, Rules.ALL_SKILLS.size() - 1)
			return {"type": "PICK_SKILL", "pid": me.id, "skill": s}
		return {}

	# ---- 改弦窗口 ----
	if phase == Rules.Phase.SWAP_WINDOW:
		if _has_type(legal, "USE_GAIXIAN"):
			if rng.randf() < 0.5:
				return {"type": "USE_GAIXIAN", "pid": me.id,
						"suit": rng.randi_range(0, Rules.PLAYABLE_SUITS.size() - 1)}
		return {"type": "PASS_WINDOW"}

	# ---- 出招阶段：随机发动主动技能（不消耗行动权，规则 §4.4）----
	if _has_type(legal, "USE_TINGJIN"):
		if rng.randf() < 0.4:
			var cnt: int = view.last_played_count
			return {"type": "USE_TINGJIN", "pid": me.id,
					"card_pos": rng.randi_range(0, cnt - 1)}
	if _has_type(legal, "USE_BIANXUSHI"):
		if rng.randf() < 0.3:
			var stones: Array = _bianxushi_stones(legal)
			if stones.size() > 0:
				return {"type": "USE_BIANXUSHI", "pid": me.id,
						"stone": stones[rng.randi_range(0, stones.size() - 1)]}

	# ---- 拆招（§13）----
	var can_challenge := _has_type(legal, "CHALLENGE")
	if can_challenge:
		var p := 0.15
		var cnt: int = view.last_played_count
		if cnt == 3:
			p += 0.25
		elif cnt == 2:
			p += 0.10
		# 我手里真牌很多 → 别人手里应该没多少
		var mine := 0
		for c in me.hand:
			if c == view.current_suit or c == Rules.Suit.HUAJIN:
				mine += 1
		if mine >= 5:
			p += 0.30
		if me.steps_taken >= 3:
			p *= 0.40            # 怕死
		var up: Dictionary = view.players[view.last_player_who_played]
		if view.skills_enabled and up.skill == Rules.Skill.HOUFA \
			and view.round_number >= up.houfa_ready_round:
			p *= 0.30            # 更怕
		if up.steps_taken >= 4:
			p += 0.15            # 赌他死
		if rng.randf() < clampf(p, 0.0, 0.95):
			return {"type": "CHALLENGE", "pid": me.id}

	# ---- 出牌 ----
	# 心魔（若在手中）：三成概率单独打出，否则多张组合里绝不混它（只能单出）
	var xinmo_at := -1
	for xi in me.hand.size():
		if me.hand[xi] == Rules.SUIT_XINMO:
			xinmo_at = xi
			break
	if xinmo_at >= 0 and rng.randf() < 0.3:
		return {"type": "PLAY", "pid": me.id, "indices": [xinmo_at]}
	var truths := []
	for i in me.hand.size():
		if me.hand[i] == view.current_suit or me.hand[i] == Rules.Suit.HUAJIN:
			truths.append(i)
	if truths.is_empty() and xinmo_at >= 0:
		return {"type": "PLAY", "pid": me.id, "indices": [xinmo_at]}
	if truths.size() >= 1:
		var r := rng.randf()
		var n := 1 if r < 0.60 else (2 if r < 0.90 else 3)
		n = mini(n, truths.size())
		return {"type": "PLAY", "pid": me.id, "indices": truths.slice(0, n)}
	return {"type": "PLAY", "pid": me.id,
			"indices": [rng.randi_range(0, me.hand.size() - 1)]}

# ---- 工具 ----
static func _has_type(legal: Array, t: String) -> bool:
	for a in legal:
		if a.get("type", "") == t:
			return true
	return false

static func _bianxushi_stones(legal: Array) -> Array:
	var out := []
	for a in legal:
		if a.get("type", "") == "USE_BIANXUSHI":
			out.append(a.stone)
	return out
