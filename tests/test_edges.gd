class_name TestEdges
extends RefCounted

# §16.2 规则草案 §9 的 32 条边界，一条一个用例。
# 测试层允许直接操作内核字段（force_*），但机器人/视图走公开接口。

const DAO := Rules.Suit.DAO        # 0 刀
const JIAN := Rules.Suit.JIAN      # 1 剑
const ZHANG := Rules.Suit.ZHANG    # 2 掌
const HUAJIN := Rules.Suit.HUAJIN  # 3 化劲

# 铺一个干净的 PLAY 局面：绕过选技能与随机发牌，直接构造精确状态。
static func _start_play(n: int, seed: int) -> GameState:
	var gs := GameState.new(seed, true)  # skills_enabled = true
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
		Helpers.force_hollow(gs, p.id, 6)   # 默认退步安全
	return gs

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

static func _find(events: Array, t: String) -> Dictionary:
	for e in events:
		if e.type == t:
			return e
	return {}

static func _run(name: String, f: Callable) -> void:
	var before: int = Helpers.failures().size()
	f.call()
	if Helpers.failures().size() == before:
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)

static func run_all() -> void:
	print("== test_edges ==")
	_run("边界 1", _edge01)
	_run("边界 2", _edge02)
	_run("边界 3", _edge03)
	_run("边界 4", _edge04)
	_run("边界 5", _edge05)
	_run("边界 6", _edge06)
	_run("边界 7", _edge07)
	_run("边界 8", _edge08)
	_run("边界 9", _edge09)
	_run("边界 10", _edge10)
	_run("边界 11", _edge11)
	_run("边界 12", _edge12)
	_run("边界 13", _edge13)
	_run("边界 14", _edge14)
	_run("边界 15", _edge15)
	_run("边界 16", _edge16)
	_run("边界 17", _edge17)
	_run("边界 18", _edge18)
	_run("边界 19", _edge19)
	_run("边界 20", _edge20)
	_run("边界 21", _edge21)
	_run("边界 22", _edge22)
	_run("边界 23", _edge23)
	_run("边界 24", _edge24)
	_run("边界 25", _edge25)
	_run("边界 26", _edge26)
	_run("边界 27", _edge27)
	_run("边界 28", _edge28)
	_run("边界 29", _edge29)
	_run("边界 30", _edge30)
	_run("边界 31", _edge31)
	_run("边界 32", _edge32)
	_run("边界 33", _edge33)
	_run("边界 27r", _edge27_reveal_path)
	_run("边界 34(选角)", _edge34_char_pick)

# 边界 1：本轮首位出招者能否拆招 → 不能
static func _edge01() -> void:
	var gs := _start_play(3, 1)
	var v: Dictionary = gs.view_for(gs.current_player)
	Helpers.assert_true(not _has(v.legal_actions, "CHALLENGE"), "边界1: 首位 legal 不应含 CHALLENGE")

# 边界 2：轮到你时你手牌已空 → 跳过
static func _edge02() -> void:
	var gs := _start_play(3, 2)
	Helpers.force_hand(gs, 1, [])
	var events := gs.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(events, "SKIPPED"), "边界2: 应发 SKIPPED")
	var sk := _find(events, "SKIPPED")
	Helpers.assert_eq(sk.pid, 1, "边界2: SKIPPED 应是 P1")
	Helpers.assert_eq(gs.current_player, 2, "边界2: current 应跳到 P2")

# 边界 3：上家打出了最后一张牌，你能拆吗 → 能
static func _edge03() -> void:
	var gs := _start_play(3, 3)
	Helpers.force_hand(gs, 1, [DAO])   # P1 只剩 1 张
	gs.current_player = 1
	gs.apply(Action.play(1, [0]))
	Helpers.assert_eq(gs.last_player_who_played, 1, "边界3: 上家应是 P1")
	var v: Dictionary = gs.view_for(2)
	Helpers.assert_true(_has(v.legal_actions, "CHALLENGE"), "边界3: P2 应能拆")

