extends SceneTree
var scene: Node
var t := 0.0
var taken := 0
var started := false
func _initialize() -> void:
	scene = load("res://ui/table.tscn").instantiate()
	root.add_child(scene)
	_loop()
func _loop() -> void:
	while t < 16.0:
		await process_frame
		t += root.get_process_delta_time()
		if taken == 0 and t >= 1.5:
			await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/intro.png")
			print("intro shot; gs is null =", scene.gs == null)
			taken += 1
		if not started and t >= 2.5:
			started = true
			scene._on_intro_start()
			print("clicked start; gs is null =", scene.gs == null)
		if taken == 1 and t >= 5.0:
			await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/after_start.png")
			taken += 1
	print("final phase =", scene.gs.phase)
	quit(0)
