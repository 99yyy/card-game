class_name TestView
extends RefCounted

# §16.4 / 铁律 3：view_for() 机密断言。
# 把 view_for() 结果 JSON.stringify 成字符串，断言不含机密键，可查到任何嵌套层级。

static func run_all() -> void:
	print("== test_view ==")
	var before: int = Helpers.failures().size()
	_test_confidential_keys()
	_test_others_no_private()
	_test_mine_has_private()
	_test_last_played_count_only()
	print("  [%s] test_view" % ["PASS" if Helpers.failures().size() == before else "FAIL"])

# 1. 任何层级不得出现五项机密键 + _seed/_rng
static func _test_confidential_keys() -> void:
	# 用真实开局（有手牌、有 hollow、有 last_played_cards 空）
	var gs := Helpers.make(4, 101, true)
	for pid in 4:
		var s := JSON.stringify(gs.view_for(pid))
		Helpers.assert_true(not s.contains("hollow_index"), "view(%d) 泄 hollow_index" % pid)
		Helpers.assert_true(not s.contains("last_played_cards"), "view(%d) 泄 last_played_cards" % pid)
		Helpers.assert_true(not s.contains("_seed"), "view(%d) 泄 _seed" % pid)
		Helpers.assert_true(not s.contains("_rng"), "view(%d) 泄 _rng" % pid)

# 2. 他人的 hand / probe_result / listen_result 不得出现
static func _test_others_no_private() -> void:
	var gs := Helpers.make(4, 102, true)
	# 给 P1/P2 塞入 probe/listen 结果，确保若泄露会被抓到
	gs._players[1].probe_result = {"3": true}
	gs._players[1].listen_result = {"7": 0}
	gs._players[2].probe_result = {"5": false}
	for pid in 4:
		var v: Dictionary = gs.view_for(pid)
		for other in 4:
			if other == pid:
				continue
			var op: Dictionary = v.players[other]
			Helpers.assert_true(not op.has("hand"), "view(%d).players[%d] 泄 hand" % [pid, other])
			Helpers.assert_true(not op.has("probe_result"), "view(%d).players[%d] 泄 probe_result" % [pid, other])
			Helpers.assert_true(not op.has("listen_result"), "view(%d).players[%d] 泄 listen_result" % [pid, other])

# 3. 本人视图应含自己的 hand / probe_result / listen_result
static func _test_mine_has_private() -> void:
	var gs := Helpers.make(4, 103, true)
	gs._players[1].probe_result = {"3": true}
	gs._players[1].listen_result = {"7": 0}
	var v: Dictionary = gs.view_for(1)
	Helpers.assert_true(v.you.has("hand"), "本人视图应含 hand")
	Helpers.assert_true(v.you.has("probe_result"), "本人视图应含 probe_result")
	Helpers.assert_true(v.you.has("listen_result"), "本人视图应含 listen_result")
	Helpers.assert_eq(v.you.probe_result["3"], true, "本人 probe_result 应可读")

# 4. last_played_cards 只以 count 形式出现，不含牌面
static func _test_last_played_count_only() -> void:
	var gs := Helpers.make(4, 104, true)
	# 构造一个已出招的局面
	gs.phase = Rules.Phase.PLAY
	gs.round_number = 5
	gs.current_suit = Rules.Suit.DAO
	gs.current_player = 1
	gs.last_player_who_played = 0
	gs.last_played_cards = [Rules.Suit.DAO, Rules.Suit.HUAJIN]
	var v: Dictionary = gs.view_for(1)
	Helpers.assert_eq(v.last_played_count, 2, "last_played_count 应为 2")
	Helpers.assert_true(not v.has("last_played_cards"), "顶层不应有 last_played_cards")
	var s := JSON.stringify(v)
	Helpers.assert_true(not s.contains("last_played_cards"), "JSON 不应含 last_played_cards")