# 边界 4：所有人手牌出尽且无人拆招 → 无人退步，重新发牌
static func _edge04() -> void:
	var gs := _start_play(3, 4)
	Helpers.force_hand(gs, 0, [DAO])
	Helpers.force_hand(gs, 1, [DAO])
	Helpers.force_hand(gs, 2, [DAO])
	gs.apply(Action.play(0, [0]))
	gs.apply(Action.play(1, [0]))
	var events := gs.apply(Action.play(2, [0]))
	var re := _find(events, "ROUND_END")
	Helpers.assert_eq(re.get("retreater", 999), -1, "边界4: retreater 应为 -1")
	Helpers.assert_eq(gs.player(0).steps_taken, 0, "边界4: P0 不应退步")
	Helpers.assert_eq(gs.player(1).steps_taken, 0, "边界4: P1 不应退步")
	Helpers.assert_eq(gs.player(2).steps_taken, 0, "边界4: P2 不应退步")

# 边界 5：有人退步后，其余人未出的手牌全部作废，重新发牌
static func _edge05() -> void:
	var gs := _start_play(3, 5)
	var r0: int = gs.round_number
	Helpers.force_hand(gs, 0, [ZHANG])   # 虚招
	Helpers.force_hollow(gs, 0, 6)       # 退步安全
	gs.apply(Action.play(0, [0]))
	gs.apply(Action.challenge(1))        # P1 拆 P0，P0 虚招退步
	Helpers.assert_eq(gs.round_number, r0 + 1, "边界5: round_number 应 +1")
	Helpers.assert_eq(gs.player(0).steps_taken, 1, "边界5: P0 应退 1 步")
	Helpers.assert_eq(gs.player(1).hand.size(), Rules.HAND_SIZE, "边界5: P1 手牌应重发为 5")

# 边界 6：玩家出局后的顺位 → 移除，跳过
static func _edge06() -> void:
	var gs := _start_play(3, 6)
	gs.player(1).alive = false
	gs.apply(Action.play(0, [0]))
	Helpers.assert_eq(gs.current_player, 2, "边界6: 出局的 P1 应被跳过")

# 边界 7：只剩两人时 → 两人互为上下家
static func _edge07() -> void:
	var gs := _start_play(3, 7)
	gs.player(0).alive = false
	gs.current_player = 1
	gs.apply(Action.play(1, [0]))
	Helpers.assert_eq(gs.current_player, 2, "边界7: 出招后轮到 P2")
	Helpers.assert_eq(gs.last_player_who_played, 1, "边界7: 上家是 P1")
	var v: Dictionary = gs.view_for(2)
	Helpers.assert_true(_has(v.legal_actions, "CHALLENGE"), "边界7: P2 应能拆 P1")

# 边界 8：金钟罩触发后再次退步 → 必坠，steps 不再增加
static func _edge08() -> void:
	var gs := _start_play(3, 8)
	var p0: Dictionary = gs.player(0)
	Helpers.force_skill(gs, 0, Rules.Skill.JINZHONGZHAO)
	p0.has_gap = true
	p0.golden_bell_used = true
	p0.steps_taken = 2
	Helpers.force_hand(gs, 0, [ZHANG])   # 虚招
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "FALL"), "边界8: 应坠崖")
	Helpers.assert_eq(p0.steps_taken, 2, "边界8: steps_taken 不应增加")

# 边界 9：后发制人退 2 步，第 1 步就踩空 → 立即出局，无第 2 步
static func _edge09() -> void:
	var gs := _start_play(3, 9)
	Helpers.force_skill(gs, 0, Rules.Skill.HOUFA)
	gs.player(0).houfa_ready_round = 0
	Helpers.force_hand(gs, 0, [DAO])     # 真招
	Helpers.force_hollow(gs, 1, 1)       # P1 第 1 步踩空
	Helpers.force_steps(gs, 1, 0)
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))   # P1 拆真招，被后发反噬退 2 步
	Helpers.assert_eq(_count(events, "RETREAT"), 1, "边界9: 应只有 1 个 RETREAT")
	Helpers.assert_true(_has(events, "FALL"), "边界9: 应坠崖")

