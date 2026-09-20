## P2-1 Step2 验收：_ball_mods 按投球者隔离 + 有效期（headless 可跑）
## ① 隔离：A 的修饰不进 B 的快照（不同 caster_id 模拟玩家/AI/被动不同来源）
## ② 过期：带 duration 的修饰到期后字段回落默认值
## ③ 取走即清：投球领走快照后，同 caster 二次投球不吃旧修饰
## ④ 兼容视图：旧 getter 读最近活跃 caster（AI/测试面板行为不变）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_ball_mods_isolation.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== ball_mods 按投球者隔离测试 ==========\n")
	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame
	await process_frame

	# ① 隔离：A(玩家路径) cast 增伤20% → A 快照吃到、B(AI路径) 快照不受影响
	handler.apply_tag_effect("ball_dmg_up_pct", {"value": 20}, 111)
	var snap_a: Dictionary = handler.take_ball_mods_snapshot(111)
	var snap_b: Dictionary = handler.take_ball_mods_snapshot(222)
	_assert("隔离: A 快照吃到自己的增伤 mult=1.2", absf(snap_a.dmg_mult - 1.2) < 0.001)
	_assert("隔离: B 快照不吃 A 的修饰 mult=1.0", absf(snap_b.dmg_mult - 1.0) < 0.001)

	# ③ 取走即清：同 caster 二次投球不吃旧修饰
	handler.apply_tag_effect("ball_speed_up_pct", {"multiplier": 1.5}, 111)
	var s1: Dictionary = handler.take_ball_mods_snapshot(111)
	var s2: Dictionary = handler.take_ball_mods_snapshot(111)
	_assert("取走即清: 第一次投球拿到 mult=1.5", absf(s1.speed_mult - 1.5) < 0.001)
	_assert("取走即清: 第二次投球回落默认 mult=1.0", absf(s2.speed_mult - 1.0) < 0.001)

	# ② 过期：带 duration 的修饰到期后回落默认；未到期正常生效
	handler.apply_tag_effect("ball_dmg_up_pct", {"value": 20, "duration": 10.0}, 333)
	var snap_now: Dictionary = handler.take_ball_mods_snapshot(333)
	_assert("未到期: 长 duration 生效中 mult=1.2", absf(snap_now.dmg_mult - 1.2) < 0.001)

	handler.apply_tag_effect("ball_dmg_up_pct", {"value": 20, "duration": 0.1}, 333)
	handler._match_clock += 0.5  # 推进比赛时钟
	var snap_exp: Dictionary = handler.take_ball_mods_snapshot(333)
	_assert("过期: 字段回落默认 mult=1.0", absf(snap_exp.dmg_mult - 1.0) < 0.001)

	# ④ 兼容视图：cast 后旧 getter 仍读最近活跃 caster（AI/测试面板行为不变）
	handler.apply_tag_effect("ball_dmg_up_pct", {"value": 30}, 444)
	_assert("兼容视图: get_modified_ball_damage 读最近 caster = 130", absf(handler.get_modified_ball_damage(100.0) - 130.0) < 0.001)
	_assert("兼容视图: is_ball_penetrating 默认 false", handler.is_ball_penetrating() == false)

	# ② 过期兜底清扫：全字段过期后 _process 清掉准备区
	handler.apply_tag_effect("ball_dmg_up_pct", {"value": 20, "duration": 0.1}, 555)
	handler._match_clock += 0.5
	await process_frame
	var swept: bool = not handler._ball_mods_by_caster.has(555)
	_assert("过期清扫: 全字段过期的准备区被 _process 回收", swept)

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
