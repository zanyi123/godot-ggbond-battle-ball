## 元灵技能AI 波B（生存/控制族27标签+事件钩子层）验收套件
## 断言组照 06§6.1：J-JSON / G-Gate / V-Value / H-Hooks(波B特有) / I-集成面 / R-纪律
## 零数据文件触碰（primitives_b.json 只读）。运行：
##   Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_wave_b.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_carrying_ball: bool = false
	var is_defeated: bool = false
	var stamina: float = 100.0
	var max_stamina: float = 100.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波B 生存/控制族：JSON + Gate + Value + Hooks ==========\n")
	for i in range(3):
		await process_frame

	const PrimB = preload("res://scripts/battle/spirit_ai/primitives_b.gd")
	const HooksScript = preload("res://scripts/battle/spirit_ai/event_hooks.gd")
	const BusScript = preload("res://scripts/systems/event_bus/event_bus.gd")

	var desc: Dictionary = PrimB.get_descriptors()

	# ===== J-JSON：表完整性与 registry 对账 =====
	var reg_text: String = FileAccess.get_file_as_string("res://data/spirits/tags_registry.json")
	var reg_tags: Dictionary = {}
	for t in (JSON.parse_string(reg_text) as Dictionary)["tags"]:
		reg_tags[t["id"]] = t
	var wave_b_ids: Array = desc.keys()
	wave_b_ids.sort()
	_assert("J1: 描述符恰好 27 条", wave_b_ids.size() == 27)
	var all_in_reg: bool = true
	for tid in wave_b_ids:
		if not reg_tags.has(tid):
			all_in_reg = false
	_assert("J2: 27 标签 id 与 tags_registry 逐字一致", all_in_reg)
	var req_fields: Array = ["family", "direction", "timing_gate", "value_param", "value_unit",
		"value_min", "value_cap", "intent", "intent_strength", "target_mode"]
	var valid_families: Array = ["ball_stat", "player_attr", "energy_mgmt",
		"player_status", "player_hp", "player_motion", "player_control"]
	var valid_gates: Array = ["always", "ball_hold", "ball_hold_engage", "enemy_visible",
		"enemy_carrying_visible", "self_threatened", "self_injured", "ally_injured",
		"calm_state", "pre_burst", "ball_flight", "ally_cast_setup"]
	var fields_ok: bool = true
	var constrain_ok: bool = true
	var param_ok: bool = true
	for tid in wave_b_ids:
		var d: Dictionary = desc[tid]
		for f in req_fields:
			if not d.has(f):
				fields_ok = false
		if d["value_min"] > d["value_cap"] or d["value_cap"] > 90.0:
			constrain_ok = false
		if not (d["family"] in valid_families) or not (d["timing_gate"] in valid_gates):
			constrain_ok = false
		if not (d["direction"] in ["self", "enemy"]) or not (d["intent"] in ["attack", "defense", "support", "control"]):
			constrain_ok = false
		if not (d["target_mode"] in ["ball", "self", "enemy_visible", "ally_support", "none"]):
			constrain_ok = false
		# value_param 与 registry params 对账（"none" 豁免 = 无数值参数标签的合规用法）
		if d["value_param"] != "none" and not (d["value_param"] in reg_tags[tid]["params"]):
			param_ok = false
	_assert("J3: 每条字段齐全无多余、枚举全部合法", fields_ok)
	_assert("J4: 约束 value_min≤value_cap≤90、gate/family/direction/intent/target_mode 合法", constrain_ok)
	_assert("J5: value_param 与 registry params 逐一对账（none 豁免）", param_ok)

	# ===== G-Gate：12 键正反例 + fail-closed + 两档 bonus + reaction_hot =====
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_wb_caster"
	caster.team = "a"
	root.add_child(caster)
	var enemy: StubPlayer = StubPlayer.new()
	enemy.character_id = "t_wb_enemy"
	enemy.team = "b"
	enemy.position = Vector2(150, 0)  # 距离 150：threat 半径内、强触发外
	root.add_child(enemy)
	var close_enemy: StubPlayer = StubPlayer.new()
	close_enemy.character_id = "t_wb_close"
	close_enemy.team = "b"
	close_enemy.position = Vector2(90, 0)  # 距离 90：强触发内
	root.add_child(close_enemy)
	var sad: Dictionary = {}
	var base_ctx: Dictionary = {
		"player": caster,
		"fov_ap": {},
		"visible_enemies": [],
		"stamina_ratio": 1.0,
		"energy_ratio": 1.0,
		"has_energy_blocked_burst": false,
		"threat_radius": 200.0,
	}

	var g_always: Dictionary = PrimB.timing_gate({"timing_gate": "always"}, sad, base_ctx)
	_assert("G1: always 恒真 bonus=1.0", g_always["ok"] and absf(g_always["bonus"] - 1.0) < 0.001)

	caster.is_carrying_ball = true
	_assert("G2a: ball_hold 持球→真", PrimB.timing_gate({"timing_gate": "ball_hold"}, sad, base_ctx)["ok"])
	caster.is_carrying_ball = false
	_assert("G2b: ball_hold 空手→假", not PrimB.timing_gate({"timing_gate": "ball_hold"}, sad, base_ctx)["ok"])

	caster.is_carrying_ball = true
	var ctx_engage: Dictionary = base_ctx.duplicate(true)
	ctx_engage["visible_enemies"] = [enemy]
	_assert("G3a: ball_hold_engage 持球+视野内敌→真", PrimB.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_engage)["ok"])
	caster.is_carrying_ball = false
	_assert("G3b: ball_hold_engage 空手→假（持球条件不满足）", not PrimB.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_engage)["ok"])

	var ctx_vis: Dictionary = base_ctx.duplicate(true)
	ctx_vis["visible_enemies"] = [enemy]
	_assert("G4a: enemy_visible 有敌→真", PrimB.timing_gate({"timing_gate": "enemy_visible"}, sad, ctx_vis)["ok"])
	_assert("G4b: enemy_visible 无敌→假", not PrimB.timing_gate({"timing_gate": "enemy_visible"}, sad, base_ctx)["ok"])

	var ctx_carry: Dictionary = base_ctx.duplicate(true)
	enemy.is_carrying_ball = true
	ctx_carry["visible_enemies"] = [enemy]
	_assert("G5a: enemy_carrying_visible 敌持球→真", PrimB.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_carry)["ok"])
	enemy.is_carrying_ball = false
	_assert("G5b: enemy_carrying_visible 敌空手→假", not PrimB.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_carry)["ok"])

	var ctx_far: Dictionary = base_ctx.duplicate(true)
	ctx_far["visible_enemies"] = [enemy]  # 距离 150 < 200 威胁半径
	var r_near: Dictionary = PrimB.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_far)
	_assert("G6a: self_threatened 敌在威胁半径→真 bonus=1.0", r_near["ok"] and absf(r_near["bonus"] - 1.0) < 0.001)
	var ctx_close: Dictionary = base_ctx.duplicate(true)
	ctx_close["visible_enemies"] = [close_enemy]  # 距离 90 < 100 强触发
	var r_strong: Dictionary = PrimB.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_close)
	_assert("G6b: self_threatened 敌贴脸→强触发 bonus=1.25", r_strong["ok"] and absf(r_strong["bonus"] - 1.25) < 0.001)
	_assert("G6c: self_threatened 无敌+满体力→假", not PrimB.timing_gate({"timing_gate": "self_threatened"}, sad, base_ctx)["ok"])
	var ctx_tired: Dictionary = base_ctx.duplicate(true)
	ctx_tired["stamina_ratio"] = 0.3
	_assert("G6d: self_threatened 体力<0.4 视同受威胁→真", PrimB.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_tired)["ok"])

	var ctx_hurt: Dictionary = base_ctx.duplicate(true)
	ctx_hurt["stamina_ratio"] = 0.3
	_assert("G7a: self_injured <0.35→真", PrimB.timing_gate({"timing_gate": "self_injured"}, sad, ctx_hurt)["ok"])
	_assert("G7b: self_injured 0.5→假", not PrimB.timing_gate({"timing_gate": "self_injured"}, sad, base_ctx)["ok"])

	var ctx_ally: Dictionary = base_ctx.duplicate(true)
	ctx_ally["allies"] = [{"stamina_ratio": 0.2}]
	_assert("G8a: ally_injured 队友<0.35→真", PrimB.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally)["ok"])
	var ctx_ally_ok: Dictionary = base_ctx.duplicate(true)
	ctx_ally_ok["allies"] = [{"stamina_ratio": 0.9}]
	_assert("G8b: ally_injured 队友健康→假", not PrimB.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_ok)["ok"])
	_assert("G8c: ally_injured 缺 allies 字段→fail-closed 假", not PrimB.timing_gate({"timing_gate": "ally_injured"}, sad, base_ctx)["ok"])

	var ctx_calm: Dictionary = base_ctx.duplicate(true)
	ctx_calm["stamina_ratio"] = 0.8
	_assert("G9a: calm_state 无球无敌健康→真", PrimB.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm)["ok"])
	var ctx_calm_hot: Dictionary = ctx_calm.duplicate(true)
	ctx_calm_hot["reaction_hot"] = true
	_assert("G9b: calm_state 反应热窗口→假（热窗口压过闲时）", not PrimB.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm_hot)["ok"])
	var ctx_calm_ball: Dictionary = ctx_calm.duplicate(true)
	caster.is_carrying_ball = true
	_assert("G9c: calm_state 持球→假", not PrimB.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm_ball)["ok"])
	caster.is_carrying_ball = false

	var ctx_burst: Dictionary = base_ctx.duplicate(true)
	ctx_burst["has_energy_blocked_burst"] = true
	_assert("G10a: pre_burst 资源被卡→真", PrimB.timing_gate({"timing_gate": "pre_burst"}, sad, ctx_burst)["ok"])
	_assert("G10b: pre_burst 缺省→假", not PrimB.timing_gate({"timing_gate": "pre_burst"}, sad, base_ctx)["ok"])

	var ctx_fly: Dictionary = base_ctx.duplicate(true)
	ctx_fly["ball_in_flight"] = true
	_assert("G11: ball_flight 缺省fail-closed/显式true→真", not PrimB.timing_gate({"timing_gate": "ball_flight"}, sad, base_ctx)["ok"] and PrimB.timing_gate({"timing_gate": "ball_flight"}, sad, ctx_fly)["ok"])

	var ctx_combo: Dictionary = base_ctx.duplicate(true)
	ctx_combo["combo_setup_active"] = true
	_assert("G12: ally_cast_setup 缺省fail-closed/显式true→真", not PrimB.timing_gate({"timing_gate": "ally_cast_setup"}, sad, base_ctx)["ok"] and PrimB.timing_gate({"timing_gate": "ally_cast_setup"}, sad, ctx_combo)["ok"])

	_assert("G13: 未知 gate 键 fail-closed", not PrimB.timing_gate({"timing_gate": "no_such_gate"}, sad, base_ctx)["ok"])
	_assert("G14: 空 descriptor fail-closed", not PrimB.timing_gate({}, sad, base_ctx)["ok"])

	# 波B增强：reaction_hot（受击反应热窗口）→ self_threatened 通道打开且强触发档
	var ctx_hot: Dictionary = base_ctx.duplicate(true)
	ctx_hot["reaction_hot"] = true
	var r_hot: Dictionary = PrimB.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_hot)
	_assert("G15: reaction_hot 无敌视野也开 self_threatened 且 bonus=1.25", r_hot["ok"] and absf(r_hot["bonus"] - 1.25) < 0.001)

	# ===== V-Value：四族计价 + clamp 边界 + 缺参数/none 回落 =====
	_assert("V1: 状态族 invincible duration=3 ×15=45", absf(PrimB.compute_value(desc["player_invincible"], {"duration": 3.0}) - 45.0) < 0.001)
	_assert("V2: 控制族 stun duration=2 ×14=28", absf(PrimB.compute_value(desc["player_stun"], {"duration": 2.0}) - 28.0) < 0.001)
	_assert("V3: 运动族 move_slow multiplier=1.5 ×10=15（下限边界）", absf(PrimB.compute_value(desc["player_move_slow"], {"multiplier": 1.5}) - 15.0) < 0.001)
	_assert("V4: 体力族 hp_heal_pct value=20 ×2=40", absf(PrimB.compute_value(desc["player_hp_heal_pct"], {"value": 20.0}) - 40.0) < 0.001)
	_assert("V5a: clamp 下限触发 regen value=1 ×6=6→15", absf(PrimB.compute_value(desc["player_hp_regen"], {"value": 1.0}) - 15.0) < 0.001)
	_assert("V5b: clamp 上限触发 charge_stock charges=10 ×12=120→60", absf(PrimB.compute_value(desc["player_charge_stock"], {"charges": 10.0}) - 60.0) < 0.001)
	_assert("V6: 缺参数回落 value_min", absf(PrimB.compute_value(desc["player_invincible"], {}) - 15.0) < 0.001)
	_assert("V7: none 参数（on_hit_expire）恒 value_min", absf(PrimB.compute_value(desc["player_on_hit_expire"], {"statuses": ["rooted"]}) - 15.0) < 0.001)

	# ===== H-Hooks：事件钩子层（受击瞬间反应） =====
	var hooks = HooksScript.new()
	var bus: Node = BusScript.new()
	root.add_child(bus)
	hooks.attach(bus)
	hooks.set_cycle(5)
	var victim: StubPlayer = StubPlayer.new()
	victim.character_id = "t_wb_victim"
	victim.team = "a"
	root.add_child(victim)
	_assert("H1: attach 后未受击→不热", not hooks.is_reaction_hot(victim))
	bus.emit_event(BusScript.GameEvent.HIT_TAKEN, {"attacker": enemy, "defender": victim, "damage": 10.0})
	_assert("H2: HIT_TAKEN 后→热（受击瞬间反应）", hooks.is_reaction_hot(victim))
	hooks.set_cycle(7)  # 5+2 窗口末端仍热
	_assert("H3: 窗口末端（cycle=受击+2）仍热", hooks.is_reaction_hot(victim))
	hooks.set_cycle(8)  # 过期
	_assert("H4: TTL 过期（cycle>受击+2）→冷（惰性清理）", not hooks.is_reaction_hot(victim) and hooks.pending_count() == 0)
	hooks.set_cycle(10)
	bus.emit_event(BusScript.GameEvent.STATUS_APPLIED, {"target": victim, "status_id": "rooted", "duration": 2.0, "source": enemy})
	_assert("H5: STATUS_APPLIED（被控）同样登记热窗口", hooks.is_reaction_hot(victim))
	hooks.detach()
	hooks.set_cycle(20)
	bus.emit_event(BusScript.GameEvent.HIT_TAKEN, {"defender": victim})
	_assert("H6: detach 后事件不再登记", not hooks.is_reaction_hot(victim))
	hooks.attach(bus)
	hooks.set_cycle(30)
	bus.emit_event(BusScript.GameEvent.HIT_TAKEN, {"defender": victim})
	_assert("H7: 重复 attach 幂等且恢复登记", hooks.is_reaction_hot(victim))
	hooks.clear()
	_assert("H8: clear 清空全部热窗口", hooks.pending_count() == 0 and not hooks.is_reaction_hot(victim))

	# ===== I-集成面：坏表不崩溃 =====
	var bad: Dictionary = PrimB._load_table("res://data/systems/spirit_ai/no_such_table.json")
	_assert("I1: 不存在路径 → 返回空表不崩溃", bad.is_empty())
	_assert("I2: 真实表 get_descriptors 27 条", desc.size() == 27)

	# ===== R-纪律：源码无随机调用（口径对齐 foundation A2：查调用形式 randf(/randi(，注释提及不算） =====
	var src_b: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/primitives_b.gd")
	var src_h: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/event_hooks.gd")
	_assert("R1: primitives_b.gd 源码无 randf(/randi( 调用", src_b.find("randf(") == -1 and src_b.find("randi(") == -1)
	_assert("R2: event_hooks.gd 源码无 randf(/randi( 调用且无墙钟", src_h.find("randf(") == -1 and src_h.find("randi(") == -1 and src_h.find("Time.get_ticks") == -1)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（波B套件，零数据文件触碰）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