# 边界 10：拆招者持金钟罩，被后发制人罚退 2 步 → 第 1 步金钟罩，第 2 步坠
static func _edge10() -> void:
	var gs := _start_play(3, 10)
	Helpers.force_skill(gs, 0, Rules.Skill.HOUFA)
	gs.player(0).houfa_ready_round = 0
	Helpers.force_skill(gs, 1, Rules.Skill.JINZHONGZHAO)
	Helpers.force_hollow(gs, 1, 1)
	Helpers.force_steps(gs, 1, 0)
	gs.player(1).golden_bell_used = false
	Helpers.force_hand(gs, 0, [DAO])
	gs.apply(Action.play(0, [0]))
	var events := gs.apply(Action.challenge(1))
	Helpers.assert_true(_has(events, "GOLDEN_BELL"), "边界10: 第 1 步应金钟罩")
	Helpers.assert_true(_has(events, "FALL"), "边界10: 第 2 步应坠崖")
	Helpers.assert_eq(_count(events, "RETREAT"), 1, "边界10: 只有 1 个 RETREAT")

# 边界 11：last_player_who_played == -1 时用听劲 → REJECTED
static func _edge11() -> void:
	var gs := _start_play(3, 11)
	Helpers.force_skill(gs, 0, Rules.Skill.TINGJIN)
	gs.last_player_who_played = -1
	var events := gs.apply(Action.use_tingjin(0, 0))
	Helpers.assert_true(_has(events, "REJECTED"), "边界11: 应 REJECTED")

# 边界 12：上家只出 1 张，card_pos=0 成功；card_pos=1 拒绝
static func _edge12() -> void:
	var gs := _start_play(3, 12)
	Helpers.force_hand(gs, 0, [DAO])
	gs.apply(Action.play(0, [0]))          # 上家出 1 张
	Helpers.force_skill(gs, 1, Rules.Skill.TINGJIN)
	gs.current_player = 1
	var ok_events := gs.apply(Action.use_tingjin(1, 0))
	Helpers.assert_true(_has(ok_events, "SKILL_USED"), "边界12: card_pos=0 应成功")
	Helpers.force_skill(gs, 1, Rules.Skill.TINGJIN)  # 恢复次数
	var bad_events := gs.apply(Action.use_tingjin(1, 1))
	Helpers.assert_true(_has(bad_events, "REJECTED"), "边界12: card_pos=1 应拒绝")

# 边界 13：PLAY 阶段用改弦 → REJECTED
static func _edge13() -> void:
	var gs := _start_play(3, 13)
	Helpers.force_skill(gs, 0, Rules.Skill.GAIXIAN)
	var events := gs.apply(Action.use_gaixian(0, DAO))
	Helpers.assert_true(_has(events, "REJECTED"), "边界13: 应 REJECTED")

# 边界 14（v0.9 反转）：技能可重复——全员都可持改弦
static func _edge14() -> void:
	var gs := Helpers.make(4, 14, true)
	for i in 4:
		gs.apply(Action.pick_skill(i, Rules.Skill.GAIXIAN))
	var holders := 0
	for i in 4:
		if gs.player(i).skill == Rules.Skill.GAIXIAN:
			holders += 1
	Helpers.assert_eq(holders, 4, "边界14(v0.9): 技能可重复，4 人都应持改弦")

# 边界 15：辨虚实指定已踏过的石板 → REJECTED
static func _edge15() -> void:
	var gs := _start_play(3, 15)
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	Helpers.force_steps(gs, 0, 2)
	var bad := gs.apply(Action.use_bianxushi(0, 2))
	Helpers.assert_true(_has(bad, "REJECTED"), "边界15: stone<=steps 应拒绝")
	Helpers.force_skill(gs, 0, Rules.Skill.BIANXUSHI)
	var ok := gs.apply(Action.use_bianxushi(0, 3))
	Helpers.assert_true(_has(ok, "SKILL_USED"), "边界15: stone=3 应成功")

# 边界 16：出招超时 → 驱动层送随机 PLAY，状态正常推进
static func _edge16() -> void:
	var gs := _start_play(3, 16)
	# 驱动层超时代出 = 随机挑 1 张打出
	var events := gs.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(events, "PLAYED"), "边界16: 超时代出应正常出牌")
	Helpers.assert_true(not _has(events, "REJECTED"), "边界16: 不应 REJECTED")

# 边界 17/18/19：掉线 → 本步不实现
static func _edge17() -> void:
	print("    SKIP: 边界 17（掉线托管）—— 热座版不实现，见 §1 范围")

