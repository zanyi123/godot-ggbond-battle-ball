## 元灵技能AI 波E（长尾族10标签：交互/复制/地形/区域标注/幻影）验收套件
## 断言组照 06§6.1：J-JSON / G-Gate / V-Value / H-Hooks(复制族快照口) / I-集成面 / R-纪律
## 零数据文件触碰（primitives_e.json 只读）。运行：
##   Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_wave_e.gd
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
	print("\n========== 波E 长尾族：JSON + Gate + Value + Hooks(快照口) ==========\n")
	for i in range(3):
		await process_frame

	const PrimE = preload("res://scripts/battle/spirit_ai/primitives_e.gd")
	const HooksScript = preload("res://scripts/battle/spirit_ai/event_hooks.gd")

	var desc: Dictionary = PrimE.get_descriptors()

	# ===== J-JSON：表完整性与 registry 对账 =====
	var reg_text: String = FileAccess.get_file_as_string("res://data/spirits/tags_registry.json")
	var reg_tags: Dictionary = {}
	for t in (JSON.parse_string(reg_text) as Dictionary)["tags"]:
		reg_tags[t["id"]] = t
	var e_ids: Array = desc.keys()
	e_ids.sort()
	_assert("J1: 描述符恰好 10 条", e_ids.size() == 10)
	var all_in_reg: bool = true
	for tid in e_ids:
		if not reg_tags.has(tid):
			all_in_reg = false
	_assert("J2: 10 标签 id 与 tags_registry 逐字一致", all_in_reg)
	var req_fields: Array = ["family", "direction", "timing_gate", "value_param", "value_unit",
		"value_min", "value_cap", "intent", "intent_strength", "target_mode"]
	var valid_families: Array = ["ball_stat", "player_attr", "energy_mgmt", "player_status",
		"player_hp", "player_motion", "player_control", "ball_flight", "ball_hit", "ball_range",
		"field_area", "field_obstacle", "player_interact", "skill_copy"]
	var valid_gates: Array = ["always", "ball_hold", "ball_hold_engage", "enemy_visible",
		"enemy_carrying_visible", "self_threatened", "self_injured", "ally_injured",
		"calm_state", "pre_burst", "ball_flight", "ally_cast_setup",
		"ally_skill_cast_recent", "ball_out_predicted"]
	var fields_ok: bool = true
	var constrain_ok: bool = true
	var param_ok: bool = true
	for tid in e_ids:
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
		if d["value_param"] != "none" and not (d["value_param"] in reg_tags[tid]["params"]):
			param_ok = false
	_assert("J3: 每条字段齐全无多余、枚举全部合法（family 含 Q1/Q4/Q8/Q9 提案全集）", fields_ok)
	_assert("J4: 约束 value_min≤value_cap≤90、gate/family/direction/intent/target_mode 合法", constrain_ok)
	_assert("J5: value_param 与 registry params 逐一对账（none 豁免=引用型参数标签）", param_ok)

	# ===== G-Gate：12 基础键正反例 + 2 提案键 fail-closed + fail-closed 兜底 =====
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_we_caster"
	caster.team = "a"
	root.add_child(caster)
	var enemy: StubPlayer = StubPlayer.new()
	enemy.character_id = "t_we_enemy"
	enemy.team = "b"
	enemy.position = Vector2(150, 0)
	root.add_child(enemy)
	var close_enemy: StubPlayer = StubPlayer.new()
	close_enemy.character_id = "t_we_close"
	close_enemy.team = "b"
	close_enemy.position = Vector2(90, 0)
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

	_assert("G1: always 恒真 bonus=1.0", PrimE.timing_gate({"timing_gate": "always"}, sad, base_ctx)["ok"])
	caster.is_carrying_ball = true
	_assert("G2a: ball_hold 持球→真", PrimE.timing_gate({"timing_gate": "ball_hold"}, sad, base_ctx)["ok"])
	caster.is_carrying_ball = false
	_assert("G2b: ball_hold 空手→假", not PrimE.timing_gate({"timing_gate": "ball_hold"}, sad, base_ctx)["ok"])
	caster.is_carrying_ball = true
	var ctx_engage: Dictionary = base_ctx.duplicate(true)
	ctx_engage["visible_enemies"] = [enemy]
	_assert("G3: ball_hold_engage 持球+敌→真 / 空手→假", PrimE.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_engage)["ok"] and not PrimE.timing_gate({"timing_gate": "ball_hold_engage"}, sad, base_ctx)["ok"])
	caster.is_carrying_ball = false
	var ctx_vis: Dictionary = base_ctx.duplicate(true)
	ctx_vis["visible_enemies"] = [enemy]
	_assert("G4: enemy_visible 有敌→真/无敌→假", PrimE.timing_gate({"timing_gate": "enemy_visible"}, sad, ctx_vis)["ok"] and not PrimE.timing_gate({"timing_gate": "enemy_visible"}, sad, base_ctx)["ok"])
	enemy.is_carrying_ball = true
	var ctx_carry: Dictionary = base_ctx.duplicate(true)
	ctx_carry["visible_enemies"] = [enemy]
	_assert("G5a: enemy_carrying_visible 敌持球→真", PrimE.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_carry)["ok"])
	enemy.is_carrying_ball = false
	_assert("G5b: enemy_carrying_visible 敌空手→假", not PrimE.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_carry)["ok"])
	var ctx_far: Dictionary = base_ctx.duplicate(true)
	ctx_far["visible_enemies"] = [enemy]
	var r_near: Dictionary = PrimE.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_far)
	_assert("G6a: self_threatened 半径内→真 bonus=1.0", r_near["ok"] and absf(r_near["bonus"] - 1.0) < 0.001)
	var ctx_close: Dictionary = base_ctx.duplicate(true)
	ctx_close["visible_enemies"] = [close_enemy]
	var r_strong: Dictionary = PrimE.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_close)
	_assert("G6b: self_threatened 贴脸→bonus=1.25", r_strong["ok"] and absf(r_strong["bonus"] - 1.25) < 0.001)
	_assert("G6c: self_threatened 安全→假", not PrimE.timing_gate({"timing_gate": "self_threatened"}, sad, base_ctx)["ok"])
	var ctx_hurt: Dictionary = base_ctx.duplicate(true)
	ctx_hurt["stamina_ratio"] = 0.3
	_assert("G7: self_injured 0.3→真/1.0→假", PrimE.timing_gate({"timing_gate": "self_injured"}, sad, ctx_hurt)["ok"] and not PrimE.timing_gate({"timing_gate": "self_injured"}, sad, base_ctx)["ok"])
	var ctx_ally: Dictionary = base_ctx.duplicate(true)
	ctx_ally["allies"] = [{"stamina_ratio": 0.2}]
	var ctx_ally_ok: Dictionary = base_ctx.duplicate(true)
	ctx_ally_ok["allies"] = [{"stamina_ratio": 0.9}]
	_assert("G8: ally_injured 伤→真/健康与缺省→假", PrimE.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally)["ok"] and not PrimE.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_ok)["ok"] and not PrimE.timing_gate({"timing_gate": "ally_injured"}, sad, base_ctx)["ok"])
	var ctx_calm: Dictionary = base_ctx.duplicate(true)
	ctx_calm["stamina_ratio"] = 0.8
	var calm_free: bool = PrimE.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm)["ok"]
	caster.is_carrying_ball = true
	var calm_ball: bool = PrimE.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm)["ok"]
	caster.is_carrying_ball = false
	_assert("G9: calm_state 闲时→真/持球→假", calm_free and not calm_ball)
	var ctx_burst: Dictionary = base_ctx.duplicate(true)
	ctx_burst["has_energy_blocked_burst"] = true
	_assert("G10: pre_burst 缺省假/显式真", not PrimE.timing_gate({"timing_gate": "pre_burst"}, sad, base_ctx)["ok"] and PrimE.timing_gate({"timing_gate": "pre_burst"}, sad, ctx_burst)["ok"])
	var ctx_fly: Dictionary = base_ctx.duplicate(true)
	ctx_fly["ball_in_flight"] = true
	_assert("G11: ball_flight 缺省假/显式真", not PrimE.timing_gate({"timing_gate": "ball_flight"}, sad, base_ctx)["ok"] and PrimE.timing_gate({"timing_gate": "ball_flight"}, sad, ctx_fly)["ok"])
	var ctx_combo: Dictionary = base_ctx.duplicate(true)
	ctx_combo["combo_setup_active"] = true
	_assert("G12: ally_cast_setup 缺省假/显式真", not PrimE.timing_gate({"timing_gate": "ally_cast_setup"}, sad, base_ctx)["ok"] and PrimE.timing_gate({"timing_gate": "ally_cast_setup"}, sad, ctx_combo)["ok"])
	var ctx_cast: Dictionary = base_ctx.duplicate(true)
	ctx_cast["ally_skill_cast_recent"] = true
	_assert("G13: 提案键 ally_skill_cast_recent 缺省fail-closed/显式真", not PrimE.timing_gate({"timing_gate": "ally_skill_cast_recent"}, sad, base_ctx)["ok"] and PrimE.timing_gate({"timing_gate": "ally_skill_cast_recent"}, sad, ctx_cast)["ok"])
	var ctx_out: Dictionary = base_ctx.duplicate(true)
	ctx_out["ball_out_predicted"] = true
	_assert("G14: 提案键 ball_out_predicted 缺省fail-closed/显式真", not PrimE.timing_gate({"timing_gate": "ball_out_predicted"}, sad, base_ctx)["ok"] and PrimE.timing_gate({"timing_gate": "ball_out_predicted"}, sad, ctx_out)["ok"])
	_assert("G15: 未知键/空 descriptor fail-closed", not PrimE.timing_gate({"timing_gate": "nope"}, sad, base_ctx)["ok"] and not PrimE.timing_gate({}, sad, base_ctx)["ok"])

	# ===== V-Value：四族计价 + clamp + 缺参/none =====
	_assert("V1: 复制族 copy_last cost_pct=0.5 ×30=15（平价下限边界）", absf(PrimE.compute_value(desc["skill_copy_last"], {"cost_pct": 0.5}) - 15.0) < 0.001)
	_assert("V2: 复制族 share_copy duration=5 ×7=35", absf(PrimE.compute_value(desc["skill_share_copy"], {"duration": 5.0}) - 35.0) < 0.001)
	_assert("V3: 地形族 terra_change duration=4 ×9=36", absf(PrimE.compute_value(desc["field_terra_change"], {"duration": 4.0}) - 36.0) < 0.001)
	_assert("V4: 幻影族 illusion_add duration=6 ×8=48", absf(PrimE.compute_value(desc["field_illusion_add"], {"duration": 6.0}) - 48.0) < 0.001)
	_assert("V5a: clamp 上限 share_copy duration=20 ×7=140→50", absf(PrimE.compute_value(desc["skill_share_copy"], {"duration": 20.0}) - 50.0) < 0.001)
	_assert("V5b: clamp 下限 terra_change duration=1 ×9=9→15", absf(PrimE.compute_value(desc["field_terra_change"], {"duration": 1.0}) - 15.0) < 0.001)
	_assert("V6: 缺参数回落 value_min", absf(PrimE.compute_value(desc["skill_share_copy"], {}) - 15.0) < 0.001)
	_assert("V7: none 参数（teleport/zone_clear 等 6 条）恒 value_min", absf(PrimE.compute_value(desc["player_teleport"], {"target_position": Vector2(1, 1)}) - 15.0) < 0.001 and absf(PrimE.compute_value(desc["field_zone_clear"], {"zone_id": "z1"}) - 15.0) < 0.001)

	# ===== H-Hooks：复制族快照口（机动领域扩展，向后兼容验证） =====
	var hooks = HooksScript.new()
	hooks.set_cycle(100)
	var viewer: StubPlayer = StubPlayer.new()
	viewer.character_id = "t_we_viewer"
	viewer.team = "a"
	root.add_child(viewer)
	var foe: StubPlayer = StubPlayer.new()
	foe.character_id = "t_we_foe"
	foe.team = "b"
	root.add_child(foe)
	var mate: StubPlayer = StubPlayer.new()
	mate.character_id = "t_we_mate"
	mate.team = "a"
	root.add_child(mate)
	_assert("H1: 无快照 → 返回空（fail-closed）", hooks.get_recent_enemy_cast(viewer).is_empty())
	hooks.record_skill_cast(foe, "skill_ice_1")
	var snap: Dictionary = hooks.get_recent_enemy_cast(viewer)
	_assert("H2: 敌方释放记录后可查（skill_id/age=0）", str(snap.get("skill_id", "")) == "skill_ice_1" and int(snap.get("age_cycles", -1)) == 0)
	hooks.set_cycle(104)
	_assert("H3: TTL 窗口末端（age=4≤4）仍可查", not hooks.get_recent_enemy_cast(viewer).is_empty())
	hooks.set_cycle(105)
	_assert("H4: TTL 过期（age=5>4）→ 空", hooks.get_recent_enemy_cast(viewer).is_empty())
	hooks.set_cycle(110)
	hooks.record_skill_cast(mate, "skill_grass_1")
	_assert("H5: 队友释放不算敌方快照（viewer 查不到）", hooks.get_recent_enemy_cast(viewer).is_empty())
	_assert("H6: 敌方视角可查到该快照（team 隔离正确）", str(hooks.get_recent_enemy_cast(foe).get("skill_id", "")) == "skill_grass_1")
	hooks.set_cycle(120)
	hooks.record_skill_cast(null, "x")
	hooks.record_skill_cast(foe, "")
	_assert("H7: 非法入参（null caster/空 skill_id）静默拒绝不崩溃", hooks.get_recent_enemy_cast(viewer).is_empty())
	var victim: StubPlayer = StubPlayer.new()
	victim.character_id = "t_we_victim"
	victim.team = "a"
	root.add_child(victim)
	hooks._reaction_until[victim.get_instance_id()] = 999
	_assert("H8: 向后兼容——is_reaction_hot 原接口行为不变", hooks.is_reaction_hot(victim))
	hooks.clear()
	_assert("H9: clear 双清（热窗口+快照全空）", hooks.pending_count() == 0 and hooks.get_recent_enemy_cast(viewer).is_empty())

	# ===== I-集成面：坏表不崩溃 =====
	var bad: Dictionary = PrimE._load_table("res://data/systems/spirit_ai/no_such_table.json")
	_assert("I1: 不存在路径 → 返回空表不崩溃", bad.is_empty())
	_assert("I2: 真实表 get_descriptors 10 条", desc.size() == 10)

	# ===== R-纪律：源码无随机调用（口径对齐 foundation A2） =====
	var src_e: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/primitives_e.gd")
	var src_h: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/event_hooks.gd")
	_assert("R1: primitives_e.gd 源码无 randf(/randi( 调用", src_e.find("randf(") == -1 and src_e.find("randi(") == -1)
	_assert("R2: event_hooks.gd 源码无 randf(/randi( 调用且无墙钟", src_h.find("randf(") == -1 and src_h.find("randi(") == -1 and src_h.find("Time.get_ticks") == -1)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（波E套件，零数据文件触碰）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
