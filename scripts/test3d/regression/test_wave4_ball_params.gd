## 波4 验收：球类参数化 4 原语（规划版 10 工单，命名已对齐，headless 可跑）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_wave4_ball_params.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "b"
	var is_defeated: bool = false
	var _stealth: bool = false
	func is_status_active(s: String) -> bool:
		return s == "stealthed" and _stealth
	func get_hit_z_range() -> Vector2:
		return Vector2(127.0, 77.0)  # 跳跃顶点窗口


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波4 球类参数化测试 ==========\n")
	for i in range(3):
		await process_frame
	var ball = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame
	await process_frame

	# ===== #15 反弹增强（max_bounces / speed_keep_pct）=====
	ball.use_wall_bounce = true
	ball.wall_bounce_count = 0
	ball.ball_mods = ball._default_ball_mods()
	ball.ball_mods["bounce_max"] = 2
	ball.ball_speed = 300.0
	ball.global_position = Vector2(ball.WALL_X_MIN - 5.0, 0.0)
	ball.ball_direction = Vector2.LEFT
	ball._bounce_off_walls()
	_assert("反弹: 第1次撞墙方向反射", ball.ball_direction.x > 0.0 and ball.wall_bounce_count == 1)
	ball.global_position = Vector2(ball.WALL_X_MIN - 5.0, 0.0)
	ball.ball_direction = Vector2.LEFT
	ball._bounce_off_walls()
	_assert("反弹: 第2次仍反射 (max=2)", ball.ball_direction.x > 0.0 and ball.wall_bounce_count == 2)
	ball.global_position = Vector2(ball.WALL_X_MIN - 5.0, 0.0)
	ball.ball_direction = Vector2.LEFT
	ball._bounce_off_walls()
	_assert("反弹: 第3次超限不反弹", ball.ball_direction.x < 0.0 and ball.wall_bounce_count == 2)
	ball.wall_bounce_count = 0
	ball.ball_mods["bounce_speed_mult"] = 1.2
	ball.ball_speed = 100.0
	ball.global_position = Vector2(ball.WALL_X_MIN - 5.0, 0.0)
	ball.ball_direction = Vector2.LEFT
	ball._bounce_off_walls()
	_assert("反弹加速: 速度×1.2 (speed_keep_pct)", absf(ball.ball_speed - 120.0) < 0.01)
	ball.ball_mods = ball._default_ball_mods()
	ball.wall_bounce_count = 0
	for i in range(5):
		ball.global_position = Vector2(ball.WALL_X_MIN - 5.0, 0.0)
		ball.ball_direction = Vector2.LEFT
		ball._bounce_off_walls()
	_assert("默认回归: 无上限反弹不受限", ball.wall_bounce_count == 5 and ball.ball_direction.x > 0.0)

	# ===== #22 必中 =====
	var jumper := StubPlayer.new(); root.add_child(jumper)
	ball.ball_z = 55.0
	_assert("必中-前置: 普通球打不到跳跃顶点", ball._can_hit_target_at(jumper) == false)
	ball.ball_mods["sure_hit"] = true
	_assert("必中: 高度窗豁免命中跳跃者", ball._can_hit_target_at(jumper) == true)
	# 追踪：隐身丢失豁免 + 无限制转向
	ball.is_active = true
	ball.ball_mods["sure_hit"] = false
	ball.ball_mods["tracking_target"] = jumper
	ball.ball_mods["tracking_turn_speed"] = 0.0  # 普通追踪0转速=不转向
	jumper._stealth = true
	ball._physics_process(0.016)
	_assert("追踪-回归: 普通追踪目标隐身丢失", ball.ball_mods.get("tracking_target") == null)
	jumper.position = Vector2(0, 0)
	ball.position = Vector2(-100, 0)
	ball.ball_direction = Vector2.UP  # 故意朝错方向
	ball.ball_mods["tracking_target"] = jumper
	ball.ball_mods["sure_hit"] = true
	ball._physics_process(0.016)
	var to_jumper: Vector2 = (jumper.global_position - ball.global_position).normalized()
	_assert("必中: 转向无速率限制(直接对准)", ball.ball_direction.distance_to(to_jumper) < 0.01)
	_assert("必中: 追踪目标隐身不丢", ball.ball_mods.get("tracking_target") == jumper)
	ball.is_active = false

	# ===== #23 球形态 =====
	ball.ball_mods = ball._default_ball_mods()
	ball.ball_mods["size_scale"] = 2.0
	ball.reset()
	_assert("形态: reset 恢复视觉尺寸 1.0", ball.ball_visual.scale.distance_to(Vector2.ONE) < 0.01)

	# ===== #7 球隐身（ball_stealth / is_stealthed）=====
	var caster_a := StubPlayer.new(); caster_a.team = "a"; root.add_child(caster_a)
	var enemy_b := StubPlayer.new(); enemy_b.team = "b"; root.add_child(enemy_b)
	ball.attacker_player = caster_a
	_assert("隐身-默认: 非隐身球 is_stealthed=false", ball.is_stealthed() == false)
	handler._apply_ball_stealth({}, 7001)
	var snap: Dictionary = handler.take_ball_mods_snapshot(7001)
	ball.ball_mods = snap
	_assert("隐身: is_stealthed()=true", ball.is_stealthed() == true)
	_assert("隐身: 施法者队友可见", ball.is_ball_visible_to(caster_a) == true)
	_assert("隐身: 敌方不可见", ball.is_ball_visible_to(enemy_b) == false)

	# ===== handler 端到端（规划版参数名）=====
	handler._apply_ball_bounce_enhance({"max_bounces": 6, "speed_keep_pct": 1.1}, 9001)
	handler._apply_ball_sure_hit({}, 9001)
	handler._apply_ball_transform({"size_scale": 2.0}, 9001)
	handler._apply_ball_stealth({}, 9001)
	var snap2: Dictionary = handler.take_ball_mods_snapshot(9001)
	_assert("端到端: 快照四字段就位(规划版参数)", int(snap2.bounce_max) == 6 and absf(snap2.bounce_speed_mult - 1.1) < 0.01 \
		and snap2.sure_hit == true and absf(snap2.size_scale - 2.0) < 0.01 and snap2.hidden_from_enemies == true)
	var snap_b: Dictionary = handler.take_ball_mods_snapshot(9002)
	_assert("隔离回归: B 快照不吃 A 修饰", int(snap_b.bounce_max) == 0 and snap_b.sure_hit == false)

	# ===== 波3 规划版命名别名端到端 =====
	var nb_result: Variant = handler._do_apply_tag("player_energy_block", {"duration": 3.0}, 9101)
	_assert("波3命名: player_energy_block case 可执行", nb_result is Dictionary and bool(nb_result.get("success", false)))

	# ===== AI 评分（规划版命名）=====
	var ai = load("res://scripts/battle/spirit_ai_manager.gd").new()
	root.add_child(ai)
	var intents: Dictionary = ai._compute_tag_intents("on_ball", {"ball_sure_hit": {}})
	_assert("AI评分: 必中 attack=0.9", absf(float(intents["attack"]) - 0.9) < 0.01)

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
