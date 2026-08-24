class_name TestSkills
extends RefCounted

# §16.3 六技能各测：正常触发 / 条件不满足不触发 / 次数耗尽 / 冷却中不触发 / skills_enabled=false 不生效。

const DAO := Rules.Suit.DAO
const ZHANG := Rules.Suit.ZHANG
const HUAJIN := Rules.Suit.HUAJIN

static func _has(events: Array, t: String) -> bool:
	for e in events:
		if e.type == t:
			return true
	return false

static func _count(events: Array, t: String) -> int:
	var c := 0
	for e in events:
		if e.type == t:
			c += 1
	return c

static func _start_play(n: int, seed: int, skills := true) -> GameState:
	var gs := GameState.new(seed, skills)
	var names := []
	var bots := []
	for i in n:
		names.append("P%d" % i)
		bots.append(true)
	gs.new_game(names, bots)
	gs.phase = Rules.Phase.PLAY
	gs.round_number = 5
	gs.current_suit = DAO
	gs.current_player = 0
	gs.round_starter = 0
	gs.last_player_who_played = -1
	gs.last_played_cards = []
	gs.discard_count = 0
	for p in gs._players:
		Helpers.force_hand(gs, p.id, [DAO, DAO, DAO])
		Helpers.force_hollow(gs, p.id, 6)
	return gs

static func _run(name: String, f: Callable) -> void:
	var before: int = Helpers.failures().size()
	f.call()
	print("  [%s] %s" % ["PASS" if Helpers.failures().size() == before else "FAIL", name])

static func run_all() -> void:
	print("== test_skills ==")
	_run("金钟罩：正常触发", _jzz_normal)
	_run("金钟罩：无技能则直接坠崖", _jzz_absent)
	_run("金钟罩：豁口后必坠", _jzz_gap)
	_run("金钟罩：skills_off 不触发", _jzz_off)
	_run("听劲：正常触发", _tj_normal)
	_run("听劲：次数耗尽", _tj_exhausted)
	_run("听劲：上家未出招不触发", _tj_no_last)
	_run("听劲：skills_off 不生效", _tj_off)
	_run("藏拙：纯视图层无事件", _cz_passive)
	_run("后发制人：正常反噬 2 步", _hf_normal)
	_run("后发制人：冷却中不触发", _hf_cooldown)
	_run("后发制人：skills_off 不触发", _hf_off)
	_run("改弦：正常触发", _gx_normal)
	_run("改弦：次数耗尽", _gx_exhausted)
	_run("改弦：非窗口阶段不触发", _gx_wrong_phase)
	_run("改弦：skills_off 不生效", _gx_off)
	_run("辨虚实：正常触发", _bxs_normal)
	_run("辨虚实：已踏过石板拒绝", _bxs_stepped)
	_run("辨虚实：次数耗尽", _bxs_exhausted)
	_run("辨虚实：skills_off 不生效", _bxs_off)

# ---------- 金钟罩 ----------
static func _jzz_normal() -> void:
	var gs := _start_play(3, 1)
	var p0: Dictionary = gs.player(0)
	Helpers.force_skill(gs, 0, Rules.Skill.JINZHONGZHAO)
	Helpers.force_hollow(gs, 0, 2)
	Helpers.force_steps(gs, 0, 1)
	Helpers.force_hand(gs, 0, [ZHANG])   # 虚招 → 退步踩空
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "GOLDEN_BELL"), "金钟罩应触发")
	Helpers.assert_true(not _has(events, "FALL"), "不应坠崖")
	Helpers.assert_true(p0.has_gap, "应留下豁口")
	Helpers.assert_eq(p0.steps_taken, 2, "steps 应为 2")

static func _jzz_absent() -> void:
	var gs := _start_play(3, 2)
	Helpers.force_hollow(gs, 0, 1)
	Helpers.force_steps(gs, 0, 0)
	Helpers.force_hand(gs, 0, [ZHANG])
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "FALL"), "无金钟罩应坠崖")

static func _jzz_gap() -> void:
	var gs := _start_play(3, 3)
	var p0: Dictionary = gs.player(0)
	Helpers.force_skill(gs, 0, Rules.Skill.JINZHONGZHAO)
	p0.has_gap = true
	p0.golden_bell_used = true
	p0.steps_taken = 2
	Helpers.force_hand(gs, 0, [ZHANG])
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "FALL"), "豁口后再退应坠崖")
	Helpers.assert_eq(p0.steps_taken, 2, "steps 不应再增")

