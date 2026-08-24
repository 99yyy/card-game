class_name Helpers
extends RefCounted

# 测试工具（§16.1）。测试层可以接触内核内部字段（force_* 就是干这个的），
# 但机器人驱动必须走 view_for / legal_actions（铁律 3 的活体测试）。

static var _failures: Array = []

static func reset() -> void:
	_failures = []

static func failures() -> Array:
	return _failures

static func assert_eq(a, b, msg := "") -> void:
	if a == b:
		return
	_failures.append("FAIL: %s\n  expected: %s\n  actual:   %s" % [msg, var_to_str(b), var_to_str(a)])

static func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		_failures.append("FAIL: %s (expected true)" % msg)

# ---------- 构造 ----------
static func make(n_players: int, seed: int, skills := true) -> GameState:
	var gs := GameState.new(seed, skills)
	var names := []
	var bots := []
	for i in n_players:
		names.append("P%d" % i)
		bots.append(true)
	gs.new_game(names, bots)
	return gs

static func force_hand(gs: GameState, pid: int, cards: Array) -> void:
	gs._players[pid].hand = cards.duplicate()

static func force_hollow(gs: GameState, pid: int, idx: int) -> void:
	gs._players[pid].hollow_index = idx

static func force_skill(gs: GameState, pid: int, skill: int) -> void:
	var p: Dictionary = gs._players[pid]
	p.skill = skill
	p.skill_uses_left = Rules.SKILL_USES[skill]
	p.houfa_ready_round = 0

static func force_steps(gs: GameState, pid: int, n: int) -> void:
	gs._players[pid].steps_taken = n

static func names_n(n: int) -> Array:
	var a := []
	for i in n:
		a.append("P%d" % i)
	return a

static func bots_n(n: int) -> Array:
	var a := []
	for i in n:
		a.append(true)
	return a

static func has_event(events: Array, t: String) -> bool:
	for e in events:
		if e.get("type", "") == t:
			return true
	return false

# ---------- 单步驱动（机器人自动决策，走 view_for） ----------
static func step(gs: GameState) -> Array:
	match gs.phase:
		Rules.Phase.GAME_OVER:
			return []
		Rules.Phase.SKILL_PICK:
			for p in gs._players:
				if p.alive and p.pending_skill_pick == Rules.Skill.NONE:
					var a: Dictionary = Bot.decide(gs.view_for(p.id), gs._rng)
					return gs.apply(a)
			return []
		Rules.Phase.SWAP_WINDOW:
			for p in gs._players:
				if p.alive and p.skill == Rules.Skill.GAIXIAN and p.skill_uses_left > 0:
					var a: Dictionary = Bot.decide(gs.view_for(p.id), gs._rng)
					return gs.apply(a)
			return gs.apply(Action.pass_window())
		_:
			if gs.current_player < 0:
				return []
			var a: Dictionary = Bot.decide(gs.view_for(gs.current_player), gs._rng)
			return gs.apply(a)

static func play_until(gs: GameState, pred: Callable) -> void:
	var guard := 0
	while not pred.call() and guard < 100000:
		guard += 1
		step(gs)

# ---------- 整局跑（收集事件，轮数上限防死循环） ----------
static func run_full(gs: GameState, max_rounds := 500) -> Array:
	var events := []
	var guard := 0
	while gs.phase != Rules.Phase.GAME_OVER and guard < 200000:
		guard += 1
		events.append_array(step(gs))
		if gs.round_number > max_rounds:
			_failures.append("FAIL: 超过轮数上限 %d（疑似死循环）" % max_rounds)
			break
	return events
