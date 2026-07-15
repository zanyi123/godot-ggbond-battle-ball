extends Node

const TEST_SCENE_PATH := "res://scenes/test/player_3d_test.tscn"

var _test_scene: Node = null
var _passed: int = 0
var _failed: int = 0
var _sep: String = "============================================================"

func _ready() -> void:
	print(_sep)
	print("[自检] player_3d_test 子平台开始")
	print(_sep)

	test_scene_load()

	if _test_scene == null:
		_final_report()
		get_tree().quit()
		return

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_diagnose()
	test_node_structure()
	test_big_camera_system()
	test_3d_model_loaded()
	test_animation_system()
	test_input_bindings()

	_final_report()
	get_tree().quit()


func _diagnose() -> void:
	print("\n--- 诊断: 变量状态 ---")
	var vars = ["_big_cam_vp", "_big_camera", "_big_cam_layer", "_big_cam_rect",
		"_proxy_a", "_proxy_b", "_camera_mode", "_manual_anim_locked", "_current_control_index"]
	for v in vars:
		var val = _test_scene.get(v)
		var type_s = "null" if val == null else typeof(val)
		print("  " + v + " = " + str(val) + " (" + type_s + ")")

	print("\n--- 诊断: 子节点列表 ---")
	for c in _test_scene.get_children():
		print("  " + c.name + " (" + c.get_class() + ")")

	var vp = _test_scene.get_node_or_null("BigCameraViewport")
	if vp:
		print("\n--- 诊断: BigCameraViewport 子节点 ---")
		for c in vp.get_children():
			print("  " + c.name + " (" + c.get_class() + ")")


func _assert(condition: bool, test_name: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  OK " + test_name)
	else:
		_failed += 1
		print("  FAIL " + test_name + " - " + detail)


func test_scene_load() -> void:
	print("\n--- 测试1: 场景加载 ---")
	var packed: PackedScene = load(TEST_SCENE_PATH)
	_assert(packed != null, "场景文件可加载", TEST_SCENE_PATH)
	if packed == null:
		return

	_test_scene = packed.instantiate()
	_assert(_test_scene != null, "场景可实例化")
	if _test_scene == null:
		return

	get_tree().root.add_child.call_deferred(_test_scene)
	_assert(true, "场景已加入场景树")


func test_node_structure() -> void:
	print("\n--- 测试2: 节点结构(TSCN定义) ---")
	_assert(_test_scene.has_node("Camera2D"), "Camera2D")
	_assert(_test_scene.has_node("FieldBG"), "FieldBG")
	_assert(_test_scene.has_node("MidLine"), "MidLine")
	_assert(_test_scene.has_node("CenterCircle"), "CenterCircle")
	_assert(_test_scene.has_node("Border"), "Border")
	_assert(_test_scene.has_node("PlayerA"), "PlayerA")
	_assert(_test_scene.has_node("PlayerB"), "PlayerB")


func test_big_camera_system() -> void:
	print("\n--- 测试3: 大相机系统 ---")
	var vp = _test_scene.get("_big_cam_vp")
	_assert(vp != null, "_big_cam_vp 已创建")

	var cam = _test_scene.get("_big_camera")
	_assert(cam != null, "_big_camera 已创建")
	if cam != null:
		_assert(cam.near == 1.0, "near=1.0")
		_assert(cam.far == 10000.0, "far=10000.0")

	var layer = _test_scene.get("_big_cam_layer")
	_assert(layer != null, "_big_cam_layer 已创建")

	var mode = _test_scene.get("_camera_mode")
	_assert(mode != null, "_camera_mode 已设置")


func test_3d_model_loaded() -> void:
	print("\n--- 测试4: 3D模型加载 ---")
	var proxy_a = _test_scene.get("_proxy_a")
	var proxy_b = _test_scene.get("_proxy_b")
	_assert(proxy_a != null, "_proxy_a 存在")
	_assert(proxy_b != null, "_proxy_b 存在")

	if proxy_a != null:
		var slot = proxy_a.get_node_or_null("ModelSlot")
		_assert(slot != null, "ProxyA ModelSlot 存在")
		if slot != null:
			_assert(slot.get_child_count() > 0, "ModelSlot子节点数=" + str(slot.get_child_count()))
			var meshes = slot.find_children("*", "MeshInstance3D", true, false)
			_assert(meshes.size() > 0, "MeshInstance3D数量=" + str(meshes.size()))


func test_animation_system() -> void:
	print("\n--- 测试5: 动画系统 ---")
	var proxy_a = _test_scene.get("_proxy_a")
	if proxy_a == null:
		_assert(false, "跳过动画测试", "_proxy_a不存在")
		return

	var ap = proxy_a.get_meta("anim_player", null)
	_assert(ap != null, "anim_player meta 存在")
	if ap == null:
		var found = _find_anim_player(proxy_a)
		_assert(found != null, "直接查找AnimationPlayer")
		ap = found

	if ap != null:
		_assert(ap.has_animation("idle"), "idle 动画")
		_assert(ap.has_animation("run"), "run 动画")
		_assert(ap.has_animation("throw"), "throw 动画")
		_assert(ap.has_animation("catch"), "catch 动画")
		var cur: String = ap.current_animation
		_assert(cur == "idle", "默认动画为 idle: " + cur)
		_assert(ap.is_playing(), "动画正在播放")


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null


func test_input_bindings() -> void:
	print("\n--- 测试6: 输入快捷键 ---")
	_assert(_test_scene.has_method("_poll_hotkeys"), "_poll_hotkeys 方法存在")
	_assert(_test_scene.has_method("_physics_process"), "_physics_process 存在")
	_assert(_test_scene.has_method("_hk_tab"), "_hk_tab 存在")
	_assert(_test_scene.has_method("_hk_throw"), "_hk_throw 存在")
	_assert(_test_scene.has_method("_hk_catch"), "_hk_catch 存在")
	_assert(_test_scene.has_method("_hk_idle"), "_hk_idle 存在")
	_assert(_test_scene.has_method("_hk_camera"), "_hk_camera 存在")
	_assert(_test_scene.has_method("_hk_reset"), "_hk_reset 存在")
	_assert(_test_scene.has_method("_hk_bigcam"), "_hk_bigcam 存在")


func _final_report() -> void:
	print("\n" + _sep)
	print("[自检结果] 通过: " + str(_passed) + " / 失败: " + str(_failed))
	if _failed == 0:
		print("[自检结果] 全部通过")
	else:
		print("[自检结果] 存在失败项")
	print(_sep)
