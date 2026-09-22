## 波6 验收：高难收官 5 原语（12 工单；#1 复制系待拆分方案批准，不在本测试）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_wave6_finale.gd
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
		return s == "cc_immune" and _cc
	func begin_carry_push(dir: Vector2, speed: float, dur: float, ball: Node) -> void:
		pass
	func set_carrying_ball(v: bool) -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波6 高难收官测试 ==========\n")
	for i in range(3):
		await process_frame
	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame

	# ===== #8 分裂 =====
	var mother: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(mother)
	var caster: StubPlayer = StubPlayer.new(); caster.team = "a"; root.add_child(caster)
	mother.is_active = true
	mother.attacker_player = caster
	mother.ball_damage = 100.0
	mother.ball_mods = mother._default_ball_mods()
	mother.ball_mods["spread_count"] = 3
	mother.ball_mods["spread_damage_ratio"] = 0.5
	mother.ball_mods["spread_trigger_dist_pct"] = 0.5
	mother.max_flight_distance = 100.0
	mother.flight_distance = 60.0  # 超过 50%
	mother._spawn_clones(3, 0.5)
	var clones: Array = []
	for child in mother.get_parent().get_children():
		if child != mother and child.get("is_clone") == true:
			clones.append(child)
	_assert("分裂: 生成 3 个子球", clones.size() == 3)
	var ratio_ok := true
	for c in clones:
		if absf(float(c.ball_damage) - 50.0) > 0.01:
			ratio_ok = false
	_assert("分裂: 子球伤害×0.5", ratio_ok)
	_assert("分裂: 子球 is_clone 不再分裂", clones.all(func(c): return c.is_clone == true))
	# 子球被接 → 球权转移（母球回手到接住者）+ 被接克隆消散
	# （其余子球独立飞行继续有效；直调 _catch_ball 避开物理连锁）
	var catcher: StubPlayer = StubPlayer.new(); catcher.team = "b"; catcher.character_id = ""; root.add_child(catcher)
	var taken = clones[0]
	taken._catch_ball(catcher)
	await process_frame
	_assert("分裂: 被接克隆消散", not is_instance_valid(taken) or taken.is_queued_for_deletion())
	for c in clones:
		if c != taken and is_instance_valid(c):
			c.queue_free()

	# ===== #14 飞行中球操作 =====
	var b2: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(b2)
	b2.is_active = true
	b2.attacker_player = caster
	b2.ball_damage = 100.0
	b2.ball_speed = 200.0
	b2.boost_in_flight({"dmg_pct": 0.3, "speed_pct": 0.2})
	_assert("推进: dmg×1.3 speed×1.2", absf(b2.ball_damage - 130.0) < 0.01 and absf(b2.ball_speed - 240.0) < 0.01)
	caster.position = Vector2(0, 0)
	b2.global_position = Vector2(200, 0)
	b2.ball_direction = Vector2.RIGHT
	b2.recall_ball(1)
	_assert("拉回: 朝投掷者转向", b2.ball_direction.x < -0.99)
	b2.queue_free()

	# ===== #14 pending 消费（ATTACK_LAUNCHED 回调直调）=====
	handler._pending_in_flight[caster.get_instance_id()] = {"mods": {"dmg_pct": 0.1}, "expires_at": 99999.0}
	var b3: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(b3)
	b3.is_active = true
	b3.attacker_player = caster
	b3.ball_damage = 100.0
	caster.set("ball_ref", b3)  # P1-1 注入惯例：pending 消费兜底路径从 ball_ref 取球
	# 直接调 handler 消费回调（绕过事件总线，与总线订阅同函数）
	handler._on_attack_launched({"attacker": caster})
	_assert("pending: ATTACK_LAUNCHED 消费扣 10%", absf(b3.ball_damage - 110.0) < 0.01)
	_assert("pending: 消费后清除", not handler._pending_in_flight.has(caster.get_instance_id()))
	b3.queue_free()

	# ===== #17 手动制导 =====
	var pilot: StubPlayer = StubPlayer.new(); pilot.team = "a"; pilot.is_player_controlled = true; root.add_child(pilot)
	pilot.max_spirit_energy = 100.0; pilot.spirit_energy = 50.0
	var mb: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(mb)
	mb.is_active = true
	mb.attacker_player = pilot
	mb.ball_mods = mb._default_ball_mods()
	mb.ball_mods["manual_steering"] = true
	mb.ball_mods["manual_energy_per_sec"] = 3.0
	mb.ball_mods["manual_max_duration"] = 1.0
	mb.begin_manual_steering()
	_assert("制导: 手动态开启", mb.get("_manual_active") == true)
	pilot.facing_direction = Vector2(0, 1)
	mb.manual_steer(pilot.facing_direction)
	_assert("制导: 转向生效", mb.ball_direction.distance_to(Vector2(0, 1)) < 0.01)
	# AI 球退化为直线（不进手动态）
	var ai_p: StubPlayer = StubPlayer.new(); ai_p.team = "b"; ai_p.is_player_controlled = false; root.add_child(ai_p)
	var ab: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(ab)
	ab.is_active = true
	ab.attacker_player = ai_p
	ab.ball_mods = ab._default_ball_mods()
	ab.ball_mods["manual_steering"] = true
	ab.begin_manual_steering()
	_assert("制导: AI 球退化为直线(不进手动态)", ab.get("_manual_active") == false)
	# 超时回直线
	mb._manual_time_left = 0.01
	mb.ball_direction = Vector2(0, 1)
	mb._physics_process(0.02)
	_assert("制导: 超时回直线(退出手动态)", mb.get("_manual_active") == false)

	# ===== #18 带人位移 =====
	var dragged: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	dragged.max_stamina = 100.0; dragged.stamina = 100.0; dragged.character_id = ""
	dragged.team = "b"
	root.add_child(dragged)
	var pb: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(pb)
	pb.is_active = true
	pb.ball_mods = pb._default_ball_mods()
	pb.ball_mods["carry_pull_speed"] = 200.0
	pb.ball_mods["carry_max_duration"] = 1.0
	pb.ball_direction = Vector2.RIGHT
	dragged.begin_carry_push(Vector2.RIGHT, 200.0, 1.0, pb)
	var d0: Vector2 = dragged.global_position
	dragged._tick_all_timers(0.5)
	_assert("带人: 拖拽位移 (右移100)", dragged.global_position.distance_to(d0 + Vector2(100, 0)) < 1.0)
	# 球消失即释放
	pb.queue_free()
	dragged._tick_all_timers(0.5)
	_assert("带人: 球消失即释放", dragged._carry_push.is_empty())
	# 免控拒绝
	var immune: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	immune.max_stamina = 100.0; immune.stamina = 100.0; immune.character_id = ""
	immune._status_lights["cc_immune"] = {"on": true, "remaining": 5.0}
	root.add_child(immune)
	var b4: Node = load("res://scripts/battle/ball.gd").new()
	root.add_child(b4)
	b4.is_active = true
	b4.ball_direction = Vector2.RIGHT
	immune.begin_carry_push(Vector2.RIGHT, 200.0, 1.0, b4)
	_assert("带人: 免控目标拒绝", immune._carry_push.is_empty())

	# ===== #9 视野迷雾 =====
	var mgr = load("res://scripts/battle/field_zone_manager.gd").new()
	root.add_child(mgr)
	await process_frame
	# P1 修正用例：a 队施法 → a 队观察者不受影响、b 队被削弱
	var fog_params := {"zone_type": 5, "width": 200.0, "height": 200.0, "duration": 10.0, "perception_scale": 0.4, "caster_team": "a"}
	mgr.spawn_zone_at(5, Vector2(0, 0), fog_params)
	_assert("迷雾: 雾内敌方感知倍率 0.4", absf(float(mgr.get_perception_scale_at(Vector2(10, 10), "b")) - 0.4) < 0.01)
	_assert("迷雾: 雾内本方不受影响 (=1.0)", absf(float(mgr.get_perception_scale_at(Vector2(10, 10), "a")) - 1.0) < 0.01)
	_assert("迷雾: 雾外感知倍率 1.0", absf(float(mgr.get_perception_scale_at(Vector2(5000, 5000), "b")) - 1.0) < 0.01)

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
