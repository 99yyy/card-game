class_name TestModes
extends RefCounted

# 三个新玩法的内核测试：心魔变体规则 + 暗器/递毒全机器人跑通与关键判定

static func run_all() -> void:
	print("== test_modes ==")
	_t("心魔：单出限制与连坐", _xinmo_rules)
	_t("心魔：100 局机器人局终局", _xinmo_games)
	_t("暗器：叫价加码与清点判定", _dice_rules)
	_t("暗器：150 局机器人局终局", _dice_games)
	_t("递毒：递/信/转赠/毒发", _poison_rules)
	_t("递毒：150 局机器人局终局", _poison_games)
	_t("递毒：机密裁剪（偷看仅当事人）", _poison_secret)

static func _t(nm: String, f: Callable) -> void:
	var before: int = Helpers.failures().size()
	f.call()
	print("  [%s] %s" % ["PASS" if Helpers.failures().size() == before else "FAIL", nm])

# ---------- 心魔 ----------
static func _xinmo_rules() -> void:
	var gs := GameState.new(901, true, true)
	gs.new_game(["a","b","c"], [true,true,true])
	for i in 3:
		gs.apply(Action.pick_skill(i, Rules.Skill.TINGJIN))
	gs.phase = Rules.Phase.PLAY
	gs.current_suit = Rules.Suit.DAO
	gs.current_player = 0
	gs.round_starter = 0
	Helpers.force_hand(gs, 0, [Rules.SUIT_XINMO, Rules.Suit.DAO])
	Helpers.force_hand(gs, 1, [Rules.Suit.DAO, Rules.Suit.DAO])
	Helpers.force_hand(gs, 2, [Rules.Suit.DAO, Rules.Suit.DAO])
	for i in 3:
		Helpers.force_hollow(gs, i, 6)
	# 心魔+其他牌混出 → 拒绝（边界 35）
	var ev := gs.apply(Action.play(0, [0, 1]))
	Helpers.assert_true(ev.size() == 1 and ev[0].type == "REJECTED", "心魔混出应拒绝")
	# 单出心魔 → 合法；被拆 → 连坐（除出牌者全场退步）
	gs.apply(Action.play(0, [0]))
	var ev2 := gs.apply(Action.challenge(1))
	Helpers.assert_true(Helpers.has_event(ev2, "XINMO_TRIGGERED"), "应触发心魔连坐")
	Helpers.assert_eq(gs.player(0).steps_taken, 0, "出牌者全身而退")
	Helpers.assert_eq(gs.player(1).steps_taken, 1, "拆招者退步")
	Helpers.assert_eq(gs.player(2).steps_taken, 1, "旁观者连坐")
	Helpers.assert_true(not Helpers.has_event(ev2, "HOUFA_TRIGGERED"), "不触发后发制人")

static func _xinmo_games() -> void:
	for seed in range(1, 101):
		var n := 2 + (seed % 3)
		var gs := GameState.new(seed + 9000, true, true)
		gs.new_game(Helpers.names_n(n), Helpers.bots_n(n))
		var events := Helpers.run_full(gs)
		Helpers.assert_true(gs.phase == Rules.Phase.GAME_OVER, "seed %d 未终局" % seed)

# ---------- 暗器 ----------
static func _dice_rules() -> void:
	var g := GameDice.new(902)
	g.new_game(["a","b","c"], [true,true,true])
	g.force_resolve_skill_pick()
	Helpers.assert_eq(g.phase, Rules.Phase.PLAY, "开局进 PLAY")
	Helpers.assert_eq(g.player(0).dice.size(), 5, "开局 5 枚")
	var cp: int = g.current_player
	# 首叫
	g.apply({"type": "BID", "pid": cp, "n": 2, "face": 1})
	# 不加码 → 拒绝
	var nxt: int = g.current_player
	var ev := g.apply({"type": "BID", "pid": nxt, "n": 2, "face": 1})
	Helpers.assert_true(ev[0].type == "REJECTED", "同价应拒绝")
	ev = g.apply({"type": "BID", "pid": nxt, "n": 1, "face": 4})
	Helpers.assert_true(ev[0].type == "REJECTED", "降 N 应拒绝")
	# 合法加码 + 拆招 → 有清点事件、有人退步
	g.apply({"type": "BID", "pid": nxt, "n": 2, "face": 3})
	var ch: int = g.current_player
	var ev2 := g.apply({"type": "CHALLENGE", "pid": ch})
	Helpers.assert_true(Helpers.has_event(ev2, "DICE_REVEALED"), "应亮囊清点")
	Helpers.assert_true(Helpers.has_event(ev2, "RETREAT") or Helpers.has_event(ev2, "FALL"), "必有人退步")

