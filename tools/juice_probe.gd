extends SceneTree
var scene
var t := 0.0
var fired := {}
func _initialize() -> void:
	scene = load("res://ui/table.tscn").instantiate()
	root.add_child(scene)
	_run()
func _run() -> void:
	await process_frame
	scene._on_intro_start()
	await process_frame
	scene._apply(Action.pick_skill(0, Rules.Skill.TINGJIN))
	while t < 22.0:
		await process_frame
		t += root.get_process_delta_time()
		if t >= 6.0 and not fired.has("emote"):
			fired["emote"] = true
			scene._apply(Action.emote(0, 1))    # 发个抱拳，验证表情动画链路
		if t >= 9.0 and not fired.has("shot"):
			fired["shot"] = true
			root.get_viewport().get_texture().get_image().save_png("/tmp/emote_shot.png")
	print("probe done, phase=", scene.gs.phase)
	quit(0)
