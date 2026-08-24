extends SceneTree
var scene
var t := 0.0
var mode := 0
var shot := false
func _initialize() -> void:
	mode = int(OS.get_environment("PROBE_MODE"))
	scene = load("res://ui/table.tscn").instantiate()
	root.add_child(scene)
	_run()
func _run() -> void:
	await process_frame
	scene._on_mode_pick(mode)
	scene._on_intro_start()
	var t0 := 0.0
	var last := -9.0
	while t0 < 40.0:
		await process_frame
		t0 += root.get_process_delta_time()
		if scene.gs == null:
			continue
		var ph: int = scene.gs.phase
		var v: Dictionary = scene.gs.view_for(0)
		# 替真人：报门户
		if ph == Rules.Phase.SKILL_PICK and t0 - last > 0.8:
			last = t0
			if mode >= 2:
				if not bool(v.you.get("ready", true)):
					scene._apply({"type": "PICK_CHAR", "pid": 0, "char_id": 3})
					scene._apply({"type": "READY", "pid": 0})
			else:
				if int(v.you.pending_skill_pick) == -1:
					scene._apply(Action.pick_skill(0, 1))
		# 替真人：轮到就用内核机器人代打
		if ph == Rules.Phase.PLAY and int(v.current_player) == 0 and t0 - last > 1.0 \
				and scene._event_queue.is_empty():
			last = t0
			match mode:
				2: scene._apply(GameDice.bot_decide(v, scene._driver_rng))
				3: scene._apply(GamePoison.bot_decide(v, scene._driver_rng))
				_:
					if v.you.hand.size() > 0:
						scene._apply(Action.play(0, [0]))
		if not shot and ph == Rules.Phase.PLAY and t0 > 8.0 and scene._event_queue.is_empty():
			shot = true
			root.get_viewport().get_texture().get_image().save_png("/tmp/mode_%d.png" % mode)
		if ph == Rules.Phase.GAME_OVER:
			break
	print("mode=%d done phase=%d" % [mode, scene.gs.phase])
	quit(0)
