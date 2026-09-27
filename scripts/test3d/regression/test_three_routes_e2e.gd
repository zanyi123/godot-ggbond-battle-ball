## 三大类原语标签链路统一验收（主人令 2026-09-27）：BALL/PLAYER/FIELD 各走完整链
## BALL：释放(随球)→投出命中→球属性/印记落地；PLAYER：选人/自体→状态灯+图标条；FIELD：zone 落地+可视
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_three_routes_e2e.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 三大类原语标签链路统一验收 ==========\n")
	for i in range(3):
		await process_frame
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame
	var pa: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	pa.team = "a"
	pa.attack_power = 50.0
	pa.defense = 20.0
	pa.spirit_energy = 100.0
	root.add_child(pa)
	var enemy: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	enemy.team = "b"
	enemy.defense = 0.0
	root.add_child(enemy)
	await process_frame
	var roster: Array[Node] = [pa, enemy]
	handler.players = roster
	var zmg: Node = load("res://scripts/battle/field_zone_manager.gd").new()
	root.add_child(zmg)
	await process_frame
	var icon_bar: Control = load("res://scripts/battle/status_icon_bar.gd").new()
	root.add_child(icon_bar)
	icon_bar.bind_player(enemy)   # 盯被打者的图标条

	# ==================== BALL 路线：伤害/速度注入+随球印记命中落地 ====================
	var rb: Dictionary = handler._do_apply_tag("ball_dmg_up_pct", {"value": 40.0}, pa.get_instance_id())
	var rs: Dictionary = handler._do_apply_tag("ball_speed_up_pct", {"multiplier": 1.5}, pa.get_instance_id())
	var rm: Dictionary = handler._do_apply_tag("player_mark_apply", {"mark_id": "frost", "max_stacks": 5, "duration": 8.0}, pa.get_instance_id())
	await process_frame
	_assert("BALL①: 伤害/速度注入准备区", bool(rb.get("success")) and bool(rs.get("success")) \
		and float(handler._ball_mods_by_caster.get(pa.get_instance_id(), {}).get("dmg_mult", 1.0)) > 1.3 \
		and float(handler._ball_mods_by_caster.get(pa.get_instance_id(), {}).get("speed_mult", 1.0)) > 1.3)
	_assert("BALL①: 随球印记暂存(不挂己)", rm.get("on_hit_pending") == true and pa.get_mark_count("frost") == 0)
	var ball: Area2D = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	ball.tag_effect_handler = handler
	ball.launch(pa.global_position, Vector2(0.0, 1.0).normalized(), 30.0, 400.0, pa)
	await process_frame
	_assert("BALL②: 投出→快照注入球体(dmg×1.4 spd×1.5)", \
		float(ball.ball_mods.get("dmg_mult", 1.0)) > 1.3 and float(ball.ball_mods.get("speed_mult", 1.0)) > 1.3 \
		and absf(float(ball.ball_damage) - 30.0 * float(ball.ball_mods.get("dmg_mult", 1.0))) < 8.0)
	# 命中敌人 → 印记落地+伤害按倍率结算
	ball._on_body_entered(enemy)
	await process_frame
	_assert("BALL③: 命中→敌人印记+1(随球 on-hit 落地)", enemy.get_mark_count("frost") == 1)
	_assert("BALL③: 命中伤害按倍率结算(30×1.4=42级)", float(ball.ball_damage) > 35.0)
	ball.queue_free()

	# ==================== PLAYER 路线：定身/禁疗/图标条反射 ====================
	var rp1: Dictionary = handler._do_apply_tag("player_root", {"duration": 2.0, "target": "enemies"}, pa.get_instance_id())
	print("[DBG-P] rp1=", rp1)
	await process_frame
	_assert("PLAYER①: root target=enemies→敌人定身灯", enemy.is_status_active("rooted"))
	var rp2: Dictionary = handler._do_apply_tag("player_heal_block", {"duration": 3.0, "target": "enemies"}, pa.get_instance_id())
	await process_frame
	_assert("PLAYER②: 禁疗灯亮+heal 返 0", enemy.is_status_active("heal_block") and enemy.heal(30.0) == 0.0)
	_assert("PLAYER③: 图标条反射(锢+疗 双图标)", "rooted" in icon_bar.get_entry_keys() and "heal_block" in icon_bar.get_entry_keys())
	enemy.turn_off_light("rooted")
	enemy.turn_off_light("heal_block")

	# ==================== FIELD 路线：危险区落地+可视 ====================
	# ==================== FIELD 路线：危险区落地+可视+伤害 ====================
	# FIELD 类（zone/障碍）语义=鼠标放置（PLACE）；headless 验收按既定口径用 spawn_zone_at 直调
	# （等同玩家左键确认后的落点，op_e2e/20 工单 B 段同口径）
	var rf = zmg.spawn_zone_at(2, Vector2(0, 0), {"width": 150.0, "height": 150.0, "damage_value": 10.0, "duration": 3.0})
	_assert("FIELD①: 危险区生成(zone 实体)", rf != null and is_instance_valid(rf))
	var vis_ok := false
	for c in rf.get_children():
		if c is ColorRect or c is Line2D:
			vis_ok = true
	_assert("FIELD②: zone 可视节点存在(色块/边框)", vis_ok)
	var h0: float = enemy.stamina
	enemy.global_position = rf.global_position
	await process_frame
	await create_timer(0.5).timeout
	_assert("FIELD③: 敌人站入危险区→持续掉血", enemy.stamina < h0)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 三大类原语标签链路全部可行且已测！")
	quit(1 if _fail > 0 else 0)

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
