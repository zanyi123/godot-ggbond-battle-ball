## 命中传递管线端到端验收（2026-09-27 修复"印记挂自己"）：释放印记球技→随球暂存→球命中敌人→敌人身上印记
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_on_hit_chain.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 命中传递管线端到端（on-hit 随球标签）==========\n")
	for i in range(3):
		await process_frame
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	await process_frame
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "a"
	caster.spirit_energy = 100.0
	root.add_child(caster)
	var victim: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	victim.team = "b"
	victim.attack_power = 50.0   # dot 的 attack_mult=有效攻击/attack_power，0 会 0/0=NaN 污染 stamina
	victim.defense = 20.0
	root.add_child(victim)
	await process_frame
	var roster: Array[Node] = [caster, victim]
	handler.players = roster
	var cid: int = caster.get_instance_id()

	# ===== ① 释放印记球技：随球暂存（施法者自己 NOT 挂印记）=====
	var r1: Dictionary = handler._do_apply_tag("player_mark_apply",
		{"mark_id": "frost", "max_stacks": 5, "duration": 6.0}, cid)
	await process_frame
	_assert("①: 释放→随球暂存(success+pending)", bool(r1.get("success", false)) and bool(r1.get("on_hit_pending", false)))
	_assert("①: 施法者自己 NOT 被挂印记（缺陷修复核心）", caster.get_mark_count("frost") == 0)

	# ===== ② 球命中敌人：以被命中者消费 → 敌人身上印记 +1 =====
	var consumed: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("②: 命中消费=1 个标签", consumed == 1)
	_assert("②: 敌人身上印记 +1（get_mark_count=1）", victim.get_mark_count("frost") == 1)
	_assert("②: 施法者依旧无印记", caster.get_mark_count("frost") == 0)

	# ===== ③ 一球一清：二次消费=0（防重复）=====
	var consumed2: int = handler.consume_hit_tags(cid, victim)
	_assert("③: 消费后暂存清空（二次消费=0）", consumed2 == 0)

	# ===== ④ 多标签同球：印记+减速+眩晕 一次命中全部落到敌人 =====
	handler._do_apply_tag("player_mark_apply", {"mark_id": "fire", "max_stacks": 3, "duration": 8.0}, cid)
	handler._do_apply_tag("player_move_slow", {"multiplier": 1.3, "duration": 2.0}, cid)
	handler._do_apply_tag("player_stun", {"duration": 1.0}, cid)
	await process_frame
	var c3: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("④: 多标签一次命中全消费(3)", c3 == 3)
	var speed_now: float = victim._get_effective_value("speed", victim.speed)
	var base_speed: float = victim.speed
	_assert("④: 敌人 印记+减速(speed %.0f→%.0f)+眩晕灯 全部生效" % [base_speed, speed_now],
		victim.get_mark_count("fire") == 1 and speed_now < base_speed and victim.is_status_active("stunned"))

	# ===== ⑤ 未命中清空：耗尽/回收路径不留残留 =====
	handler._do_apply_tag("player_mark_apply", {"mark_id": "frost", "max_stacks": 5, "duration": 6.0}, cid)
	handler.clear_hit_tags(cid)
	var c4: int = handler.consume_hit_tags(cid, victim)
	_assert("⑤: 清空后消费=0", c4 == 0)

	# ===== ⑥ 过期不传递（TTL 防陈旧）：暂存后推时钟过 8s TTL → 消费=0（2026-09-27 分流语义后用无 target 的 mark 验证）=====
	var frost_before: int = victim.get_mark_count("frost")
	handler._do_apply_tag("player_mark_apply", {"mark_id": "stale", "max_stacks": 3, "duration": 6.0}, cid)
	handler._match_clock += 9.0   # 推过 8s TTL
	var c5: int = handler.consume_hit_tags(cid, victim)
	await process_frame
	_assert("⑥: 过期标签不消费（TTL 生效，不污染目标）", c5 == 0 and victim.get_mark_count("stale") == 0 and victim.get_mark_count("frost") == frost_before)

	# ===== 22-2 on-hit 矩阵：11 条逐条"暂存→消费→按各自落地方式断言"（2026-09-27 工单）=====
	# 每条独立轮：登记（无目标→暂存）→consume 到 victim→真行为断言→复位
	var matrix := {
		"player_mark_apply": {"params": {"mark_id": "m1", "max_stacks": 3, "duration": 5.0},
			"check": func(): return victim.get_mark_count("m1") >= 1, "reset": func(): victim.clear_mark("m1")},
		"player_move_slow": {"params": {"multiplier": 1.4, "duration": 3.0},
			"check": func(): return victim._get_effective_value("speed", victim.speed) < victim.speed,
			"reset": func(): victim.turn_off_light("speed_down")},
		"player_stun": {"params": {"duration": 2.0},
			"check": func(): return victim.is_status_active("stunned"), "reset": func(): victim.turn_off_light("stunned")},
		"player_root": {"params": {"duration": 2.0},
			"check": func(): return victim.is_status_active("rooted"), "reset": func(): victim.turn_off_light("rooted")},
		"player_heal_block": {"params": {"duration": 3.0},
			"check": func(): return victim.heal(30.0) == 0.0,
			"reset": func(): victim.turn_off_light("heal_block")},
		"player_energy_block": {"params": {"duration": 3.0},
			"check": func():
				var e0: float = victim.spirit_energy
				victim._tick_all_timers(1.0)   # 回能 tick（真函数）：灯亮时不回复（+delta 被拦）
				return victim.spirit_energy == e0,
			"reset": func(): victim.turn_off_light("energy_block")},
		"player_hp_dot": {"params": {"value": 6.0, "duration": 3.0},
			"check": func():
				var h0: float = victim.stamina
				victim._tick_all_timers(0.5)
				return victim.stamina < h0,
			"reset": func(): victim.turn_off_light("hp_dot")},
		"player_vulnerable": {"params": {"multiplier": 1.5, "duration": 3.0},
			"check": func():
				var d1: float = float(victim.take_damage(100.0, null, "")["damage"])
				victim.turn_off_light("vulnerable")
				var d2: float = float(victim.take_damage(100.0, null, "")["damage"])
				return d1 > d2,
			"reset": func(): pass},
		"player_disarm": {"params": {"duration": 3.0},
			"check": func(): return victim.is_status_active("disarmed"),
			"reset": func(): victim.turn_off_light("disarmed")},
		"player_reveal": {"params": {"duration": 3.0},
			"pre": func(): victim.turn_on_light("stealthed", 10.0),
			"check": func(): return not victim.is_status_active("stealthed"),   # reveal 落地=清隐身（既有实现：群体显形不点灯）
			"reset": func(): pass},
		"player_silence": {"params": {"duration": 2.0},
			"check": func(): return victim.is_status_active("silenced"), "reset": func(): victim.turn_off_light("silenced")},
	}
	for tag_id in matrix:
		var spec: Dictionary = matrix[tag_id]
		if spec.has("pre"):
			spec["pre"].call()
		handler._do_apply_tag(str(tag_id), spec["params"], cid)
		await process_frame
		var consumed_n: int = handler.consume_hit_tags(cid, victim)
		await process_frame
		var ok: bool = bool(spec["check"].call())
		_assert("矩阵 %s: 消费=%d 落地断言" % [tag_id, consumed_n], consumed_n == 1 and ok)
		if spec.has("reset"):
			spec["reset"].call()
		# 复位生命（vulnerable 对比伤害可能致死，防污染下一条）
		victim.is_defeated = false
		victim.stamina = victim.max_stamina
		await process_frame

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 命中传递链路打通！（印记技能：球命中敌人 → 敌人身上叠加印记）")
	quit(1 if _fail > 0 else 0)

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
