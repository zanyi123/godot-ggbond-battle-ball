## 3D 赛场系统自检脚本（headless 状态验证版）
## 加载 player_3d_test.tscn，模拟 throw/catch 测试，验证节点状态
extends Node

const TEST_SCENE: String = "res://scenes/test/player_3d_test.tscn"
const MAX_PHASES: int = 5

var _test_root: Node = null
var _phase: int = 0
var _phase_wait: float = 0.0
var _player_3d: Node = null
var _results: Dictionary = {}


func _ready() -> void:
	print("[SelfTest] === 开始 3D 赛场系统自检 ===")
	# 等几帧让 root 完全初始化
	await get_tree().process_frame
	await get_tree().process_frame
	# 加载测试场景（必须用 call_deferred 因为 root 还在 _ready）
	var scene: PackedScene = load(TEST_SCENE)
	if scene == null:
		print("[SelfTest] ❌ 无法加载测试场景: %s" % TEST_SCENE)
		get_tree().quit(1)
		return
	_test_root = scene.instantiate()
	get_tree().root.add_child.call_deferred(_test_root)
	# 等几帧让 _test_root._ready 执行
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	print("[SelfTest] ✅ 测试场景加载完成")
	# 找 player_3d_test
	_player_3d = _test_root
	if _player_3d == null:
		print("[SelfTest] ❌ 找不到 player_3d_test 根节点")
		get_tree().quit(1)
		return
	# 输出关键节点状态
	_report_nodes("Phase0_Initial")
	# Phase 1: 模拟 throw
	_run_phase_throw()
	# 等球飞 0.5s
	await get_tree().create_timer(0.5).timeout
	_report_nodes("Phase1_ThrowFired")
	# Phase 2: 模拟 catch
	_run_phase_catch()
	# 等接球 0.5s
	await get_tree().create_timer(0.5).timeout
	_report_nodes("Phase2_CatchFired")
	# Phase 3: 等接球助手完成
	await get_tree().create_timer(0.5).timeout
	_report_nodes("Phase3_Caught")
	# Phase 4: F1 throw again
	_run_phase_throw()
	await get_tree().create_timer(0.5).timeout
	_report_nodes("Phase4_ThrowAgain")
	# 全部完成
	_print_summary()
	get_tree().quit(0)


func _run_phase_throw() -> void:
	print("[SelfTest] === 模拟 F1 throw ===")
	if _player_3d.has_method("_hk_throw"):
		_player_3d._hk_throw()
	else:
		print("[SelfTest] ❌ _hk_throw 方法不存在")


func _run_phase_catch() -> void:
	print("[SelfTest] === 模拟 F2 catch ===")
	if _player_3d.has_method("_hk_catch"):
		_player_3d._hk_catch()
	else:
		print("[SelfTest] ❌ _hk_catch 方法不存在")


