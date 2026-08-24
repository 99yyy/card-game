extends SceneTree
# 动画打磨冒烟：单机开局，跑 25 秒确认无报错、截两张图
var scene
var t := 0.0
var shots := {4.0: "/tmp/juice1.png", 12.0: "/tmp/juice2.png"}
var done := {}
func _initialize() -> void:
	scene = load("res://ui/table.tscn").instantiate()
	root.add_child(scene)
	_run()
func _run() -> void:
	await process_frame
	scene._on_intro_start()
	await process_frame
	# 替真人选技能加速进对局
	scene._apply(Action.pick_skill(0, Rules.Skill.TINGJIN))
	while t < 25.0:
		await process_frame
		t += root.get_process_delta_time()
		for k in shots:
			if t >= k and not done.has(k):
				done[k] = true
				root.get_viewport().get_texture().get_image().save_png(shots[k])
	print("probe done, phase=", scene.gs.phase)
	quit(0)