static func _jzz_off() -> void:
	var gs := _start_play(3, 4, false)
	var p0: Dictionary = gs.player(0)
	Helpers.force_skill(gs, 0, Rules.Skill.JINZHONGZHAO)
	Helpers.force_hollow(gs, 0, 1)
	Helpers.force_steps(gs, 0, 0)
	Helpers.force_hand(gs, 0, [ZHANG])
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "FALL"), "skills_off 时金钟罩不生效")

# ---------- 听劲 ----------
static func _tj_normal() -> void:
	var gs := _start_play(3, 5)
	Helpers.force_hand(gs, 0, [DAO])
	gs.apply(Action.play(0, [0]))   # 上家 P0 出 1 张刀
	Helpers.force_skill(gs, 1, Rules.Skill.TINGJIN)
	gs.current_player = 1
	var events := gs.apply(Action.use_tingjin(1, 0))
	Helpers.assert_true(_has(events, "SKILL_USED"), "听劲应触发")
	Helpers.assert_eq(gs.player(1).listen_result[str(gs.round_number)], DAO, "听劲应看到刀")
	Helpers.assert_eq(gs.player(1).skill_uses_left, 1, "次数应剩 1")
	Helpers.assert_eq(gs.current_player, 1, "听劲不应消耗行动权")

static func _tj_exhausted() -> void:
	var gs := _start_play(3, 6)
	Helpers.force_hand(gs, 0, [DAO])
	gs.apply(Action.play(0, [0]))
	Helpers.force_skill(gs, 1, Rules.Skill.TINGJIN)
	gs.current_player = 1
	gs.player(1).skill_uses_left = 0
	var events := gs.apply(Action.use_tingjin(1, 0))
	Helpers.assert_true(_has(events, "REJECTED"), "次数耗尽应拒绝")

static func _tj_no_last() -> void:
	var gs := _start_play(3, 7)
	Helpers.force_skill(gs, 0, Rules.Skill.TINGJIN)
	gs.current_player = 0
	gs.last_player_who_played = -1
	var events := gs.apply(Action.use_tingjin(0, 0))
	Helpers.assert_true(_has(events, "REJECTED"), "上家未出招应拒绝")

static func _tj_off() -> void:
	var gs := _start_play(3, 8, false)
	Helpers.force_hand(gs, 0, [DAO])
	gs.apply(Action.play(0, [0]))
	Helpers.force_skill(gs, 1, Rules.Skill.TINGJIN)
	gs.current_player = 1
	var events := gs.apply(Action.use_tingjin(1, 0))
	Helpers.assert_true(_has(events, "REJECTED"), "skills_off 应拒绝")

# ---------- 藏拙 ----------
static func _cz_passive() -> void:
	var gs := _start_play(3, 9)
	Helpers.force_skill(gs, 0, Rules.Skill.CANGZHUO)
	var events := gs.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(events, "PLAYED"), "藏拙者出招正常")
	Helpers.assert_true(not _has(events, "SKILL_USED"), "藏拙是被动，无 SKILL_USED")
	Helpers.assert_eq(gs.player(0).skill_uses_left, Rules.UNLIMITED, "藏拙常驻")

# ---------- 后发制人 ----------
static func _hf_normal() -> void:
	var gs := _start_play(3, 10)
	Helpers.force_skill(gs, 0, Rules.Skill.HOUFA)
	gs.player(0).houfa_ready_round = 0
	Helpers.force_hand(gs, 0, [DAO])    # 真招
	Helpers.force_hollow(gs, 1, 6)
	Helpers.force_steps(gs, 1, 0)
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))   # P1 拆真招，被反噬
	Helpers.assert_true(_has(events, "HOUFA_TRIGGERED"), "后发应触发")
	Helpers.assert_eq(_count(events, "RETREAT"), 2, "应退 2 步")
	Helpers.assert_eq(gs.player(1).steps_taken, 2, "P1 应退 2 步")

