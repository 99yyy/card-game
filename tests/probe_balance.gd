extends SceneTree
#
# 《绝顶》平衡探针 —— 无人局知识创造工具
#
# 用法：
#   godot --headless --path . --script res://tests/probe_balance.gd
#   PROBE_N=20000 godot --headless --path . --script res://tests/probe_balance.gd
#
# 它回答什么：
#   - 各技能胜率（随机分配 = 随机对照试验；被动技能的结论可直接采信）
#   - 座位公平性（本作是"对称但有出手顺序"的游戏，顺序优势必须实测）
#   - 全员同技能的局面畸变（乌龟局假设）
#   - 每个技能单独 1v3 的净效应
#
# 它回答不了什么（重要，别自欺）：
#   - 藏拙：纯视图层技能，内核里不存在，机器人也不读时间 → 它的胜率就是"零效应基线"
#   - 听劲 / 改弦 / 辨虚实：机器人随机时机发动，情报价值被整个扔掉
#   → 所以本探针测的是「不动脑也能拿到的价值」。
#     被动技能（金钟罩/后发制人）的数字是**下限**，真人只会更高不会更低。
#     判断类技能落在基线附近**不能**证明它们弱，只能证明机器人用不了它们。
#
const N4 := 4

class R:
	var rounds := 0
	var retreats := 0
	var falls := 0
	var challenges := 0
	var plays := 0
	var idle_rounds := 0      # 真·空转轮：既无退步也无坠崖
	var heaven := 0
	var bell := 0
	var houfa := 0
	var winner := -1

static func run_one(seed: int, skills: bool, assign: Array) -> R:
	var gs := Helpers.make(N4, seed, skills)
	var guard := 0
	while gs.phase == Rules.Phase.SKILL_PICK and guard < 1000:
		guard += 1
		Helpers.step(gs)
	if skills and assign.size() == N4:
		for i in N4:
			Helpers.force_skill(gs, i, assign[i])
	var r := R.new()
	var moved := false
	var g2 := 0
	while gs.phase != Rules.Phase.GAME_OVER and g2 < 200000:
		g2 += 1
		for e in Helpers.step(gs):
			match e.type:
				"ROUND_START": moved = false
				# 注意：豁口坠崖不发 RETREAT，只发 FALL —— 漏了这一条，
				# 空转轮会被高估成 19%（第一版探针就栽在这里）
				"RETREAT":    r.retreats += 1;   moved = true
				"FALL":       r.falls += 1;      moved = true
				"ROUND_END":
					if not moved:
						r.idle_rounds += 1
				"CHALLENGED":      r.challenges += 1
				"PLAYED":          r.plays += 1
				"HEAVEN_CHECK":    r.heaven += 1
				"GOLDEN_BELL":     r.bell += 1
				"HOUFA_TRIGGERED": r.houfa += 1
		if gs.round_number > 500:
			break
	r.rounds = gs.round_number
	r.winner = gs.winner
	return r

static func agg(label: String, seeds: Array, skills: bool, assign_fn: Callable) -> void:
	var n := float(seeds.size())
	var rounds := 0.0; var retreats := 0.0; var chal := 0.0; var plays := 0.0
	var idle := 0.0; var heaven := 0.0; var bell := 0.0; var houfa := 0.0
	var seat_wins := [0, 0, 0, 0]
	var skill_seats := {}
	var skill_wins := {}
	for s in seeds:
		var assign: Array = assign_fn.call(s)
		var r := run_one(s, skills, assign)
		rounds += r.rounds; retreats += r.retreats; chal += r.challenges
		plays += r.plays; idle += r.idle_rounds
		heaven += r.heaven; bell += r.bell; houfa += r.houfa
		if r.winner >= 0 and r.winner < N4:
			seat_wins[r.winner] += 1
		if skills and assign.size() == N4:
			for i in N4:
				var sk: int = assign[i]
				skill_seats[sk] = skill_seats.get(sk, 0) + 1
				if r.winner == i:
					skill_wins[sk] = skill_wins.get(sk, 0) + 1
	print("--- %s  (n=%d) ---" % [label, int(n)])
	print("  平均轮数 %.2f | 平均退步 %.2f | 平均拆招 %.2f | 平均出招 %.2f" %
		[rounds/n, retreats/n, chal/n, plays/n])
	print("  真·空转轮 %.2f 轮/局 (%.1f%%) | 拆招率 %.1f%% | 天道检验 %.2f/局 | 金钟罩救 %.2f/局 | 后发触发 %.2f/局" %
		[idle/n, idle/maxf(rounds,1.0)*100.0, chal/maxf(plays,1.0)*100.0, heaven/n, bell/n, houfa/n])
	var sl := "  座位胜率: "
	for i in N4:
		sl += "P%d=%.1f%% " % [i, float(seat_wins[i])/n*100.0]
	print(sl)
	if skills and not skill_seats.is_empty():
		print("  各技能胜率（基线 25.0%，括号内为 95%% 置信半宽）:")
		for sk in Rules.ALL_SKILLS:
			var st: int = skill_seats.get(sk, 0)
			if st == 0:
				continue
			var w: int = skill_wins.get(sk, 0)
			var wr := float(w) / float(st) * 100.0
			var se := sqrt(0.25 * 0.75 / float(st)) * 1.96 * 100.0
			var tag := ""
			if wr - se > 25.0:
				tag = "↑ 显著强"
			elif wr + se < 25.0:
				tag = "↓ 显著弱"
			print("    %-6s 出场 %6d  胜 %6d  胜率 %5.1f%% (±%.1f)  %s" %
				[Rules.SKILL_NAMES[sk], st, w, wr, se, tag])

func _initialize() -> void:
	var n_env := OS.get_environment("PROBE_N")
	var N := 4000 if n_env == "" else maxi(200, int(n_env))
	var seeds := []
	for i in N:
		seeds.append(90001 + i)

	agg("A 技能开 · 随机分配（可重复，= 现行 v0.9 规则）", seeds, true, func(s):
		var r := RandomNumberGenerator.new(); r.seed = s * 31 + 7
		return [r.randi_range(0, 5), r.randi_range(0, 5), r.randi_range(0, 5), r.randi_range(0, 5)])

	agg("B 技能关 · 纯净骗子酒馆（对照组）", seeds, false, func(_s): return [])

	agg("C 全员金钟罩（乌龟局假设）", seeds, true, func(_s): return [0, 0, 0, 0])

	agg("C2 全员唯一技能（v0.8 旧规则：四人四技能不重复）", seeds, true, func(s):
		var r := RandomNumberGenerator.new(); r.seed = s * 13 + 3
		var pool := [0, 1, 2, 3, 4, 5]
		# Fisher-Yates，取前 4
		for i in range(pool.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var t = pool[i]; pool[i] = pool[j]; pool[j] = t
		return [pool[0], pool[1], pool[2], pool[3]])

	for target in Rules.ALL_SKILLS:
		agg("D%d  P0=%s  vs  3× 随机其他技能" % [target, Rules.SKILL_NAMES[target]], seeds, true,
			func(s):
				var r := RandomNumberGenerator.new(); r.seed = s * 17 + target
				var others := []
				for k in 3:
					var x := r.randi_range(0, 5)
					while x == target:
						x = r.randi_range(0, 5)
					others.append(x)
				return [target, others[0], others[1], others[2]])
	quit()