static func _edge18() -> void:
	print("    SKIP: 边界 18（掉线重连）—— 热座版不实现，见 §1 范围")

static func _edge19() -> void:
	print("    SKIP: 边界 19（房主掉线转移）—— 热座版不实现，见 §1 范围")

# 边界 20：一局中途人数不足 3 → 游戏继续
static func _edge20() -> void:
	var gs := _start_play(3, 20)
	gs.player(0).alive = false
	Helpers.assert_eq(gs.alive_count(), 2, "边界20: 存活 2 人")
	Helpers.assert_true(gs.phase != Rules.Phase.GAME_OVER, "边界20: 游戏不中止")

# 边界 21：手牌出尽者被跳过后，下一人的上家是再往前最近出过招的人
static func _edge21() -> void:
	var gs := _start_play(4, 21)
	gs.current_player = 1
	Helpers.force_hand(gs, 2, [])   # P2 空手
	gs.apply(Action.play(1, [0]))
	Helpers.assert_eq(gs.current_player, 3, "边界21: 跳过 P2 轮到 P3")
	Helpers.assert_eq(gs.last_player_who_played, 1, "边界21: P3 的上家应是 P1")

# 边界 22：藏拙者超时被代出 → 全场看不到超时（伪读条在驱动层，内核不区分）
static func _edge22() -> void:
	var gs := _start_play(3, 22)
	Helpers.force_skill(gs, 0, Rules.Skill.CANGZHUO)
	# 藏拙是纯视图层技能：不改变任何内核判定
	var events := gs.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(events, "PLAYED"), "边界22: 藏拙者出招正常")
	Helpers.assert_true(not _has(events, "SKILL_USED"), "边界22: 藏拙不应发 SKILL_USED")
	print("    NOTE: 伪读条在驱动层实现（§15.4），第 4 步验证")

# 边界 23：金钟罩触发后的豁口全场可见
static func _edge23() -> void:
	var gs := _start_play(3, 23)
	gs.player(0).has_gap = true
	for pid in 3:
		var v: Dictionary = gs.view_for(pid)
		Helpers.assert_true(v.players[0].has_gap, "边界23: 豁口应对 pid=%d 可见" % pid)

# 边界 24：7 人 new_game → 抛错或返回 null
static func _edge24() -> void:
	var gs := GameState.new(24, true)
	var names := []
	var bots := []
	for i in Rules.MAX_PLAYERS + 1:
		names.append("P%d" % i)
		bots.append(true)
	gs.new_game(names, bots)
	Helpers.assert_eq(gs.player_count(), 0, "边界24: 超上限人数应拒绝初始化")

# 边界 25：3 人局 deck_remaining==5，未发的牌不在任何人 hand
static func _edge25() -> void:
	var gs := Helpers.make(3, 25, false)
	Helpers.assert_eq(gs.deck_remaining, 5, "边界25: deck_remaining 应为 5")
	var hand_total := 0
	for i in 3:
		hand_total += gs.player(i).hand.size()
	Helpers.assert_eq(hand_total, 15, "边界25: 手牌总和应为 15")

# 边界 26：全员选同一技能 → 各得不同技能，randomized.size()==5
static func _edge26() -> void:
	var gs := Helpers.make(4, 26, true)
	var events := []
	for i in 4:
		events.append_array(gs.apply(Action.pick_skill(i, Rules.Skill.JINZHONGZHAO)))
	# v0.9：可重复——全员如愿拿到金钟罩，无人被随机分配
	for i in 4:
		Helpers.assert_eq(gs.player(i).skill, Rules.Skill.JINZHONGZHAO, "边界26(v0.9): 各取所愿")
	var sa := _find(events, "SKILLS_ASSIGNED")
	Helpers.assert_eq(sa.randomized.size(), 0, "边界26(v0.9): 无人被随机分配")

