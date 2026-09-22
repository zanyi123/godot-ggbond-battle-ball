## 波5 验收：管道/zone 扩展 4 原语（11 工单 §三，headless 可跑）
## 前置 P2-5 已修复（zone 走公开面）本测试全部经公开接口验证
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_wave5_extensions.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var team: String = "b"
	var is_defeated: bool = false
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var max_spirit_energy: float = 100.0
	var spirit_energy: float = 100.0
	var char_data: Dictionary = {"name": "stub"}
	var defense: float = 0.0
	var defense_factor: float = 0.15
	func get_defense_resist() -> float:
		return 0.0
	func heal(amount: float) -> float:
		if is_defeated:
			return 0.0
		var b: float = stamina
		stamina = minf(max_stamina, stamina + amount)
		return stamina - b
	func drain_stamina(amount: float) -> float:
		if is_defeated:
			return 0.0
		var a: float = minf(stamina, amount)
		stamina -= a
		return a


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波5 管道/zone 扩展测试 ==========\n")
	for i in range(3):
		await process_frame
	var mgr = load("res://scripts/battle/field_zone_manager.gd").new()
	root.add_child(mgr)
	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	await process_frame
	await process_frame
	var real_player: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	real_player.max_stamina = 100.0
	real_player.stamina = 50.0
	real_player.character_id = ""
	root.add_child(real_player)
	await process_frame
	var hr: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	hr.max_stamina = 100.0; hr.stamina = 40.0; hr.character_id = ""
	root.add_child(hr)
	await process_frame
	# handler 名册注入（目标选取依赖）
	var h_roster: Array[Node] = [real_player, hr]
	handler.players = h_roster

	# ===== P2-5 前置回归：danger tick 走公开面（drain_stamina）=====
	real_player.turn_on_light("invincible", 5.0)
	var applied: float = real_player.drain_stamina(30.0)
	_assert("P2-5: 无敌时环境伤害=0", applied == 0.0)
	real_player.turn_off_light("invincible")
	var heal_ret: float = real_player.heal(25.0)
	_assert("P2-5: heal 公开接口回血", absf(heal_ret - 25.0) < 0.01)
	real_player.turn_on_light("heal_block", 5.0)
	_assert("P2-5联动: heal_block 时 heal=0", real_player.heal(25.0) == 0.0)
	real_player.turn_off_light("heal_block")

	# ===== #10 叠层印记 =====
	var p := _mk_player()
	p.turn_on_light("rooted", 5.0)
	var c1: int = p.apply_mark("frost", 3, 5.0)
	var c2: int = p.apply_mark("frost", 3, 5.0)
	var c3: int = p.apply_mark("frost", 3, 5.0)
	var c4: int = p.apply_mark("frost", 3, 5.0)
	_assert("印记: 叠至3层封顶 (1,2,3,3)", [c1, c2, c3, c4] == [1, 2, 3, 3])
	_assert("印记: get_mark_count 读数", p.get_mark_count("frost") == 3)
	p.clear_mark("frost")
	_assert("印记: 清层后归零", p.get_mark_count("frost") == 0)
	# 过期全清
	p.apply_mark("burn", 5, 0.05)
	p._tick_marks(0.1)
	_assert("印记: 过期全清", p.get_mark_count("burn") == 0)
	# 两个 mark_id 互不干扰
	p.apply_mark("a", 5, 5.0)
	p.apply_mark("b", 5, 5.0)
	_assert("印记: 不同 mark_id 互不干扰", p.get_mark_count("a") == 1 and p.get_mark_count("b") == 1)

	# ===== handler 印记阈值端到端（真实 player 管道；hr 已在上方创建并注入名册）=====
	handler.priority_queue_enabled = false
	await process_frame
	# 每层印记叠加到 2 层触发 heal(30)：对 hr 自身
	var mark_params := {"mark_id": "healmark", "max_stacks": 2, "duration": 5.0,
		"threshold_count": 2, "threshold_tag": "player_hp_heal_flat",
		"threshold_params": {"value": 30.0}, "clear_on_trigger": true, "target": "self"}
	handler._do_apply_tag("player_mark_apply", mark_params.duplicate(), hr.get_instance_id())
	handler._do_apply_tag("player_mark_apply", mark_params.duplicate(), hr.get_instance_id())
	await process_frame
	_assert("印记阈值端到端: 2层触发 heal_flat(40→70)", absf(hr.stamina - 70.0) < 0.01 and hr.get_mark_count("healmark") == 0)

	# ===== #13 toggle 维持型 =====
	var t: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(t)
	await process_frame
	var tp: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	tp.max_stamina = 100.0; tp.stamina = 100.0; tp.max_spirit_energy = 100.0
	tp.spirit_energy = 20.0; tp.character_id = ""
	root.add_child(tp)
	await process_frame
	t._skills_cache["test_toggle"] = {"id": "test_toggle", "type": "active", "mode": "toggle",
		"energy_cost": 0, "cooldown": 0.0, "tags": ["player_spd_up_pct"],
		"tag_params": {"player_spd_up_pct": {"value": 30.0, "energy_per_sec": 5.0}}}
	var t_roster: Array[Node] = [tp]
	t.players = t_roster
	var tskills: Array[String] = ["test_toggle"]
	t.set_player_skills(tp.get_instance_id(), tskills)
	var open_ok: bool = t.trigger_skill(tp.get_instance_id(), "test_toggle", {})
	_assert("toggle: 开启成功且灯亮", open_ok and tp.is_status_active("spd_up_toggle"))
	var e_open: float = tp.spirit_energy
	tp._tick_all_timers(1.0)
	# 净 -4：toggle 扣 5/s，能量自然回复 +1/s 并存
	_assert("toggle: 每秒净耗能 4 (扣5回1)", absf(e_open - tp.spirit_energy - 4.0) < 0.01)
	var close_ok: bool = t.trigger_skill(tp.get_instance_id(), "test_toggle", {})
	_assert("toggle: 再按关闭且效果全清", close_ok and not tp.is_status_active("spd_up_toggle") and tp.active_toggles.is_empty())
	# 能量尽自动关
	tp.spirit_energy = 0.3
	t.trigger_skill(tp.get_instance_id(), "test_toggle", {})
	tp._tick_all_timers(1.0)
	_assert("toggle: 能量尽自动关+信号", not tp.active_toggles.has("test_toggle"))

	# ===== #3 治疗区 =====
	var heal_params := {"zone_type": 4, "width": 200.0, "height": 200.0, "heal_per_sec": 20.0}
	var z = mgr.spawn_zone_at(4, Vector2(0, 0), heal_params)
	_assert("治疗区: zone_type=4 生成", is_instance_valid(z) and int(z.zone_type) == 4)
	var victim := _mk_player(); victim.stamina = 40.0; victim.team = "a"; root.add_child(victim)
	mgr.zones  # noop
	z._players_inside[victim.get_instance_id()] = {"player": victim}
	z._process_heal_tick(1.0)
	_assert("治疗区: 区内回血 20", absf(victim.stamina - 60.0) < 0.01)
	victim.turn_on_light("heal_block", 5.0)
	z._process_heal_tick(1.0)
	_assert("治疗区: 禁疗灯下不回血", absf(victim.stamina - 60.0) < 0.01)
	z.force_remove()

	# ===== #12 zone 作用于球 =====
	var ball = load("res://scripts/battle/ball.gd").new()
	root.add_child(ball)
	ball.ball_damage = 100.0
	ball.ball_speed = 200.0
	ball.is_active = true
	var ab_params := {"zone_type": 2, "width": 200.0, "height": 200.0, "damage_value": 5.0,
		"affect_ball": {"dmg_pct": 0.3, "speed_pct": 0.2}}
	var zb = mgr.spawn_zone_at(2, Vector2(0, 0), ab_params)
	zb.ball_ref = ball
	zb.zone_ball_passed.connect(ball._on_zone_ball_passed)
	ball.global_position = Vector2(0, 0)
	zb._process(0.016)
	_assert("#12: 球穿区一次性强化 (dmg130/spd240)", absf(ball.ball_damage - 130.0) < 0.01 and absf(ball.ball_speed - 240.0) < 0.01)
	ball.global_position = Vector2(5000, 5000)
	zb._process(0.016)
	ball.global_position = Vector2(0, 0)
	zb._process(0.016)
	_assert("#12: 离开再穿越重复触发 (dmg169)", absf(ball.ball_damage - 169.0) < 0.01)
	ball.queue_free()
	zb.force_remove()

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _mk_player() -> CharacterBody2D:
	var p: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	p.max_stamina = 100.0
	p.stamina = 100.0
	p.max_spirit_energy = 100.0
	p.spirit_energy = 100.0
	p.character_id = ""
	root.add_child(p)
	return p


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