static func _hf_cooldown() -> void:
	var gs := _start_play(3, 11)
	Helpers.force_skill(gs, 0, Rules.Skill.HOUFA)
	gs.player(0).houfa_ready_round = gs.round_number + 1   # 冷却中
	Helpers.force_hand(gs, 0, [DAO])
	Helpers.force_hollow(gs, 1, 6)
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(not _has(events, "HOUFA_TRIGGERED"), "冷却中不应触发")
	Helpers.assert_eq(_count(events, "RETREAT"), 1, "应只退 1 步")

static func _hf_off() -> void:
	var gs := _start_play(3, 12, false)
	Helpers.force_skill(gs, 0, Rules.Skill.HOUFA)
	gs.player(0).houfa_ready_round = 0
	Helpers.force_hand(gs, 0, [DAO])
	Helpers.force_hollow(gs, 1, 6)
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(not _has(events, "HOUFA_TRIGGERED"), "skills_off 不应触发")

# ---------- 改弦 ----------
static func _gx_normal() -> void:
	var gs := GameState.new(13, true)
	gs._players = []
	var names := ["P0", "P1", "P2"]
	var bots := [true, true, true]
	gs.new_game(names, bots)
	# 直接构造 SWAP_WINDOW 局面
	gs.phase = Rules.Phase.SWAP_WINDOW
	gs.current_suit = DAO
	Helpers.force_skill(gs, 0, Rules.Skill.GAIXIAN)
	var events := gs.apply(Action.use_gaixian(0, ZHANG))
	Helpers.assert_true(_has(events, "SUIT_CHANGED"), "改弦应触发")
	Helpers.assert_eq(gs.current_suit, ZHANG, "路数应改为掌")
	Helpers.assert_eq(gs.suit_changed_by, 0, "改弦者应是 P0")

static func _gx_exhausted() -> void:
	var gs := _start_play(3, 14)
	gs.phase = Rules.Phase.SWAP_WINDOW
	Helpers.force_skill(gs, 0, Rules.Skill.GAIXIAN)
	gs.player(0).skill_uses_left = 0
	var events := gs.apply(Action.use_gaixian(0, ZHANG))
	Helpers.assert_true(_has(events, "REJECTED"), "次数耗尽应拒绝")

static func _gx_wrong_phase() -> void:
	var gs := _start_play(3, 15)
	Helpers.force_skill(gs, 0, Rules.Skill.GAIXIAN)
	var events := gs.apply(Action.use_gaixian(0, ZHANG))
	Helpers.assert_true(_has(events, "REJECTED"), "PLAY 阶段应拒绝")

static func _gx_off() -> void:
	var gs := _start_play(3, 16, false)
	gs.phase = Rules.Phase.SWAP_WINDOW
	Helpers.force_skill(gs, 0, Rules.Skill.GAIXIAN)
	var events := gs.apply(Action.use_gaixian(0, ZHANG))
	Helpers.assert_true(_has(events, "REJECTED"), "skills_off 应拒绝")

# ---------- 辨虚实 ----------
static func _bxs_normal() -> void:
	var gs := _start_play(3, 17)
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	Helpers.force_hollow(gs, 0, 4)
	var events := gs.apply(Action.use_bianxushi(0, 4))
	Helpers.assert_true(_has(events, "SKILL_USED"), "辨虚实应触发")
	Helpers.assert_eq(gs.player(0).probe_result["4"], true, "第 4 格应是虚石")
	Helpers.assert_eq(gs.current_player, 0, "辨虚实不应消耗行动权")

static func _bxs_stepped() -> void:
	var gs := _start_play(3, 18)
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	Helpers.force_steps(gs, 0, 2)
	var events := gs.apply(Action.use_bianxushi(0, 1))
	Helpers.assert_true(_has(events, "REJECTED"), "已踏过的石板应拒绝")

static func _bxs_exhausted() -> void:
	var gs := _start_play(3, 19)
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	gs.player(0).skill_uses_left = 0
	var events := gs.apply(Action.use_bianxushi(0, 4))
	Helpers.assert_true(_has(events, "REJECTED"), "次数耗尽应拒绝")

static func _bxs_off() -> void:
	var gs := _start_play(3, 20, false)
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	var events := gs.apply(Action.use_bianxushi(0, 4))
	Helpers.assert_true(_has(events, "REJECTED"), "skills_off 应拒绝")
