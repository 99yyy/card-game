extends SceneTree

# 无头测试入口（§2.2）。全绿 quit(0)，有失败先打印全部再 quit(1)。

func _initialize() -> void:
	Helpers.reset()
	TestRules.run_all()
	TestRules.run_report()
	TestEdges.run_all()
	TestSkills.run_all()
	TestView.run_all()
	var fails: Array = Helpers.failures()
	if fails.is_empty():
		print("\n=== ALL TESTS PASSED ===")
		quit(0)
	else:
		print("\n=== %d FAILURE(S) ===" % fails.size())
		for f in fails:
			print(f)
		quit(1)
