extends SceneTree
# 联机端到端：Godot 客户端连生产服 → 建房 → 补3机器人 → 开局 → 打完
var scene
var t := 0.0
var last_send := -9.0

func _initialize() -> void:
	scene = load("res://ui/table.tscn").instantiate()
	root.add_child(scene)
	_run()

func _run() -> void:
	await process_frame
	scene._name_edit.text = "测试侠"
	scene._on_create_room()
	var t0 := 0.0
	while scene.net == null or scene.net.lobby.is_empty():
		await process_frame
		t0 += root.get_process_delta_time()
		if t0 > 25.0:
			print("FAIL: lobby 超时"); quit(1); return
	print("进房 room=%s seat=%d host=%s" % [scene.net.room, scene.net.my_seat, str(scene.net.lobby.get("host"))])
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/lobby.png")
	scene._send_add_bot(); scene._send_add_bot(); scene._send_add_bot()
	t0 = 0.0
	while scene.net.lobby.get("seats", []).size() < 4 and t0 < 10.0:
		await process_frame
		t0 += root.get_process_delta_time()
	print("座位数=", scene.net.lobby.get("seats", []).size(), " can_start=", scene.net.lobby.get("can_start"))
	scene._send_start()
	var over := false
	var shot := false
	t0 = 0.0
	while not over and t0 < 300.0:
		await process_frame
		t0 += root.get_process_delta_time()
		if scene.gs == null:
			continue
		var v: Dictionary = scene.gs.view_for(0)
		if v.is_empty():
			continue
		var ph := int(v.get("phase", -1))
		if ph == Rules.Phase.SKILL_PICK and int(v.you.pending_skill_pick) == -1 and t0 - last_send > 1.0:
			last_send = t0
			scene.net.send_action({"type": "PICK_SKILL", "pid": scene.my_id, "skill": 1})
		if ph == Rules.Phase.PLAY and int(v.current_player) == scene.my_id \
				and v.you.hand.size() > 0 and t0 - last_send > 1.2:
			last_send = t0
			scene.net.send_action({"type": "PLAY", "pid": scene.my_id, "indices": [0]})
		if not shot and int(v.get("round_number", 0)) >= 1 and scene._event_queue.is_empty():
			shot = true
			root.get_viewport().get_texture().get_image().save_png("/tmp/online_game.png")
		if ph == Rules.Phase.GAME_OVER:
			over = true
	print("over=%s winner=%s 轮数=%s" % [str(over), str(scene.gs.winner), str(scene.gs.view_for(0).get("round_number"))])
	quit(0 if over else 1)
