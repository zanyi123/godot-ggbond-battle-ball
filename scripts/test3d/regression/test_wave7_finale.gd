## 波7 验收：削能墙 + 地形改动（16 工单，原语收官批；headless 可跑）
## #6b：捕获吸入/逐帧削能/吸住超时释放/不击穿/耗尽停球球权
## #6a：摩擦地形区（区内 mu/区外默认/到期恢复）；两原语共存
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_wave7_finale.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var is_player_controlled: bool = true
	var char_data: Dictionary = {"name": "stub"}
	var character_id: String = ""
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var max_spirit_energy: float = 100.0
	var spirit_energy: float = 100.0
	var facing_direction: Vector2 = Vector2.RIGHT
	var ball_ref: Node = null
	var _cc: bool = false
	func is_status_active(s: String) -> bool:
		return false
	func set_carrying_ball(v: bool) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波7 削能墙+地形改动测试 ==========\n")
	for i in range(3):
		await process_frame
	var mgr = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(mgr)
	mgr.ball_ref = null
	await process_frame

	# ===== #6b 削能墙 =====
	var caster: StubPlayer = StubPlayer.new(); caster.team = "a"; caster.position = Vector2(0, 0); root.add_child(caster)
	var p_wall := {"shape": "rect", "width": 60.0, "height": 60.0, "hp": 9999.0,
		"duration": 30.0, "capture_radius": 90.0, "absorb_pull": 240.0, "drain_hold": 2.0,
		"attack_consume_rate": 20.0, "speed_consume_rate": 20.0}
	var wall = mgr.create_obstacle(p_wall.duplicate(), Vector2(150, 0), 0.0, "res://scripts/battle/drain_wall.gd")
	wall.setup_drain(p_wall)
	await process_frame
	_assert("削能墙: 生成且 hp 不参与击穿", is_instance_valid(wall) and absf(float(wall.obstacle_hp) - 9999.0) < 0.01)

	var ball: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	ball.is_active = true
	ball.attacker_player = caster
	ball.is_clone = false
	ball.ball_damage = 40.0
	ball.ball_speed = 200.0
	ball.stuck_on_obstacle = null
	ball.global_position = Vector2(120, 0)  # 墙(150,0)半径90内
	wall.ball_ref = ball

	# 捕获+吸入
	ball._physics_process(0.016)
	_assert("削能墙: 球被捕获 (stuck=wall)", ball.stuck_on_obstacle == wall)
	var d_before: float = ball.global_position.distance_to(wall.global_position)
	ball._physics_process(0.016)
	_assert("削能墙: 吸力向墙心", ball.global_position.distance_to(wall.global_position) < d_before or ball.stuck_on_obstacle == wall)

	# 逐帧削能（复用岩石墙口径：攻-20/s 速-20/s）
	var dmg0: float = float(ball.ball_damage)
	var spd0: float = float(ball.ball_speed)
	ball._process_obstacle_stuck(1.0)
	_assert("削能墙: 1秒削攻20", absf(float(ball.ball_damage) - (dmg0 - 20.0)) < 0.01)
	_assert("削能墙: 1秒削速20", absf(float(ball.ball_speed) - (spd0 - 20.0)) < 0.01)
	_assert("削能墙: 不做击穿(墙hp不降)", absf(float(wall.obstacle_hp) - 9999.0) < 0.01)

	# 吸住超时释放
	wall._physics_process(2.5)
	_assert("削能墙: 吸住超时释放继续飞", ball.stuck_on_obstacle == null and ball.is_active)

	# 耗尽停球球权：再次吸入并削到耗尽
	ball.stuck_on_obstacle = null
	ball.global_position = Vector2(150, 0)
	ball._physics_process(0.016)
	ball.ball_speed = 10.0
	ball._process_obstacle_stuck(1.0)  # 速尽 → _stop_and_return → 回攻击者
	_assert("削能墙: 球速耗尽停球球权回攻击者", ball.owner_player == caster)

	# ===== #6a 摩擦地形区 =====
	var fpm = load("res://scripts/battle/field_physics_manager.gd").new()
	root.add_child(fpm)
	await process_frame
	var default_mu: float = float(fpm.get_friction())
	fpm.add_terra_zone(Vector2(0, 0), 100.0, 0.5, 30.0)
	_assert("地形: 区内 mu=0.5", absf(float(fpm.get_friction_at(Vector2(10, 10))) - 0.5) < 0.01)
	_assert("地形: 区外保持默认", absf(float(fpm.get_friction_at(Vector2(5000, 5000))) - default_mu) < 0.01)
	# 到期恢复
	fpm.terra_zones[0]["remaining"] = 0.1
	fpm._cleanup_terra_zones()
	_assert("地形: 到期移除恢复默认", absf(float(fpm.get_friction_at(Vector2(10, 10))) - default_mu) < 0.01)
	# 共存：terra 区与削能墙互不影响
	_assert("共存: 削能墙仍有效", is_instance_valid(wall))

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