# 边界 27：下一轮由谁先出招
static func _edge27() -> void:
	# a. 退步者存活 → 由他开始
	var gs1 := _start_play(4, 27)
	gs1.round_starter = 0
	gs1._end_round(1)
	Helpers.assert_eq(gs1.round_starter, 1, "边界27a: 退步者存活应由他开始")
	# b. 退步者出局 → 由他的下家开始
	var gs2 := _start_play(4, 28)
	gs2.round_starter = 0
	gs2.player(1).alive = false
	gs2._end_round(1)
	Helpers.assert_eq(gs2.round_starter, 2, "边界27b: 出局应由下家开始")
	# c. 无人退步 → 由原起始者下家开始
	var gs3 := _start_play(4, 29)
	gs3.round_starter = 0
	gs3._end_round(-1)
	Helpers.assert_eq(gs3.round_starter, 1, "边界27c: 无人退步应由原起始者下家开始")

# 边界 28：出招后是否补牌 → 不补，只减不增
static func _edge28() -> void:
	var gs := _start_play(3, 30)
	var before: int = gs.player(0).hand.size()
	gs.apply(Action.play(0, [0, 1]))
	Helpers.assert_true(gs.player(0).hand.size() < before, "边界28: 出牌后手牌应减少")

# 边界 29：之前几手进弃牌堆永不揭示，REVEALED 只含最近一手
static func _edge29() -> void:
	var gs := _start_play(3, 31)
	Helpers.force_hand(gs, 0, [DAO, DAO, DAO])
	Helpers.force_hand(gs, 1, [ZHANG])     # P1 第二手出虚招
	gs.apply(Action.play(0, [0, 1]))       # 第一手 2 张
	gs.apply(Action.play(1, [0]))          # 第二手 1 张
	Helpers.assert_eq(gs.discard_count, 2, "边界29: 第一手应进弃牌堆")
	var events := gs.apply(Action.challenge(2))
	var rev := _find(events, "REVEALED")
	Helpers.assert_eq(rev.cards.size(), 1, "边界29: REVEALED 只含最近一手")

# 边界 30：任何人的 view 不含 hollow_index（详见 test_view）
static func _edge30() -> void:
	var gs := _start_play(3, 32)
	for pid in 3:
		var s := JSON.stringify(gs.view_for(pid))
		Helpers.assert_true(not s.contains("hollow_index"), "边界30: view 不应含 hollow_index")

# 边界 31：场上只剩你一人还有牌（上家=自己）→ 不能拆也不能听劲
static func _edge31() -> void:
	var gs := _start_play(3, 33)
	Helpers.force_hand(gs, 0, [DAO, DAO])
	Helpers.force_hand(gs, 1, [])
	Helpers.force_hand(gs, 2, [])
	gs.current_player = 0
	gs.last_player_who_played = 0   # 上家 = 自己
	var v: Dictionary = gs.view_for(0)
	Helpers.assert_true(not _has(v.legal_actions, "CHALLENGE"), "边界31: 不应能拆")
	Helpers.assert_true(not _has(v.legal_actions, "USE_TINGJIN"), "边界31: 不应能听劲")

# 边界 32：每轮重新洗牌，hand 总和 + deck_remaining == 20
static func _edge32() -> void:
	var gs := Helpers.make(3, 34, false)
	var h1 := 0
	for i in 3:
		h1 += gs.player(i).hand.size()
	Helpers.assert_eq(h1 + gs.deck_remaining, 20, "边界32: 第 1 轮应为 20")
	# 跑完一轮（全员出尽）
	Helpers.force_hand(gs, 0, [DAO])
	Helpers.force_hand(gs, 1, [DAO])
	Helpers.force_hand(gs, 2, [DAO])
	gs.current_player = 0
	gs.apply(Action.play(0, [0]))
	gs.apply(Action.play(1, [0]))
	gs.apply(Action.play(2, [0]))
	var h2 := 0
	for i in 3:
		h2 += gs.player(i).hand.size()
	Helpers.assert_eq(h2 + gs.deck_remaining, 20, "边界32: 第 2 轮应为 20")