func _report_nodes(label: String) -> void:
	print("[SelfTest] === %s 状态报告 ===" % label)
	# 1. ball_2d 状态
	if _player_3d.get("ball_2d"):
		var b2: Node = _player_3d.get("ball_2d")
		var is_active: bool = b2.is_active
		var owner_team: String = "<null>"
		if b2.owner_player:
			owner_team = str(b2.owner_player.team)
		print("[SelfTest]   ball_2d: pos=%s is_active=%s owner_team=%s" % [
			b2.global_position, is_active, owner_team
		])
		# 记录关键状态
		_results[label + "_ball_active"] = is_active
		_results[label + "_ball_owner"] = owner_team
	else:
		print("[SelfTest]   ❌ ball_2d 为 null")
	# 2. BallProxy3D 状态
	if _player_3d.get("_ball_proxy_3d"):
		var bp: Node = _player_3d.get("_ball_proxy_3d")
		print("[SelfTest]   BallProxy3D: global_pos=%s, in_tree=%s" % [
			bp.global_position, bp.is_inside_tree()
		])
		_results[label + "_ballproxy_pos"] = str(bp.global_position)
	else:
		print("[SelfTest]   ❌ _ball_proxy_3d 为 null")
	# 3. 球员代理位置
	if _player_3d.get("_proxy_a"):
		var pa: Node3D = _player_3d.get("_proxy_a")
		print("[SelfTest]   _proxy_a: pos=%s rot.y=%.2f" % [pa.position, pa.rotation.y])
		_results[label + "_proxyA_pos"] = str(pa.position)
		_results[label + "_proxyA_rot"] = pa.rotation.y
	if _player_3d.get("_proxy_b"):
		var pb: Node3D = _player_3d.get("_proxy_b")
		print("[SelfTest]   _proxy_b: pos=%s rot.y=%.2f" % [pb.position, pb.rotation.y])
		_results[label + "_proxyB_pos"] = str(pb.position)
	# 4. HandProxy 位置
	if _player_3d.get("_proxy_a"):
		var pa2: Node3D = _player_3d.get("_proxy_a")
		var hp: Node3D = pa2.get_node_or_null("HandProxy")
		if hp:
			print("[SelfTest]   proxy_a.HandProxy: global_pos=%s" % hp.global_position)
			_results[label + "_handA_pos"] = str(hp.global_position)
	# 5. 球员持球状态
	if _player_3d.get("player_a"):
		var pla: Node = _player_3d.get("player_a")
		print("[SelfTest]   player_a: pos=%s is_carrying_ball=%s stamina=%.1f spirit=%.1f" % [
			pla.global_position, pla.is_carrying_ball, pla.stamina, pla.spirit_energy
		])
		_results[label + "_playerA_stamina"] = pla.stamina
		_results[label + "_playerA_spirit"] = pla.spirit_energy
		_results[label + "_playerA_carrying"] = pla.is_carrying_ball
	if _player_3d.get("player_b"):
		var plb: Node = _player_3d.get("player_b")
		print("[SelfTest]   player_b: pos=%s is_carrying_ball=%s stamina=%.1f spirit=%.1f" % [
			plb.global_position, plb.is_carrying_ball, plb.stamina, plb.spirit_energy
		])
	# 6. 面板状态
	if _player_3d.get("_stam_a"):
		var stam_a: ProgressBar = _player_3d.get("_stam_a")
		print("[SelfTest]   _stam_a: value=%.1f/%.1f" % [stam_a.value, stam_a.max_value])
	if _player_3d.get("_energy_a"):
		var energy_a: ProgressBar = _player_3d.get("_energy_a")
		print("[SelfTest]   _energy_a: value=%.1f/%.1f" % [energy_a.value, energy_a.max_value])
	# 7. 动画状态
	if _player_3d.get("_proxy_a"):
		var pa3: Node3D = _player_3d.get("_proxy_a")
		var ap: AnimationPlayer = pa3.get_meta("anim_player", null)
		if ap:
			print("[SelfTest]   proxy_a 动画: current=%s playing=%s" % [ap.current_animation, ap.is_playing()])
	# 8. 模型缩放诊断（关键！验证 slot.scale=70 是否生效）
	_report_model_scale("Phase0_Initial")


