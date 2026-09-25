## 波D布场窗口验收：场地族（区域+障碍）10标签位置原语
## 断言组：J-JSON契约 / G-Gate闸门 / V-Value计价 / P-Position选位 / I-集成面 / R-纪律
## 契约：元灵技能AI规划/06_原语接口规约.md（波D扩展看板Q4/Q5）。零热文件触碰。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_wave_d.gd
extends SceneTree

const D_TABLE_PATH := "res://data/systems/spirit_ai/primitives_d.json"
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const D_SOURCE_PATH := "res://scripts/battle/spirit_ai/primitives_d.gd"

## 波D 10标签全名单（07§③）
const WAVE_D_TAGS: Array[String] = [
	"field_vision_block", "field_zone_boost", "field_zone_slow",
	"field_zone_danger", "field_zone_safe", "field_zone_heal",
	"field_obs_add", "field_obs_clear", "player_shield_obstacle", "field_drain_wall",
]

## 06§2.1 冻结字段 + 波D扩展字段 position_intent（Q4③）
const REQUIRED_FIELDS: Array[String] = [
	"family", "direction", "timing_gate", "value_param", "value_unit",
	"value_min", "value_cap", "intent", "intent_strength", "target_mode",
	"position_intent", "notes",
]

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_carrying_ball: bool = false
	var stamina: float = 100.0
	var max_stamina: float = 100.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波D布场窗口：场地族10标签位置原语 ==========\n")
	for i in range(3):
		await process_frame

	var prim: GDScript = load("res://scripts/battle/spirit_ai/primitives_d.gd")

	# ===== J-JSON：契约与 registry 一致性 =====
	var table_text := FileAccess.get_file_as_string(D_TABLE_PATH)
	var table: Variant = JSON.parse_string(table_text)
	_assert("J1: 原语表 JSON 可解析", typeof(table) == TYPE_DICTIONARY)
	if typeof(table) != TYPE_DICTIONARY:
		_finish()
		return
	_assert("J2: wave=D / schema_version=3（Q4扩展版）", str(table.get("wave", "")) == "D" and int(table.get("schema_version", 0)) == 3)
	var descriptors: Dictionary = table.get("descriptors", {})
	_assert("J3: 描述符恰为10个", descriptors.size() == 10)

	var registry_text := FileAccess.get_file_as_string(REGISTRY_PATH)
	var registry: Variant = JSON.parse_string(registry_text)
	_assert("J4: tags_registry.json 可解析", typeof(registry) == TYPE_DICTIONARY)
	var reg_by_id: Dictionary = {}
	if typeof(registry) == TYPE_DICTIONARY:
		var reg_tags: Variant = registry.get("tags", [])
		if typeof(reg_tags) == TYPE_ARRAY:
			for t in reg_tags as Array:
				if typeof(t) == TYPE_DICTIONARY:
					reg_by_id[str(t.get("id", ""))] = t

	var ids_ok := true
	var fields_ok := true
	var enum_ok := true
	var param_ok := true
	var range_ok := true
	for tag_id in WAVE_D_TAGS:
		var d: Variant = descriptors.get(tag_id)
		if typeof(d) != TYPE_DICTIONARY:
			ids_ok = false
			print("    [缺标签] " + tag_id)
			continue
		var desc: Dictionary = d
		# id 与 registry 逐字一致
		if not reg_by_id.has(tag_id):
			ids_ok = false
			print("    [registry无此id] " + tag_id)
		# 字段齐全无多余（冻结字段 + Q4扩展 position_intent）
		var keys := desc.keys()
		if keys.size() != REQUIRED_FIELDS.size():
			fields_ok = false
			print("    [字段数不符] %s: %d" % [tag_id, keys.size()])
		for f in REQUIRED_FIELDS:
			if not desc.has(f):
				fields_ok = false
				print("    [缺字段] %s.%s" % [tag_id, f])
		# 枚举合法
		if str(desc.get("family", "")) not in ["field_area", "field_obstacle"]:
			enum_ok = false
			print("    [family非法] " + tag_id)
		if str(desc.get("direction", "")) not in ["self", "enemy"]:
			enum_ok = false
			print("    [direction非法] " + tag_id)
		if str(desc.get("timing_gate", "")) not in prim.GATE_KEYS:
			enum_ok = false
			print("    [gate非法] " + tag_id)
		if str(desc.get("intent", "")) not in ["attack", "defense", "support", "control"]:
			enum_ok = false
			print("    [intent非法] " + tag_id)
		if str(desc.get("target_mode", "")) != "field_position":
			enum_ok = false
			print("    [target_mode非field_position] " + tag_id)
		if str(desc.get("position_intent", "")) not in prim.POSITION_INTENTS:
			enum_ok = false
			print("    [position_intent非法] " + tag_id)
		var strength := float(desc.get("intent_strength", -1.0))
		if strength < 0.0 or strength > 1.0:
			enum_ok = false
			print("    [intent_strength越界] " + tag_id)
		# value_param 以 registry params 数组为准
		var reg_tag: Dictionary = reg_by_id.get(tag_id, {})
		var reg_params: Variant = reg_tag.get("params", [])
		if typeof(reg_params) == TYPE_ARRAY and not (reg_params as Array).has(str(desc.get("value_param", ""))):
			param_ok = false
			print("    [value_param不在registry params] %s: %s" % [tag_id, str(desc.get("value_param", ""))])
		# 数值域
		var v_min := float(desc.get("value_min", 0.0))
		var v_cap := float(desc.get("value_cap", 0.0))
		if v_min > v_cap or v_cap > 90.0:
			range_ok = false
			print("    [数值域非法] %s: min=%.1f cap=%.1f" % [tag_id, v_min, v_cap])
	_assert("J5: 10标签 id 与 registry 逐字一致", ids_ok)
	_assert("J6: 字段齐全无多余（冻结11字段+notes）", fields_ok)
	_assert("J7: 枚举全部合法（family/direction/gate/intent/target_mode/position_intent/强度）", enum_ok)
	_assert("J8: value_param 逐一在 registry params 数组中", param_ok)
	_assert("J9: value_min ≤ value_cap ≤ 90", range_ok)

	# ===== G-Gate：12 键正反例 =====
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_fd_caster"
	caster.team = "a"
	caster.is_carrying_ball = true
	caster.position = Vector2(0, 0)
	root.add_child(caster)
	var carrier: StubPlayer = StubPlayer.new()
	carrier.character_id = "t_fd_carrier"
	carrier.team = "b"
	carrier.is_carrying_ball = true
	carrier.position = Vector2(300, 0)
	root.add_child(carrier)
	var weak: StubPlayer = StubPlayer.new()
	weak.character_id = "t_fd_weak"
	weak.team = "b"
	weak.is_carrying_ball = false
	weak.stamina = 25.0
	weak.position = Vector2(400, 50)
	root.add_child(weak)
	var far: StubPlayer = StubPlayer.new()
	far.character_id = "t_fd_far"
	far.team = "b"
	far.is_carrying_ball = false
	far.position = Vector2(1000, 0)
	root.add_child(far)

	var ctx_full: Dictionary = {
		"player": caster,
		"fov_ap": {},
		"visible_enemies": [carrier, weak],
		"stamina_ratio": 1.0,
		"energy_ratio": 0.5,
		"threat_radius": 200.0,
		"ball_position": Vector2(-200, 0),
		"own_goal": Vector2(-500, 0),
		"enemy_goal": Vector2(500, 0),
	}
	var sad: Dictionary = {"player": caster}

	var g_always: Dictionary = prim.timing_gate({"timing_gate": "always"}, sad, {})
	_assert("G1a: always 恒真 bonus=1.0（零ctx）", bool(g_always.get("ok")) and float(g_always.get("bonus")) == 1.0)
	_assert("G1b: ball_hold 持球→过", bool(prim.timing_gate({"timing_gate": "ball_hold"}, sad, ctx_full).get("ok")))
	var ctx_nocarry: Dictionary = ctx_full.duplicate(true)
	caster.is_carrying_ball = false
	_assert("G1c: ball_hold 无球→不过", not bool(prim.timing_gate({"timing_gate": "ball_hold"}, sad, ctx_nocarry).get("ok")))
	caster.is_carrying_ball = true
	_assert("G1d: ball_hold_engage 持球+视野内敌→过", bool(prim.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_full).get("ok")))
	var ctx_noenemy: Dictionary = ctx_full.duplicate(true)
	ctx_noenemy["visible_enemies"] = []
	_assert("G1e: ball_hold_engage 持球无敌→不过", not bool(prim.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_noenemy).get("ok")))
	_assert("G2a: enemy_visible 有敌→过", bool(prim.timing_gate({"timing_gate": "enemy_visible"}, sad, ctx_full).get("ok")))
	_assert("G2b: enemy_visible 无敌→不过", not bool(prim.timing_gate({"timing_gate": "enemy_visible"}, sad, ctx_noenemy).get("ok")))
	_assert("G2c: enemy_carrying_visible 视野内持球敌→过", bool(prim.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_full).get("ok")))
	var ctx_nocarrier: Dictionary = ctx_full.duplicate(true)
	ctx_nocarrier["visible_enemies"] = [weak, far]
	_assert("G2d: enemy_carrying_visible 无持球敌→不过", not bool(prim.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_nocarrier).get("ok")))
	var ctx_mgr_flag: Dictionary = ctx_noenemy.duplicate(true)
	ctx_mgr_flag["enemy_carrier_visible"] = true
	_assert("G2e: enemy_carrying_visible 尊重 manager 单口键", bool(prim.timing_gate({"timing_gate": "enemy_carrying_visible"}, sad, ctx_mgr_flag).get("ok")))

	var ctx_far: Dictionary = ctx_full.duplicate(true)
	ctx_far["visible_enemies"] = [far]
	var g_far: Dictionary = prim.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_far)
	_assert("G3a: self_threatened 敌在威胁半径外且体力足→不过", not bool(g_far.get("ok")))
	var ctx_hurt: Dictionary = ctx_far.duplicate(true)
	ctx_hurt["stamina_ratio"] = 0.3
	_assert("G3b: self_threatened 体力比<0.4→过（无敌亦触发）", bool(prim.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_hurt).get("ok")))
	var ctx_near: Dictionary = ctx_full.duplicate(true)
	ctx_near["visible_enemies"] = [carrier]
	carrier.position = Vector2(150, 0)
	var g_near: Dictionary = prim.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_near)
	_assert("G3c: self_threatened 敌距150<200→过 且 bonus=1.0", bool(g_near.get("ok")) and float(g_near.get("bonus")) == 1.0)
	var ctx_grave := ctx_near.duplicate(true)
	carrier.position = Vector2(80, 0)
	var g_grave: Dictionary = prim.timing_gate({"timing_gate": "self_threatened"}, sad, ctx_grave)
	_assert("G3d: self_threatened 敌距80<100 强触发 bonus=1.25（两档禁更细）", bool(g_grave.get("ok")) and float(g_grave.get("bonus")) == 1.25)
	carrier.position = Vector2(300, 0)
	_assert("G4a: self_injured 0.3→过", bool(prim.timing_gate({"timing_gate": "self_injured"}, sad, ctx_hurt).get("ok")))
	_assert("G4b: self_injured 1.0→不过", not bool(prim.timing_gate({"timing_gate": "self_injured"}, sad, ctx_full).get("ok")))
	var ctx_ally_bad: Dictionary = {"player": caster, "ally_stamina_ratios": [0.9, 0.2]}
	var ctx_ally_ok: Dictionary = {"player": caster, "ally_stamina_ratios": [0.9, 0.8]}
	_assert("G5a: ally_injured 队友<0.35→过", bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_bad).get("ok")))
	_assert("G5b: ally_injured 全健康→不过", not bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_ok).get("ok")))
	_assert("G5c: ally_injured 缺键 fail-closed", not bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, {}).get("ok")))
	var ctx_calm: Dictionary = ctx_noenemy.duplicate(true)
	ctx_calm["stamina_ratio"] = 0.8
	caster.is_carrying_ball = false
	var g_calm: Dictionary = prim.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm)
	_assert("G6a: calm_state 无球+无敌+体力>0.5→过", bool(g_calm.get("ok")))
	caster.is_carrying_ball = true
	_assert("G6b: calm_state 持球→不过", not bool(prim.timing_gate({"timing_gate": "calm_state"}, sad, ctx_calm).get("ok")))
	_assert("G6c: calm_state 视野内有敌→不过", not bool(prim.timing_gate({"timing_gate": "calm_state"}, sad, ctx_full).get("ok")))
	_assert("G7a: pre_burst 采纳 manager 判定键", bool(prim.timing_gate({"timing_gate": "pre_burst"}, sad, {"has_energy_blocked_burst": true}).get("ok")))
	_assert("G7b: pre_burst 默认不过", not bool(prim.timing_gate({"timing_gate": "pre_burst"}, sad, {}).get("ok")))
	_assert("G7c: ball_flight 预留键可判定", bool(prim.timing_gate({"timing_gate": "ball_flight"}, sad, {"ball_in_flight": true}).get("ok")))
	_assert("G7d: ally_cast_setup 预留键可判定", bool(prim.timing_gate({"timing_gate": "ally_cast_setup"}, sad, {"combo_setup_active": true}).get("ok")))
	_assert("G8a: 未知 gate 键 fail-closed", not bool(prim.timing_gate({"timing_gate": "bogus_gate"}, sad, ctx_full).get("ok")))
	_assert("G8b: 空 descriptor fail-closed", not bool(prim.timing_gate({}, sad, ctx_full).get("ok")))
	_assert("G8c: 缺 player ctx 的节点级 gate fail-closed", not bool(prim.timing_gate({"timing_gate": "ball_hold"}, sad, {"visible_enemies": []}).get("ok")))
	_assert("G9: 12 gate 键全量登记", prim.GATE_KEYS.size() == 12)

	# ===== V-Value：计价（含 clamp 与缺参回落） =====
	var desc_boost: Dictionary = descriptors.get("field_zone_boost", {})
	var desc_shield: Dictionary = descriptors.get("player_shield_obstacle", {})
	var desc_danger: Dictionary = descriptors.get("field_zone_danger", {})
	_assert("V1: field_area 族计价（boost 8s×6=48）", absf(prim.compute_value(desc_boost, {"duration": 8.0}) - 48.0) < 0.001)
	_assert("V2: field_obstacle 族计价（shield hp400×0.1=40）", absf(prim.compute_value(desc_shield, {"hp": 400.0}) - 40.0) < 0.001)
	_assert("V3a: clamp 上限（danger 1000×0.6→cap70）", absf(prim.compute_value(desc_danger, {"damage_value": 1000.0}) - 70.0) < 0.001)
	_assert("V3b: clamp 下限（boost 0.5s×6=3→min15）", absf(prim.compute_value(desc_boost, {"duration": 0.5}) - 15.0) < 0.001)
	_assert("V4: params 缺键回落 value_min", absf(prim.compute_value(desc_boost, {}) - float(desc_boost.get("value_min", 15.0))) < 0.001)
	_assert("V5: value_param=none 回落 value_min（波B口径兼容）", absf(prim.compute_value({"value_param": "none", "value_min": 15.0, "value_cap": 90.0}, {"anything": 9.0}) - 15.0) < 0.001)

	# ===== P-Position：选位语义（确定性 + fail-closed） =====
	var desc_wall: Dictionary = descriptors.get("field_obs_add", {})            # goal_ball_line
	var desc_drain: Dictionary = descriptors.get("field_drain_wall", {})       # enemy_carrier_path
	var desc_safe: Dictionary = descriptors.get("field_zone_safe", {})         # defensive_anchor
	var desc_boost_pos: Dictionary = descriptors.get("field_zone_boost", {})   # advance_lane
	var desc_vision: Dictionary = descriptors.get("field_vision_block", {})    # shoot_line_block
	var desc_heal: Dictionary = descriptors.get("field_zone_heal", {})         # defensive_anchor

	var pos_wall: Vector2 = prim.select_field_position(desc_wall, sad, ctx_full)
	_assert("P1a: goal_ball_line=球门-球连线0.6系数cap80（obs_add）", pos_wall.distance_to(Vector2(-420, 0)) < 0.001)
	var pos_drain: Vector2 = prim.select_field_position(desc_drain, sad, ctx_full)
	_assert("P1b: enemy_carrier_path=球门→持球敌0.4系数cap60（drain_wall）", pos_drain.distance_to(Vector2(-440, 0)) < 0.001)

	var ctx_aoe_def: Dictionary = ctx_full.duplicate(true)
	ctx_aoe_def["visible_enemies"] = [carrier, weak]
	var desc_danger_pos: Dictionary = desc_danger.duplicate(true)
	desc_danger_pos["intent"] = "defense"
	var pos_cluster_def: Vector2 = prim.select_field_position(desc_danger_pos, sad, ctx_aoe_def)
	_assert("P2a: enemy_cluster defense=最近敌（精化aoe雏形）", pos_cluster_def.distance_to(carrier.global_position) < 0.001)
	var desc_danger_atk: Dictionary = desc_danger.duplicate(true)
	desc_danger_atk["intent"] = "attack"
	var pos_cluster_atk: Vector2 = prim.select_field_position(desc_danger_atk, sad, ctx_aoe_def)
	_assert("P2b: enemy_cluster 其余=最残血敌（精化aoe雏形）", pos_cluster_atk.distance_to(weak.global_position) < 0.001)

	var pos_vision: Vector2 = prim.select_field_position(desc_vision, sad, ctx_full)
	_assert("P3: shoot_line_block=球门→持球敌0.5系数cap100（vision_block）", pos_vision.distance_to(Vector2(-400, 0)) < 0.001)
	var pos_lane: Vector2 = prim.select_field_position(desc_boost_pos, sad, ctx_full)
	_assert("P4: advance_lane=自位朝敌门60px（zone_boost）", pos_lane.distance_to(Vector2(60, 0)) < 0.001)
	var pos_anchor: Vector2 = prim.select_field_position(desc_safe, sad, ctx_full)
	var pos_anchor_heal: Vector2 = prim.select_field_position(desc_heal, sad, ctx_full)
	_assert("P5: defensive_anchor=己方球门前+20y（safe/heal同语义）", pos_anchor.distance_to(Vector2(-500, 20)) < 0.001 and pos_anchor_heal.distance_to(Vector2(-500, 20)) < 0.001)

	var ctx_min: Dictionary = {"player": caster}
	var pos_fallback_wall: Vector2 = prim.select_field_position(desc_wall, sad, ctx_min)
	var pos_fallback_drain: Vector2 = prim.select_field_position(desc_drain, sad, ctx_min)
	_assert("P6a: 缺ball/goal ctx fail-closed 回自站位（goal_ball_line/carrier_path）", pos_fallback_wall == caster.global_position and pos_fallback_drain == caster.global_position)
	_assert("P6b: position_intent=none 回自站位（obs_clear）", prim.select_field_position(descriptors.get("field_obs_clear", {}), sad, ctx_full) == caster.global_position)
	var desc_bogus: Dictionary = {"position_intent": "bogus_intent"}
	_assert("P6c: 未知 position_intent fail-closed 回自站位", prim.select_field_position(desc_bogus, sad, ctx_full) == caster.global_position)

	var ctx_mgr_carrier: Dictionary = ctx_noenemy.duplicate(true)
	ctx_mgr_carrier["enemy_carrier"] = carrier
	var pos_drain_mgr: Vector2 = prim.select_field_position(desc_drain, sad, ctx_mgr_carrier)
	_assert("P7: 敌持球者可经 ctx.enemy_carrier 单口注入（视野外持球敌路径）", pos_drain_mgr.distance_to(Vector2(-440, 0)) < 0.001)

	var pos_repeat: Vector2 = prim.select_field_position(desc_wall, sad, ctx_full)
	_assert("P8: 同输入两次选位恒同（零随机）", pos_repeat == pos_wall)
	_assert("P9: 7 枚举 position_intent 全量登记", prim.POSITION_INTENTS.size() == 7)

	# ===== I-集成面：容错与读表 =====
	var live: Dictionary = prim.get_descriptors()
	_assert("I1: get_descriptors 读实表得10标签", live.size() == 10)
	_assert("I2: timing_gate 对空 descriptor fail-closed", not bool(prim.timing_gate({}, {}, {}).get("ok")))
	_assert("I3a: resolve_target_mode 空描述符回落none", prim.resolve_target_mode({}, {}) == "none")
	_assert("I3b: resolve_target_mode 实描述符=field_position", prim.resolve_target_mode(desc_wall, {}) == "field_position")
	_assert("I4a: 坏 JSON 文本不崩溃（空表）", prim._parse_descriptors("{{{not json").is_empty())
	_assert("I4b: 缺 descriptors 键不崩溃（空表）", prim._parse_descriptors(JSON.stringify({"wave": "D"})).is_empty())

	# ===== R-纪律：源码红线 =====
	var src := FileAccess.get_file_as_string(D_SOURCE_PATH)
	_assert("R1: primitives_d.gd 源码无 randf(/randi(（确定性铁律）", src.find("randf(") == -1 and src.find("randi(") == -1)
	_assert("R2: primitives_d.gd 源码无 instance_id(（禁不稳定键）", src.find("instance_id(") == -1)
	_assert("R3: primitives_d.gd 源码无 ai_manager 直连（感知只从 ctx 取）", src.find("ai_manager") == -1)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（零热文件触碰）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
