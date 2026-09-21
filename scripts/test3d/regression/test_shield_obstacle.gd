## V1-2 验收：体外实体盾 player_shield_obstacle（05 文档 §四断言清单，headless 可跑）
## 覆盖：follow跟随/static固定/uses次数制/hp数值制/超时expired/信号契约/manager查询/索敌兼容/释放者淘汰联动
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_shield_obstacle.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "a"
	var is_defeated: bool = false
	var facing_direction: Vector2 = Vector2.RIGHT
	func is_status_active(_s: String) -> bool:
		return false


func _initialize() -> void:
	_run()


func _mk_shield(params: Dictionary, caster: StubPlayer) -> Node:
	var shield = load("res://scripts/battle/player_shield.gd").new()
	root.add_child(shield)
	shield.setup(params)
	shield.setup_shield(params, caster)
	return shield


func _run() -> void:
	print("\n========== 体外实体盾测试 ==========\n")
	var base := {"shape": "rect", "width": 70.0, "height": 24.0, "hp": 100.0,
		"attack_consume_rate": 20.0, "speed_consume_rate": 20.0, "duration": 10.0,
		"element_color": Color(0.5, 0.8, 1.0)}

	# ===== ① follow 跟随：位置=释放者身前，随移动/转向 =====
	var caster := StubPlayer.new(); caster.position = Vector2(0, 0)
	root.add_child(caster)
	var s1 := _mk_shield(base.duplicate(), caster)
	await process_frame
	_assert("follow: 初始在身前 offset=52", s1.global_position.distance_to(Vector2(52, 0)) < 2.0)
	caster.position = Vector2(100, 0)
	caster.facing_direction = Vector2(0, 1)
	await process_frame
	await process_frame
	_assert("follow: 移动+转向后仍跟随 (100,52)", s1.global_position.distance_to(Vector2(100, 52)) < 3.0)
	s1.queue_free()

	# ===== ② static 固定：不随释放者移动/转向 =====
	var caster2 := StubPlayer.new(); caster2.position = Vector2(0, 0)
	root.add_child(caster2)
	var p2 := base.duplicate(); p2["follow_mode"] = "static"
	var s2 := _mk_shield(p2, caster2)
	await process_frame
	var fixed_pos: Vector2 = s2.global_position
	caster2.position = Vector2(300, 300)
	caster2.facing_direction = Vector2(-1, 0)
	await process_frame
	await process_frame
	_assert("static: 释放者移动后盾位置不变", s2.global_position.distance_to(fixed_pos) < 0.5)
	s2.queue_free()

	# ===== ③④ uses 次数制：撞 N 次盾碎，信号契约 hit→broken =====
	var caster3 := StubPlayer.new(); root.add_child(caster3)
	var p3 := base.duplicate(); p3["durability_mode"] = "uses"; p3["uses"] = 2
	var s3 := _mk_shield(p3, caster3)
	var ev3: Array = []
	s3.shield_state_changed.connect(func(hp, reason): ev3.append([hp, reason]))
	_assert("uses: 初始 uses_left=2", int(s3.uses_left) == 2)
	s3.on_ball_hit()
	_assert("uses: 撞1次 → 信号(1,hit)", ev3.size() == 1 and absf(float(ev3[0][0]) - 1.0) < 0.01 and ev3[0][1] == "hit")
	s3.on_ball_hit()
	_assert("uses: 撞2次 → 报(0,hit)后补(0,broken)", ev3.size() == 3 and ev3[1][0] == 0.0 and ev3[1][1] == "hit" and ev3[2][0] == 0.0 and ev3[2][1] == "broken")
	_assert("uses: 盾碎后销毁", s3._broken_signaled and s3.is_queued_for_deletion())
	await process_frame

	# ===== ⑤⑦ hp 数值制：consume_frame 扣耐久，耗尽 broken =====
	var p5 := base.duplicate(); p5["durability_mode"] = "hp"; p5["hp"] = 30.0
	p5["attack_consume_rate"] = 10.0
	var s5 := _mk_shield(p5, caster3)
	var ev5: Array = []
	s5.shield_state_changed.connect(func(hp, reason): ev5.append([hp, reason]))
	_assert("hp: get_shield_hp 初始=30", absf(s5.get_shield_hp() - 30.0) < 0.01)
	s5.consume_frame(1.0)  # 10/s × 1s = 扣10
	_assert("hp: 1秒消耗后剩余=20", absf(s5.get_shield_hp() - 20.0) < 0.01 and ev5.size() >= 1 and ev5[0][1] == "hit")
	s5.consume_frame(1.0)
	s5.consume_frame(1.0)  # 累计扣30 → 归零
	var has_broken := false
	for e in ev5:
		if e[1] == "broken":
			has_broken = true
	_assert("hp: 耗尽 → broken 信号", has_broken and s5.get_shield_hp() <= 0.0)
	await process_frame

	# ===== ⑥ 超时 expired =====
	var s6 := _mk_shield(base.duplicate(), caster3)
	var ev6: Array = []
	s6.shield_state_changed.connect(func(hp, reason): ev6.append([hp, reason]))
	s6._on_duration_expired()
	_assert("超时: reason=expired", ev6.size() == 1 and ev6[0][1] == "expired")
	await process_frame

	# ===== ⑨ manager 查询接口 =====
	var mgr = load("res://scripts/battle/obstacle_manager.gd").new()
	root.add_child(mgr)
	await process_frame
	var caster4 := StubPlayer.new(); root.add_child(caster4)
	var shield = mgr.create_player_shield(base.duplicate(), caster4)
	await process_frame
	_assert("manager: get_player_shield 按施法者查到盾", mgr.get_player_shield(caster4.get_instance_id()) == shield)
	_assert("manager: 他人查询返回空", mgr.get_player_shield(caster3.get_instance_id()) == null)
	# 注意：盾是 mgr 的子节点，mgr 须等索敌用例用完盾后再释放

	# ===== ⑩ 索敌兼容：盾不是球员（非 CharacterBody2D，名册/AOE 筛选排除）=====
	var ball = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	var ally := StubPlayer.new(); ally.team = "a"; ally.position = Vector2(0, 0)
	var enemy := StubPlayer.new(); enemy.team = "b"; enemy.position = Vector2(30, 0)
	root.add_child(ally); root.add_child(enemy)
	await process_frame
	var targets: Array = ball._collect_aoe_targets(ally, "b", 100.0, [shield, enemy])
	_assert("索敌兼容: 盾不进 AOE 目标集合", targets.size() == 1 and targets[0] == enemy)
	ball.queue_free()
	shield.queue_free()
	mgr.queue_free()

	# ===== ⑪ 生命周期：释放者被淘汰 → 盾随之清理 =====
	var caster5 := StubPlayer.new(); root.add_child(caster5)
	var s7 := _mk_shield(base.duplicate(), caster5)
	await process_frame
	caster5.is_defeated = true
	await process_frame
	await process_frame
	_assert("生命周期: 释放者被淘汰后盾自毁", not is_instance_valid(s7) or s7.is_queued_for_deletion())

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