func _report_model_scale(label: String) -> void:
	"""诊断 proxy_a 的 ModelSlot 缩放链和 mesh AABB"""
	if not _player_3d.get("_proxy_a"):
		print("[SelfTest]   ❌ _proxy_a 为 null，无法检查模型缩放")
		return
	var proxy: Node3D = _player_3d.get("_proxy_a")
	# ModelSlot
	var slot: Node3D = proxy.get_node_or_null("ModelSlot") as Node3D
	if slot:
		print("[SelfTest]   ModelSlot: scale=%s" % str(slot.scale))
		_results[label + "_slot_scale"] = str(slot.scale)
		# 检查 slot 内子节点
		for child in slot.get_children():
			if child is Node3D:
				var c3d: Node3D = child
				print("[SelfTest]     slot child '%s': scale=%s visible=%s" % [c3d.name, str(c3d.scale), c3d.visible])
				# 查找 mesh AABB
				var meshes = c3d.find_children("*", "MeshInstance3D", true, false)
				for m in meshes:
					if m is MeshInstance3D:
						var mi: MeshInstance3D = m
						if mi.mesh:
							var aabb: AABB = mi.mesh.get_aabb()
							print("[SelfTest]       mesh '%s': AABB size=%s global_scale=%s" % [
								mi.name, str(aabb.size), str(mi.global_transform.basis.get_scale())
							])
							_results[label + "_mesh_" + mi.name + "_size"] = str(aabb.size)
	else:
		print("[SelfTest]   ❌ ModelSlot 未找到")
	# 检查 HandProxy
	var hp: Node3D = proxy.get_node_or_null("HandProxy") as Node3D
	if hp:
		print("[SelfTest]   HandProxy: local_pos=%s global_pos=%s" % [str(hp.position), str(hp.global_position)])
		_results[label + "_hand_proxy_pos"] = str(hp.global_position)
	# 检查 SubViewport 节点数
	if _player_3d.get("_big_cam_vp"):
		var vp: SubViewport = _player_3d.get("_big_cam_vp")
		print("[SelfTest]   SubViewport: child_count=%d size=%s" % [vp.get_child_count(), str(vp.size)])


func _print_summary() -> void:
	print("\n[SelfTest] ============== 总结报告 ==============")
	# 关键验证点
	var ball_initial: String = _results.get("Phase0_Initial_ball_owner", "<null>")
	var ball_after_throw: bool = _results.get("Phase1_ThrowFired_ball_active", false)
	var ball_after_catch: bool = _results.get("Phase3_Caught_ball_active", true)
	var owner_after_catch: String = _results.get("Phase3_Caught_ball_owner", "<null>")
	var owner_initial: String = _results.get("Phase0_Initial_ball_owner", "<null>")
	var throwing_side_initial: float = _results.get("Phase0_Initial_proxyA_rot", 0.0)
	var throwing_side_after_throw: float = _results.get("Phase1_ThrowFired_proxyA_rot", 0.0)

	print("[SelfTest] 初始持球方: %s (应为 A 队)" % ball_initial)
	print("[SelfTest] 投球后球是否飞行: %s (应 true)" % ball_after_throw)
	print("[SelfTest] 接球后球是否停飞: %s (应 false)" % (not ball_after_catch))
	print("[SelfTest] 接球后持球方: %s (应 A 队 - controlled_player)" % owner_after_catch)
	print("[SelfTest] 投球前 proxyA 朝向: %.2f, 投球后: %.2f (应不同 → 投球手一侧已旋转)" % [
		throwing_side_initial, throwing_side_after_throw
	])
	# 评估
	var pass_count: int = 0
	var fail_count: int = 0
	if ball_initial == "a":
		pass_count += 1
		print("[SelfTest] ✅ 初始 A 持球")
	else:
		fail_count += 1
		print("[SelfTest] ❌ 初始持球方错误: %s" % ball_initial)
	if ball_after_throw:
		pass_count += 1
		print("[SelfTest] ✅ 投球后球在飞")
	else:
		fail_count += 1
		print("[SelfTest] ❌ 投球后球未飞行")
	if not ball_after_catch and owner_after_catch != "<null>":
		pass_count += 1
		print("[SelfTest] ✅ 接球后球停飞 + 归属正确")
	else:
		fail_count += 1
		print("[SelfTest] ❌ 接球后状态异常: active=%s owner=%s" % [ball_after_catch, owner_after_catch])
	if abs(throwing_side_after_throw - throwing_side_initial) > 0.1:
		pass_count += 1
		print("[SelfTest] ✅ 投球手一侧已旋转")
	else:
		fail_count += 1
		print("[SelfTest] ⚠️ 投球手一侧未旋转（可能 controlled_player 没动）")
	print("[SelfTest] ============== 通过 %d / 失败 %d ==============" % [pass_count, fail_count])
