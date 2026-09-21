## V1-3 验收：区域触发原语 zone 坐标入口 + 球落点钩子（06 文档 §四断言清单，headless 可跑）
## 覆盖：坐标入口/ball_land/ball_stop/pending过期/鼠标路径不登记/E2一次性/既有zone生命周期
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_zone_spawn_at.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 区域触发测试 ==========\n")
	var mgr = load("res://scripts/battle/field_zone_manager.gd").new()
	root.add_child(mgr)
	await process_frame
	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	await process_frame
	await process_frame

	# ===== ① 坐标入口：spawn_zone_at 在指定坐标生成正确类型的 zone =====
	var zp := {"width": 90.0, "height": 90.0, "duration": 4.0, "effect_value": 8.0}
	var z1 = mgr.spawn_zone_at(2, Vector2(123, 456), zp.duplicate())
	_assert("坐标入口: zone 生成于指定坐标", is_instance_valid(z1) and z1.global_position.distance_to(Vector2(123, 456)) < 1.0)
	_assert("坐标入口: 类型/数值正确", int(z1.zone_type) == 2 and absf(float(z1.effect_value) - 8.0) < 0.01)
	_assert("坐标入口: 注册进 manager 名册", mgr.zones.has(z1))

	# ===== ②③ ball_land / ball_stop 触发 =====
	var params_land := {"radius": 90.0, "duration": 4.0, "damage_value": 8.0, "spawn_at": "ball_land"}
	handler._apply_field_zone_effect(params_land, 2)
	_assert("ball_land: 登记待发 pending", handler._pending_zone_spawns.size() == 1)
	handler._on_ball_first_land(Vector2(-200, 100))
	await process_frame
	_assert("ball_land: 落点生成 zone 且 pending 清空", handler._pending_zone_spawns.is_empty() and mgr.zones.any(func(z): return z.global_position.distance_to(Vector2(-200, 100)) < 1.0))

	var params_stop := {"radius": 130.0, "duration": 5.0, "slow_multiplier": 1.4, "spawn_at": "ball_stop"}
	handler._apply_field_zone_effect(params_stop, 1)
	handler._on_ball_stopped(Vector2(50, -60))
	await process_frame
	_assert("ball_stop: 停点生成 zone", handler._pending_zone_spawns.is_empty() and mgr.zones.any(func(z): return z.global_position.distance_to(Vector2(50, -60)) < 1.0))

	# ===== E2 一次性：消费后再发同信号不再生成 =====
	var zones_before: int = mgr.zones.size()
	handler._on_ball_first_land(Vector2(10, 10))
	await process_frame
	_assert("E2: pending 消费后二次触地不再生成", mgr.zones.size() == zones_before)

	# ===== ④ pending 过期清理不泄漏 =====
	handler._apply_field_zone_effect({"radius": 90.0, "duration": 4.0, "damage_value": 8.0, "spawn_at": "ball_land"}, 2)
	_assert("过期: 登记成功待清理", handler._pending_zone_spawns.size() == 1)
	handler._match_clock += 31.0
	handler._cleanup_expired_zone_spawns()
	_assert("过期: 30s 兜底清理 pending 不泄漏", handler._pending_zone_spawns.is_empty())

	# ===== ⑤ 鼠标路径不回归：无 spawn_at 不登记 pending（走 start_placing 后取消）=====
	var before_mouse: int = handler._pending_zone_spawns.size()
	handler._apply_field_zone_effect({"width": 100.0, "duration": 3.0, "boost_multiplier": 1.5}, 0)
	_assert("鼠标路径: 无 spawn_at 不登记 pending", handler._pending_zone_spawns.size() == before_mouse)
	mgr.cancel_operation()

	# ===== ⑥ zone 既有生命周期：force_remove 正常移除 =====
	var z2 = mgr.spawn_zone_at(3, Vector2(0, 0), {"duration": 2.0})
	var count_before: int = mgr.zones.size()
	z2.force_remove()
	await process_frame
	_assert("生命周期: 移除后名册更新", mgr.zones.size() == count_before - 1)

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