static func _dice_games() -> void:
	for seed in range(1, 151):
		var n := 2 + (seed % 3)
		var g := GameDice.new(seed + 7000)
		g.new_game(Helpers.names_n(n), Helpers.bots_n(n))
		g.force_resolve_skill_pick()
		var guard := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		while g.phase != Rules.Phase.GAME_OVER and guard < 20000:
			guard += 1
			g.apply(GameDice.bot_decide(g.view_for(g.current_player), rng))
		Helpers.assert_true(g.phase == Rules.Phase.GAME_OVER, "暗器 seed %d 未终局" % seed)
		Helpers.assert_true(g.winner >= 0 and g.winner < n, "暗器 seed %d 胜者非法" % seed)

# ---------- 递毒 ----------
static func _poison_rules() -> void:
	var g := GamePoison.new(903)
	g.new_game(["a","b","c"], [true,true,true])
	g.force_resolve_skill_pick()
	var total := 0
	for i in 3:
		total += g.player(i).hand.size()
	Helpers.assert_eq(total, 40, "40 张全发完")
	var cp: int = g.current_player
	var card: int = g.player(cp).hand[0]
	var tgt := (cp + 1) % 3
	g.apply({"type": "OFFER", "pid": cp, "card_index": 0, "target": tgt, "claim": card})
	# 收礼人视图能看到牌面；第三人不能
	Helpers.assert_eq(int(g.view_for(tgt).you.peeked), card, "收礼人可窥牌面")
	var third := (cp + 2) % 3
	Helpers.assert_eq(int(g.view_for(third).you.peeked), -1, "第三人不可见")
	# 信（声称为真）→ 出手人吃
	var ev := g.apply({"type": "RESPOND", "pid": tgt, "guess": true})
	Helpers.assert_true(Helpers.has_event(ev, "POISON_EATEN"), "应吃毒")
	Helpers.assert_eq(g.player(cp).collected[card], 1, "说真话被信 → 出手人吃")
	# 毒发：喂满 4 只
	var g2 := GamePoison.new(904)
	g2.new_game(["a","b"], [true,true])
	g2.force_resolve_skill_pick()
	g2.player(1).collected = [3, 0, 0, 0, 0]
	g2.player(0).hand = [0, 0]
	g2.player(1).hand = [1]
	g2.current_player = 0
	g2.apply({"type": "OFFER", "pid": 0, "card_index": 0, "target": 1, "claim": 1})
	var ev3 := g2.apply({"type": "RESPOND", "pid": 1, "guess": true})   # 判错 → 自己吃第 4 只蛇
	Helpers.assert_true(Helpers.has_event(ev3, "POISONED_OUT"), "同种 4 只应毒发")
	Helpers.assert_eq(g2.winner, 0, "只剩一人 → 胜")

static func _poison_games() -> void:
	for seed in range(1, 151):
		var n := 2 + (seed % 3)
		var g := GamePoison.new(seed + 8000)
		g.new_game(Helpers.names_n(n), Helpers.bots_n(n))
		g.force_resolve_skill_pick()
		var guard := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		while g.phase != Rules.Phase.GAME_OVER and guard < 20000:
			guard += 1
			g.apply(GamePoison.bot_decide(g.view_for(g.current_player), rng))
		Helpers.assert_true(g.phase == Rules.Phase.GAME_OVER, "递毒 seed %d 未终局" % seed)

static func _poison_secret() -> void:
	# 在途牌面绝不进非收礼人视图（含 JSON 全文扫描）
	var g := GamePoison.new(905)
	g.new_game(["a","b","c"], [true,true,true])
	g.force_resolve_skill_pick()
	var cp: int = g.current_player
	g.apply({"type": "OFFER", "pid": cp, "card_index": 0, "target": (cp + 1) % 3, "claim": 2})
	var third := (cp + 2) % 3
	var st := JSON.stringify(g.view_for(third))
	Helpers.assert_true(not st.contains("offer_card"), "offer_card 不得出现在视图")
	Helpers.assert_true(not st.contains("hollow"), "无关机密不得出现")