# 边界 33：天道检验——其他人出尽后，唯一持牌者的每一手自动亮招
static func _edge33() -> void:
	# a. 虚招被天道拆穿 → 退步
	var gs := _start_play(3, 331)
	Helpers.force_hand(gs, 0, [ZHANG, ZHANG])   # 本轮论刀，掌是虚招
	Helpers.force_hand(gs, 1, [])
	Helpers.force_hand(gs, 2, [])
	gs.current_player = 0
	var ev := gs.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(ev, "HEAVEN_CHECK"), "边界33a: 应触发天道检验")
	Helpers.assert_true(_has(ev, "REVEALED"), "边界33a: 应亮招")
	Helpers.assert_eq(gs.player(0).steps_taken, 1, "边界33a: 虚招应退一步")
	Helpers.assert_true(_has(ev, "ROUND_END"), "边界33a: 本轮应结束")
	# b. 真招 → 不退步，继续由他出下一手
	var gs2 := _start_play(3, 332)
	Helpers.force_hand(gs2, 0, [DAO, DAO])
	Helpers.force_hand(gs2, 1, [])
	Helpers.force_hand(gs2, 2, [])
	gs2.current_player = 0
	var ev2 := gs2.apply(Action.play(0, [0]))
	Helpers.assert_true(_has(ev2, "HEAVEN_CHECK"), "边界33b: 应触发天道检验")
	Helpers.assert_eq(gs2.player(0).steps_taken, 0, "边界33b: 真招不应退步")
	Helpers.assert_true(not _has(ev2, "ROUND_END"), "边界33b: 还有牌，本轮不应结束")
	Helpers.assert_eq(gs2.current_player, 0, "边界33b: 仍轮到他出")
	# c. 真招且是最后一张 → 本轮平安结束，无人退步
	var ev3 := gs2.apply(Action.play(0, [0]))
	var re := _find(ev3, "ROUND_END")
	Helpers.assert_eq(re.get("retreater", 999), -1, "边界33c: 无人退步")
	# d. 天道拆穿不触发后发制人（没有拆招者）
	var gs3 := _start_play(3, 333)
	Helpers.force_skill(gs3, 0, Rules.Skill.HOUFA)
	Helpers.force_hand(gs3, 0, [ZHANG])
	Helpers.force_hand(gs3, 1, [])
	Helpers.force_hand(gs3, 2, [])
	gs3.current_player = 0
	var ev4 := gs3.apply(Action.play(0, [0]))
	Helpers.assert_true(not _has(ev4, "HOUFA_TRIGGERED"), "边界33d: 天道检验不触发后发制人")

# 边界 27 回归：走完整拆招路径时，下一轮起始者 = 退步者本人
static func _edge27_reveal_path() -> void:
	# 冤枉了人：拆招者(P1)退步 → 下一轮应由 P1 先出（旧版 bug：错定为被拆者 P0）
	var gs := _start_play(3, 271)
	Helpers.force_hand(gs, 0, [DAO])            # P0 出真招
	Helpers.force_hand(gs, 1, [DAO, DAO])
	Helpers.force_hand(gs, 2, [DAO, DAO])
	Helpers.force_hollow(gs, 1, 6)              # 保证 P1 退一步后活着
	gs.current_player = 0
	gs.apply(Action.play(0, [0]))
	gs.apply(Action.challenge(1))               # P1 拆真招，被冤枉，P1 退步
	Helpers.assert_eq(gs.round_starter, 1, "边界27r: 冤枉人后应由拆招者(退步者)开始下一轮")


# 边界 34（v0.9）：报门户阶段自由选皮囊，可重复，全场视图可见；PLAY 阶段不可改
static func _edge34_char_pick() -> void:
	var gs := Helpers.make(3, 340, true)
	gs.apply(Action.pick_char(0, 5))
	gs.apply(Action.pick_char(1, 5))         # 允许重复
	Helpers.assert_eq(gs.player(0).char_id, 5, "边界34: P0 选中 5 号")
	Helpers.assert_eq(gs.player(1).char_id, 5, "边界34: 重复皮囊允许")
	Helpers.assert_eq(int(gs.view_for(2).players[0].char_id), 5, "边界34: 皮囊全场可见")
	var ev := gs.apply(Action.pick_char(0, 9))
	Helpers.assert_true(ev.size() == 1 and ev[0].type == "REJECTED", "边界34: 非法皮囊号拒绝")
	for i in 3:
		gs.apply(Action.pick_skill(i, i))    # 结束报门户
	var ev2 := gs.apply(Action.pick_char(0, 1))
	Helpers.assert_true(ev2.size() == 1 and ev2[0].type == "REJECTED", "边界34: 开局后不可改皮囊")
