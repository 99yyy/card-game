class_name TestRules
extends RefCounted

# §16.5 内核基础测试：
# 1. 200 局全机器人：不崩、恰有 1 胜者、无死循环
# 2. 可复现：同 seed 跑两次事件序列完全一致
# 3. 序列化往返：跑到第 5 轮 → to_dict → from_dict → 继续跑完，事件序列与不中断一致
# 4. 统计输出

static func run_all() -> void:
	print("== test_rules ==")
	test_200_games()
	test_reproducible()
	test_serialization_roundtrip()
	test_stats()

static func _names(n: int) -> Array:
	var a := []
	for i in n:
		a.append("P%d" % i)
	return a

static func _bots(n: int) -> Array:
	var a := []
	for i in n:
		a.append(true)
	return a

static func _event_str(gs: GameState) -> String:
	# 复用 run 逻辑：跑完整局，返回事件序列的 JSON
	var events := []
	var guard := 0
	while gs.phase != Rules.Phase.GAME_OVER and guard < 200000:
		guard += 1
		events.append_array(Helpers.step(gs))
	return JSON.stringify(events)

static func test_200_games() -> void:
	var ok := 0
	for seed in range(1, 201):
		var n := 2 + (seed % 3)          # 2..4 人，均匀铺开
		var gs := Helpers.make(n, seed, true)
		var events := Helpers.run_full(gs)
		if gs.phase != Rules.Phase.GAME_OVER:
			Helpers.assert_true(false, "seed %d: 未正常结束" % seed)
			continue
		var winners := 0
		for e in events:
			if e.type == "GAME_OVER":
				winners += 1
		Helpers.assert_eq(winners, 1, "seed %d: GAME_OVER 事件数应为 1" % seed)
		Helpers.assert_true(gs.winner >= 0 and gs.winner < n, "seed %d: winner 非法" % seed)
		ok += 1
	print("200 局完成，正常结束 %d 局" % ok)

static func test_reproducible() -> void:
	var n := 4
	var a := Helpers.make(n, 12345, true)
	var b := Helpers.make(n, 12345, true)
	var sa := _event_str(a)
	var sb := _event_str(b)
	Helpers.assert_eq(sa, sb, "同 seed 两次运行事件序列应一致")
	print("可复现：", "通过" if sa == sb else "失败")

static func test_serialization_roundtrip() -> void:
	var n := 4
	var seed := 999
	# 不中断地跑完
	var full := Helpers.make(n, seed, true)
	var full_events := _event_str(full)

	# 跑到第 5 轮（或结束），序列化，恢复，继续跑完
	var gs := Helpers.make(n, seed, true)
	var guard := 0
	while gs.round_number < 5 and gs.phase != Rules.Phase.GAME_OVER and guard < 100000:
		guard += 1
		Helpers.step(gs)
	var d := gs.to_dict()
	var gs2 := GameState.new()
	gs2.from_dict(d)
	var remaining_events := []
	var guard2 := 0
	while gs2.phase != Rules.Phase.GAME_OVER and guard2 < 200000:
		guard2 += 1
		remaining_events.append_array(Helpers.step(gs2))
	# 重建整体事件串：恢复后的后半段应与 full 的后半段一致
	# 简单起见：把 full_events 拆成「前 guard 步」和「后」，与恢复段比对
	# 由于 step 产生的事件数不固定，改用「恢复点之后 full 继续跑」来对齐：
	var full_continue := Helpers.make(n, seed, true)
	var guard3 := 0
	while full_continue.round_number < 5 and full_continue.phase != Rules.Phase.GAME_OVER and guard3 < 100000:
		guard3 += 1
		Helpers.step(full_continue)
	var full_remaining := []
	var guard4 := 0
	while full_continue.phase != Rules.Phase.GAME_OVER and guard4 < 200000:
		guard4 += 1
		full_remaining.append_array(Helpers.step(full_continue))
	Helpers.assert_eq(JSON.stringify(remaining_events), JSON.stringify(full_remaining),
		"序列化往返后事件序列应一致")
	print("序列化往返：", "通过" if JSON.stringify(remaining_events) == JSON.stringify(full_remaining) else "失败")

static func test_stats() -> void:
	print("== 统计（skills_enabled=true）==")
	var total_rounds := 0
	var total_retreats := 0
	var skill_wins := {}
	var n_games := 100
	for seed in range(1001, 1001 + n_games):
		var n := 2 + (seed % 3)
		var gs := Helpers.make(n, seed, true)
		var events := Helpers.run_full(gs)
		total_rounds += gs.round_number
		for e in events:
			if e.type == "RETREAT":
				total_retreats += 1
		var w := gs.winner
		var s: int = gs._players[w].skill
		if not skill_wins.has(s):
			skill_wins[s] = 0
		skill_wins[s] += 1
	print("  局数 %d，平均轮数 %.2f，平均退步 %.2f" %
		[n_games, float(total_rounds) / n_games, float(total_retreats) / n_games])
	var line := "  各技能胜场: "
	for s in Rules.ALL_SKILLS:
		line += "%s=%d " % [Rules.SKILL_NAMES[s], skill_wins.get(s, 0)]
	print(line)

	print("== 统计（skills_enabled=false 对照）==")
	var total_rounds2 := 0
	var total_retreats2 := 0
	for seed in range(2001, 2001 + n_games):
		var n := 2 + (seed % 3)
		var gs := Helpers.make(n, seed, false)
		var events := Helpers.run_full(gs)
		total_rounds2 += gs.round_number
		for e in events:
			if e.type == "RETREAT":
				total_retreats2 += 1
	print("  局数 %d，平均轮数 %.2f，平均退步 %.2f" %
		[n_games, float(total_rounds2) / n_games, float(total_retreats2) / n_games])


# §17 第 5 步要交回的机器人局数据：技能选择频率 + 各技能胜率 + 平均轮数 + 退步次数。
static func run_report() -> void:
	print("== 第 5 步机器人局报告 ==")
	var skill_picks := {}
	var skill_wins := {}
	var total_rounds := 0
	var total_retreats := 0
	var total_challenges := 0
	var total_plays := 0
	var n_games := 500
	for seed in range(5001, 5001 + n_games):
		var n := 2 + (seed % 3)
		var gs := Helpers.make(n, seed, true)
		var events := Helpers.run_full(gs)
		total_rounds += gs.round_number
		for e in events:
			match e.type:
				"RETREAT": total_retreats += 1
				"CHALLENGED": total_challenges += 1
				"PLAYED": total_plays += 1
		for p in gs._players:
			var s: int = p.skill
			if not skill_picks.has(s):
				skill_picks[s] = 0
			skill_picks[s] += 1
			if p.alive and gs.winner == p.id:
				if not skill_wins.has(s):
					skill_wins[s] = 0
				skill_wins[s] += 1
	print("  局数 %d" % n_games)
	print("  平均轮数 %.2f，平均退步 %.2f，平均拆招 %.2f，平均出招 %.2f" % [
		float(total_rounds) / n_games, float(total_retreats) / n_games,
		float(total_challenges) / n_games, float(total_plays) / n_games])
	print("  技能被选次数:")
	for s in Rules.ALL_SKILLS:
		var wins: int = skill_wins.get(s, 0)
		var picks: int = skill_picks.get(s, 0)
		var wr := 0.0
		if picks > 0:
			wr = float(wins) / float(picks) * 100.0
		print("    %s: 选中 %d 次，胜 %d 场，胜率 %.1f%%" %
			[Rules.SKILL_NAMES[s], picks, wins, wr])
