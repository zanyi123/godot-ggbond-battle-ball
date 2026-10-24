extends Node
## 36号：全局热键（主人令"F7 不行就挂监听"）——F7=技能测试专用平台入口，任何场景可用。
## 37号：F9=操控标签演示平台入口；FullAIPlatform 内不劫持（F9 归观测面板收/展，30号裁定）。
## autoload 的 _input 优先于场景内节点（树根前），且不受全屏 Control 键盘焦点消费影响。

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F7:
		var cs := get_tree().current_scene
		if cs != null and cs.name == "SkillTestPlatform":
			return  # 已在平台内，不重复切
		get_viewport().set_input_as_handled()
		print("[GlobalHotkeys] F7 → 技能测试专用平台")
		get_tree().change_scene_to_file("res://scenes/test3d/skill_test_platform.tscn")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		var cs9 := get_tree().current_scene
		if cs9 != null and (cs9.name == "SkillControlDemoPlatform" or cs9.name == "FullAIPlatform"):
			return  # 已在37号平台内不重复切；full_ai_platform 内 F9 归观测面板（防劫持）
		get_viewport().set_input_as_handled()
		print("[GlobalHotkeys] F9 → 操控标签演示平台")
		get_tree().change_scene_to_file("res://scenes/test3d/skill_control_demo_platform.tscn")
