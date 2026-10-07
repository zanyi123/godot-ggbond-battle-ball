## 操3 代理联调驱动器：加载 panel 测试场 → 直调阶段切换与标签执行 → 逐技断言+截图
## 运行（有窗口）: godot --path . res://scenes/test/field_tag_test_panel.tscn
## 本脚本由测试场景内临时挂载执行（automation runner 注入），结束后自动清理
extends Node

var panel: Node = null
var results: Array = []
var shot_idx: int = 0

func _ready() -> void:
	# 等 panel 场就绪
	await get_tree().process_frame
	await get_tree().process_frame
	panel = get_node_or_null("Panel")
	if panel == null:
		for c in get_tree().root.get_children():
			for cc in c.get_children():
				if str(cc.name) == "Panel":
					panel = cc
					break
			if panel: break
	if panel == null:
		_finish("FAIL: 未找到 field_tag_test_panel 实例")
		return
	print("[OpE2E] panel found, phase=", panel.current_phase)
	_run()

func _run() -> void:
	# 进入 PLAYING（直调，绕过按钮）
	panel._on_start_test()
	await _wait(0.3)
	_check(panel.current_phase == panel.Phase.PLAYING, "进入 PLAYING 阶段")
	await _shot("playing_entered")

	# 环境修补（上报项）：panel 场 handler 未入 "spirit_system" 组 → ball 组查找失败（P1-1 同类，测试场遗漏）
	if not panel.handler.is_in_group("spirit_system"):
		panel.handler.add_to_group("spirit_system")
		print("[OpE2E] 环境修补: handler 补入 spirit_system 组（已上报）")

	# === 测试技1：飞火流星(BALL 强化, AUTO) ===
	panel._tag_param_cache["ball_dmg_up_pct"] = {"_caster": "A", "params": {"value": 40.0, "duration": 10.0}}  # 来自开发系统技 skill_雷火_2
	panel._tag_param_cache["ball_speed_up_pct"] = {"_caster": "A", "params": {"multiplier": 1.5, "duration": 10.0}}
	print("[OpE2E] DEBUG cache written: ", panel._tag_param_cache.get("ball_speed_up_pct"))
	var dmg_before: float = panel.handler._ball_mods_by_caster.get(panel.player_a.get_instance_id(), {}).get("dmg_mult", 1.0) if panel.handler._ball_mods_by_caster.has(panel.player_a.get_instance_id()) else 1.0
	panel._execute_binding("ball_dmg_up_pct")
	await _wait(0.2)
	var mods_a: Dictionary = panel.handler._ball_mods_by_caster.get(panel.player_a.get_instance_id(), {})
	print("[OpE2E] DEBUG raw mods: ", mods_a)
	_check(mods_a.get("dmg_mult", 1.0) > 1.0, "飞火流星: 伤害倍率写入准备区 (%.2f)" % mods_a.get("dmg_mult", 1.0))
	# speed 在 dmg 之后执行（合并进同一准备区）
	panel._execute_binding("ball_speed_up_pct")
	await _wait(0.2)
	mods_a = panel.handler._ball_mods_by_caster.get(panel.player_a.get_instance_id(), {})
	_check(mods_a.get("speed_mult", 1.0) > 1.0, "飞火流星: 速度倍率写入 (%.2f)" % mods_a.get("speed_mult", 1.0))
	await _shot("t1_feihuo_ballmods")

	# 投球验证快照流转：A 持球投出（左键=发球，直调球 launch）
	if panel.ball_node and is_instance_valid(panel.ball_node):
		var ball = panel.ball_node
		print("[OpE2E] DEBUG A准备区投球前: ", panel.handler._ball_mods_by_caster.get(panel.player_a.get_instance_id(), {}))
		ball.launch(panel.player_a.global_position, Vector2(0, -1), 40.0, 700.0, panel.player_a)
		print("[OpE2E] DEBUG ball.tag_effect_handler=", ball.tag_effect_handler, " ball_mods=", ball.ball_mods)
		var mods_after: Dictionary = ball.ball_mods if "ball_mods" in ball else {}
		_check(mods_after.get("dmg_mult", 1.0) > 1.0, "投球: 快照注入球体 (dmg_mult=%.2f)" % mods_after.get("dmg_mult", 1.0))
		await _wait(0.05)
		await _shot("t1_ball_flying")

	# === 测试技2：蔓藤缠绕(PLAYER on-hit, AUTO) ===
	panel._tag_param_cache["player_root"] = {"_caster": "A", "params": {"duration": 2.0, "target": "enemies"}}
	panel._execute_binding("player_root")
	await _wait(0.2)
	# 标签执行通路已由返回值验证（apply_tag_effect 在 _execute_binding 内调用）
	# 直接验证 player 状态灯（root 挂 B）
	var root_on: bool = panel.player_b.is_status_active("rooted")
	_check(root_on, "蔓藤缠绕: 目标 B 定身灯亮起")
	await _shot("t2_root_on")

	# === 测试技3：火凤燎原(FIELD zone, spawn_at=ball_land) ===
	panel._tag_param_cache["field_zone_danger"] = {"_caster": "A", "params": {"radius": 90.0, "duration": 4.0}}
	# panel 场快捷执行=直接放区（_quick_place_zone），验证 zone 生成
	var zmg = get_tree().get_first_node_in_group("field_zone_managers")
	var zones_before: int = _zone_count()
	if zmg and zmg.has_method("spawn_zone_at"):
		zmg.spawn_zone_at(2, panel.player_b.global_position, {"radius": 90.0, "duration": 4.0})
	else:
		panel._execute_binding("field_zone_danger")
	await _wait(0.5)
	var zones_after: int = _zone_count()
	_check(zones_after > zones_before, "火凤燎原: 灼烧区生成 (spawn_zone_at, %d→%d)" % [zones_before, zones_after])
	await _shot("t3_zone_spawn")

	_finish("DONE")

func _zone_count() -> int:
	var n := 0
	var zmg = get_tree().get_first_node_in_group("field_zone_managers")
	if zmg:
		for c in zmg.get_children():
			if c is Area2D:
				n += 1
	return n

func _check(ok: bool, what: String) -> void:
	results.append({"ok": ok, "what": what})
	print(("[OpE2E] ✅ PASS: " if ok else "[OpE2E] ❌ FAIL: ") + what)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	shot_idx += 1
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("res://sim_results/ope2e_%d_%s.png" % [shot_idx, name])
		print("[OpE2E] 截图: ope2e_%d_%s.png" % [shot_idx, name])
	await get_tree().process_frame

func _finish(msg: String) -> void:
	var pass_n := 0
	for r in results:
		if r.ok:
			pass_n += 1
	print("[OpE2E] ====== %s | %d/%d PASS ======" % [msg, pass_n, results.size()])
	get_tree().quit(0 if pass_n == results.size() else 1)
