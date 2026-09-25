## 波C操球窗口验收：球行为族17标签 + AI虚拟操作者
## 断言组：J-JSON契约 / G-Gate闸门 / V-Value计价 / O-操作意图 / K-状态机接线 / I-集成面 / R-纪律
## 契约：元灵技能AI规划/06_原语接口规约.md（波C扩展看板Q8）。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_wave_c.gd
extends SceneTree

const C_TABLE_PATH := "res://data/systems/spirit_ai/primitives_c.json"
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const C_SOURCE_PATH := "res://scripts/battle/spirit_ai/primitives_c.gd"
const INPUT_SOURCE_PATH := "res://scripts/battle/spirit_ai/ai_input_source.gd"
const STATE_MANAGER_PATH := "res://scripts/systems/spirit_system/skill_state_manager.gd"

## 波C 17标签全名单（07§④）
const WAVE_C_TAGS: Array[String] = [
	"ball_tracking", "ball_avoid", "ball_boomerang", "ball_straight", "ball_lockon",
	"ball_spread", "ball_bounce_enhance", "ball_transform", "ball_stealth",
	"ball_in_flight_boost", "ball_recall", "ball_manual_steering", "ball_penetrate",
	"ball_sure_hit", "ball_carry_push", "ball_range_up", "ball_range_down",
]

## 06§2.1 冻结字段 + 波C扩展字段 operation_mode/op_policy（Q8）
const REQUIRED_FIELDS: Array[String] = [
	"family", "direction", "timing_gate", "value_param", "value_unit",
	"value_min", "value_cap", "intent", "intent_strength", "target_mode",
	"operation_mode", "op_policy", "notes",
]

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_carrying_ball: bool = false
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var ball_ref: Node = null


class StubBall extends Node2D:
	var is_active: bool = true
	var _manual_active: bool = false
	var steer_count: int = 0
	var last_steer_dir: Vector2 = Vector2.ZERO
	var recalled_count: int = 0
	var boosted_count: int = 0

	func manual_steer(dir: Vector2) -> void:
		steer_count += 1
		last_steer_dir = dir

	func recall_ball(times: int) -> void:
		recalled_count += times

	func boost_in_flight(opts: Dictionary) -> void:
		boosted_count += 1


## K10 用：最小状态机 stub（验证 apply_operation 走公开入口 on_skill_key_pressed 的调用面）
class StubStateManager extends RefCounted:
	var pressed: Array = []

	func on_skill_key_pressed(player_id: int, slot: int) -> bool:
		pressed.append({"pid": player_id, "slot": slot})
		return true


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 波C操球窗口：球行为17标签 + AI虚拟操作者 ==========\n")
	for i in range(3):
		await process_frame

	var prim: GDScript = load("res://scripts/battle/spirit_ai/primitives_c.gd")
	var input_src: GDScript = load("res://scripts/battle/spirit_ai/ai_input_source.gd")

	# ===== J-JSON：契约与 registry 一致性 =====
	var table_text := FileAccess.get_file_as_string(C_TABLE_PATH)
	var table: Variant = JSON.parse_string(table_text)
	_assert("J1: 原语表 JSON 可解析", typeof(table) == TYPE_DICTIONARY)
	if typeof(table) != TYPE_DICTIONARY:
		_finish()
		return
	_assert("J2: wave=C / schema_version=4（Q8扩展版）", str(table.get("wave", "")) == "C" and int(table.get("schema_version", 0)) == 4)
	var descriptors: Dictionary = table.get("descriptors", {})
	_assert("J3: 描述符恰为17个", descriptors.size() == 17)

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
	var mode_gate_ok := true
	var family_count: Dictionary = {"ball_flight": 0, "ball_hit": 0, "ball_range": 0}
	var op_count: Dictionary = {"none": 0, "steer": 0, "midfly": 0}
	for tag_id in WAVE_C_TAGS:
		var d: Variant = descriptors.get(tag_id)
		if typeof(d) != TYPE_DICTIONARY:
			ids_ok = false
			print("    [缺标签] " + tag_id)
			continue
		var desc: Dictionary = d
		if not reg_by_id.has(tag_id):
			ids_ok = false
			print("    [registry无此id] " + tag_id)
		var keys := desc.keys()
		if keys.size() != REQUIRED_FIELDS.size():
			fields_ok = false
			print("    [字段数不符] %s: %d" % [tag_id, keys.size()])
		for f in REQUIRED_FIELDS:
			if not desc.has(f):
				fields_ok = false
				print("    [缺字段] %s.%s" % [tag_id, f])
		# 枚举合法
		if str(desc.get("family", "")) not in ["ball_flight", "ball_hit", "ball_range"]:
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
		if str(desc.get("target_mode", "")) != "ball":
			enum_ok = false
			print("    [target_mode非ball] " + tag_id)
		if str(desc.get("operation_mode", "")) not in prim.OPERATION_MODES:
			enum_ok = false
			print("    [operation_mode非法] " + tag_id)
		if str(desc.get("op_policy", "")) not in prim.OP_POLICIES:
			enum_ok = false
			print("    [op_policy非法] " + tag_id)
		var strength := float(desc.get("intent_strength", -1.0))
		if strength < 0.0 or strength > 1.0:
			enum_ok = false
			print("    [intent_strength越界] " + tag_id)
		# value_param 以 registry params 数组为准（none=无参数标签合规口径，波B先例）
		var vp := str(desc.get("value_param", ""))
		var reg_tag: Dictionary = reg_by_id.get(tag_id, {})
		var reg_params: Variant = reg_tag.get("params", [])
		if vp != "none" and not (typeof(reg_params) == TYPE_ARRAY and (reg_params as Array).has(vp)):
			param_ok = false
			print("    [value_param不在registry params] %s: %s" % [tag_id, vp])
		# 数值域
		var v_min := float(desc.get("value_min", 0.0))
		var v_cap := float(desc.get("value_cap", 0.0))
		if v_min > v_cap or v_cap > 90.0:
			range_ok = false
			print("    [数值域非法] %s: min=%.1f cap=%.1f" % [tag_id, v_min, v_cap])
		# 波C特有：operation_mode 与 gate/policy 联动（midfly↔ball_flight；steer 无 policy）
		var mode := str(desc.get("operation_mode", "none"))
		var gate := str(desc.get("timing_gate", ""))
		if mode == "midfly" and gate != "ball_flight":
			mode_gate_ok = false
			print("    [midfly须走ball_flight] " + tag_id)
		if mode == "steer" and str(desc.get("op_policy", "")) != "":
			mode_gate_ok = false
			print("    [steer不须policy] " + tag_id)
		if mode == "midfly" and str(desc.get("op_policy", "")) not in ["recall", "boost"]:
			mode_gate_ok = false
			print("    [midfly须policy] " + tag_id)
		family_count[str(desc.get("family", ""))] = int(family_count.get(str(desc.get("family", "")), 0)) + 1
		op_count[mode] = int(op_count.get(mode, 0)) + 1
	_assert("J5: 17标签 id 与 registry 逐字一致", ids_ok)
	_assert("J6: 字段齐全无多余（冻结10字段+Q8两字段+notes）", fields_ok)
	_assert("J7: 枚举全部合法（family/direction/gate/intent/target_mode/mode/policy/强度）", enum_ok)
	_assert("J8: value_param 逐一在 registry params（none=无参口径）", param_ok)
	_assert("J9: value_min ≤ value_cap ≤ 90", range_ok)
	_assert("J10: operation_mode 联动契约（midfly↔ball_flight / steer 无policy）", mode_gate_ok)
	_assert("J11: family 计数 14+1+2=17", int(family_count.get("ball_flight", 0)) == 14 and int(family_count.get("ball_hit", 0)) == 1 and int(family_count.get("ball_range", 0)) == 2)
	_assert("J12: operation_mode 计数 注入14+steer1+midfly2=17", int(op_count.get("none", 0)) == 14 and int(op_count.get("steer", 0)) == 1 and int(op_count.get("midfly", 0)) == 2)

	# ===== G-Gate：12 键正反例（波C重点：ball_flight） =====
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_c_caster"
	caster.team = "a"
	caster.is_carrying_ball = true
	caster.position = Vector2(0, 0)
	root.add_child(caster)
	var carrier: StubPlayer = StubPlayer.new()
	carrier.character_id = "t_c_carrier"
	carrier.team = "b"
	carrier.is_carrying_ball = true
	carrier.position = Vector2(300, 0)
	root.add_child(carrier)
	var weak: StubPlayer = StubPlayer.new()
	weak.character_id = "t_c_weak"
	weak.team = "b"
	weak.is_carrying_ball = false
	weak.stamina = 25.0
	weak.position = Vector2(400, 50)
	root.add_child(weak)
	var far: StubPlayer = StubPlayer.new()
	far.character_id = "t_c_far"
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
		"ball_position": Vector2(100, 0),
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
	_assert("G1d: ball_hold_engage 持球+视野内敌→过（注入族主闸门）", bool(prim.timing_gate({"timing_gate": "ball_hold_engage"}, sad, ctx_full).get("ok")))
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
	var ctx_ally_obj: Dictionary = {"player": caster, "allies": [{"stamina_ratio": 0.3}]}
	_assert("G5a: ally_injured 比值表<0.35→过", bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_bad).get("ok")))
	_assert("G5b: ally_injured 全健康→不过", not bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_ok).get("ok")))
	_assert("G5c: ally_injured 对象表（波B allies 形态兼容）→过", bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, ctx_ally_obj).get("ok")))
	_assert("G5d: ally_injured 缺键 fail-closed", not bool(prim.timing_gate({"timing_gate": "ally_injured"}, sad, {}).get("ok")))
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
	var g_flight: Dictionary = prim.timing_gate({"timing_gate": "ball_flight"}, sad, {"ball_in_flight": true})
	_assert("G7c: ball_flight 本波启用（操控族时机）→过", bool(g_flight.get("ok")))
	_assert("G7d: ball_flight 缺省 fail-closed（未接线零触发）", not bool(prim.timing_gate({"timing_gate": "ball_flight"}, sad, {}).get("ok")))
	_assert("G7e: ally_cast_setup 预留键可判定", bool(prim.timing_gate({"timing_gate": "ally_cast_setup"}, sad, {"combo_setup_active": true}).get("ok")))
	_assert("G8a: 未知 gate 键 fail-closed", not bool(prim.timing_gate({"timing_gate": "bogus_gate"}, sad, ctx_full).get("ok")))
	_assert("G8b: 空 descriptor fail-closed", not bool(prim.timing_gate({}, sad, ctx_full).get("ok")))
	_assert("G8c: 缺 player ctx 的节点级 gate fail-closed", not bool(prim.timing_gate({"timing_gate": "ball_hold"}, sad, {"visible_enemies": []}).get("ok")))
	_assert("G9: 12 gate 键全量登记", prim.GATE_KEYS.size() == 12)

	# ===== V-Value：计价（三家族 + clamp + 缺参回落 + none 平价） =====
	var desc_boost_fly: Dictionary = descriptors.get("ball_in_flight_boost", {})
	var desc_push: Dictionary = descriptors.get("ball_carry_push", {})
	var desc_range_up: Dictionary = descriptors.get("ball_range_up", {})
	var desc_track: Dictionary = descriptors.get("ball_tracking", {})
	var desc_boom: Dictionary = descriptors.get("ball_boomerang", {})
	var desc_lockon: Dictionary = descriptors.get("ball_lockon", {})
	_assert("V1: ball_flight 族计价（boost dmg_pct 60×0.5=30）", absf(prim.compute_value(desc_boost_fly, {"dmg_pct": 60.0}) - 30.0) < 0.001)
	_assert("V2: ball_hit 族计价（push pull_speed 400×0.12=48）", absf(prim.compute_value(desc_push, {"pull_speed": 400.0}) - 48.0) < 0.001)
	_assert("V3: ball_range 族计价（range_up damage_pct 60×0.5=30）", absf(prim.compute_value(desc_range_up, {"damage_pct": 60.0}) - 30.0) < 0.001)
	_assert("V4a: clamp 上限（tracking turn_speed 10×12=120→cap60）", absf(prim.compute_value(desc_track, {"turn_speed": 10.0}) - 60.0) < 0.001)
	_assert("V4b: clamp 下限（boomerang 20×0.25=5→min15）", absf(prim.compute_value(desc_boom, {"return_distance": 20.0}) - 15.0) < 0.001)
	_assert("V5: params 缺键回落 value_min", absf(prim.compute_value(desc_track, {}) - float(desc_track.get("value_min", 15.0))) < 0.001)
	_assert("V6: value_param=none 恒 value_min 平价（波B口径，不受 params 干扰）", absf(prim.compute_value(desc_lockon, {"anything": 999.0}) - float(desc_lockon.get("value_min", 15.0))) < 0.001)

	# ===== O-操作意图：AI虚拟操作者生成语义（确定性 + fail-closed） =====
	var desc_steer: Dictionary = descriptors.get("ball_manual_steering", {})
	var desc_recall: Dictionary = descriptors.get("ball_recall", {})
	var desc_flyboost: Dictionary = descriptors.get("ball_in_flight_boost", {})
	var desc_track_op: Dictionary = descriptors.get("ball_tracking", {})

	var o_inject: Dictionary = input_src.generate_operation_intent(desc_track_op, sad, ctx_full)
	_assert("O1: 注入族→none AUTO（零操作）", str(o_inject.get("op", "")) == "none" and not bool(o_inject.get("should_press", true)))

	var o_steer: Dictionary = input_src.generate_operation_intent(desc_steer, sad, ctx_full)
	var want_aim: Vector2 = (Vector2(500, 0) - Vector2(100, 0)).normalized()
	_assert("O2: steer 优先敌门方向（归一化）", str(o_steer.get("op", "")) == "steer" and (o_steer.get("aim_direction", Vector2.ZERO) as Vector2).distance_to(want_aim) < 0.001)

	var ctx_enemy_only: Dictionary = {"player": caster, "ball_position": Vector2(0, 0), "visible_enemies": [carrier, weak]}
	var o_steer_enemy: Dictionary = input_src.generate_operation_intent(desc_steer, sad, ctx_enemy_only)
	_assert("O3: steer 无门信息→最近敌拦截向", (o_steer_enemy.get("aim_direction", Vector2.ZERO) as Vector2).distance_to(Vector2(1, 0)) < 0.001)

	var ctx_minimal: Dictionary = {"player": caster}
	var o_steer_min: Dictionary = input_src.generate_operation_intent(desc_steer, sad, ctx_minimal)
	_assert("O4: steer 零ctx→零向量 fail-closed（球走直线）", (o_steer_min.get("aim_direction", Vector2.ONE) as Vector2) == Vector2.ZERO)

	var ctx_vel_only: Dictionary = {"player": caster, "ball_position": Vector2(0, 0), "ball_velocity": Vector2(0, -30)}
	var o_steer_vel: Dictionary = input_src.generate_operation_intent(desc_steer, sad, ctx_vel_only)
	_assert("O5: steer 保持当前航向（velocity 归一）", (o_steer_vel.get("aim_direction", Vector2.ZERO) as Vector2).distance_to(Vector2(0, -1)) < 0.001)

	var ctx_recall_far: Dictionary = {"player": caster, "ball_position": Vector2(400, 0), "visible_enemies": []}
	var o_recall_far: Dictionary = input_src.generate_operation_intent(desc_recall, sad, ctx_recall_far)
	_assert("O6: recall 球远>350→再按", str(o_recall_far.get("op", "")) == "midfly" and bool(o_recall_far.get("should_press", false)))
	var ctx_recall_near: Dictionary = {"player": caster, "ball_position": Vector2(100, 0), "visible_enemies": []}
	var o_recall_hold: Dictionary = input_src.generate_operation_intent(desc_recall, sad, ctx_recall_near)
	_assert("O7: recall 球近无敌→hold（操作余量不用）", not bool(o_recall_hold.get("should_press", true)))
	carrier.position = Vector2(110, 0)
	var ctx_recall_intercept: Dictionary = {"player": caster, "ball_position": Vector2(100, 0), "visible_enemies": [carrier]}
	var o_recall_int: Dictionary = input_src.generate_operation_intent(desc_recall, sad, ctx_recall_intercept)
	_assert("O8: recall 敌近球<120→再按（防截）", bool(o_recall_int.get("should_press", false)))
	carrier.position = Vector2(300, 0)

	var ctx_boost_goal: Dictionary = {"player": caster, "ball_position": Vector2(100, 0), "ball_velocity": Vector2(40, 0), "enemy_goal": Vector2(500, 0), "visible_enemies": []}
	var o_boost: Dictionary = input_src.generate_operation_intent(desc_flyboost, sad, ctx_boost_goal)
	_assert("O9: boost 球朝敌门→再按", str(o_boost.get("op", "")) == "midfly" and bool(o_boost.get("should_press", false)))
	var ctx_boost_away: Dictionary = {"player": caster, "ball_position": Vector2(100, 0), "ball_velocity": Vector2(-40, 0), "enemy_goal": Vector2(500, 0), "visible_enemies": []}
	var o_boost_away: Dictionary = input_src.generate_operation_intent(desc_flyboost, sad, ctx_boost_away)
	_assert("O10: boost 球背门→hold", not bool(o_boost_away.get("should_press", true)))

	var sad_odd: Dictionary = {"skill_exec_count": 1}
	var o_cadence: Dictionary = input_src.generate_operation_intent(desc_recall, sad_odd, ctx_recall_far)
	_assert("O11: 周期节流 exec_count=1→hold（1.0s间隔>双击窗，确定性）", not bool(o_cadence.get("should_press", true)))
	var sad_even: Dictionary = {"skill_exec_count": 2}
	var o_cadence_ok: Dictionary = input_src.generate_operation_intent(desc_recall, sad_even, ctx_recall_far)
	_assert("O12: 周期节流 exec_count=2→放行", bool(o_cadence_ok.get("should_press", false)))

	var desc_bogus_mode: Dictionary = {"operation_mode": "warp"}
	var o_bogus: Dictionary = input_src.generate_operation_intent(desc_bogus_mode, sad, ctx_full)
	_assert("O13a: 未知 operation_mode fail-closed→none", str(o_bogus.get("op", "")) == "none")
	_assert("O13b: 空 descriptor fail-closed→none", str(input_src.generate_operation_intent({}, sad, ctx_full).get("op", "")) == "none")
	var desc_bogus_policy: Dictionary = {"operation_mode": "midfly", "op_policy": "teleport"}
	var o_bogus_p: Dictionary = input_src.generate_operation_intent(desc_bogus_policy, sad, ctx_recall_far)
	_assert("O13c: 未知 op_policy fail-closed→none", str(o_bogus_p.get("op", "")) == "none")
	var o_repeat: Dictionary = input_src.generate_operation_intent(desc_steer, sad, ctx_full)
	_assert("O14: 同输入两次生成恒同（零随机）", (o_repeat.get("aim_direction", Vector2.ONE) as Vector2).distance_to(o_steer.get("aim_direction", Vector2.ZERO)) < 0.001)

	# ===== K-状态机接线：skill_state_manager AI 输入源口 =====
	var sm: Node = load(STATE_MANAGER_PATH).new()
	root.add_child(sm)
	_assert("K1: 出厂态 AI 登记为空（未接线零行为差异）", sm.ai_virtual_inputs.is_empty() and sm.get_ai_aim(999) == Vector2.ZERO)
	_assert("K2: attach 有口→登记成功", bool(input_src.attach(sm, 9001, caster)))
	_assert("K3: 登记 caster/瞄准可写可读", sm.get_ai_aim(9001) == Vector2.ZERO and (sm.ai_virtual_inputs.get(9001, {}).get("caster") == caster))
	sm.set_ai_aim(9001, Vector2(1, 0))
	_assert("K4: set_ai_aim→get_ai_aim 回读一致", sm.get_ai_aim(9001) == Vector2(1, 0))
	sm.set_ai_aim(7777, Vector2(1, 1))
	_assert("K5: 未登记 player 写瞄准被忽略", sm.get_ai_aim(7777) == Vector2.ZERO)

	# K6：MIDFLY 球源解析——AI caster.ball_ref 优先于 controlled_player 链（AI 无 input_manager）
	var ai_ball: StubBall = StubBall.new()
	ai_ball.is_active = true
	caster.ball_ref = ai_ball
	sm._operator_context[9001] = {"operator": "OP_MIDFLY", "substate": 0, "skill_id": "t_midfly", "slot": 0, "midfly_left": 2}
	var midfly_ok: bool = sm._trigger_midfly(9001, "t_midfly")
	_assert("K6: _trigger_midfly 经 AI caster 球源命中拉回", midfly_ok and ai_ball.recalled_count == 1)
	_assert("K7: 干预次数扣减（2→1）", int(sm._operator_context.get(9001, {}).get("midfly_left", -1)) == 1)

	var sm_bare: Node = load(STATE_MANAGER_PATH).new()
	root.add_child(sm_bare)
	sm_bare._operator_context[9002] = {"operator": "OP_MIDFLY", "substate": 0, "skill_id": "t_midfly", "slot": 0, "midfly_left": 2}
	var midfly_noai: bool = sm_bare._trigger_midfly(9002, "t_midfly")
	_assert("K8: 未登记 AI→球源回落原链（空）→不干预（零行为差异）", not midfly_noai)

	# K9：apply_operation 全链——steer 走球侧同口 + 瞄准留档；midfly 走公开再按入口
	var steer_intent: Dictionary = {"op": "steer", "aim_direction": Vector2(1, 0), "should_press": false, "reason": "steer_window"}
	ai_ball._manual_active = true
	var applied: bool = input_src.apply_operation(steer_intent, sm, 9001, caster, 0)
	_assert("K9a: steer 经 ball.manual_steer（与 input_manager 同口）", applied and ai_ball.steer_count == 1 and ai_ball.last_steer_dir == Vector2(1, 0))
	_assert("K9b: 瞄准意图经 set_ai_aim 留档", sm.get_ai_aim(9001) == Vector2(1, 0))
	ai_ball._manual_active = false
	_assert("K9c: 球非手动态→不干预（同 input_manager 闸门）", not bool(input_src.apply_operation(steer_intent, sm, 9001, caster, 0)) and ai_ball.steer_count == 1)

	# K10：midfly 公开入口再按调用面（真实 OP_MIDFLY 技能数据 skills.json 现无，
	# get_operator 回落 OP_AUTO——全链公开路径断言归集成接线工单；此处验证 apply_operation
	# 只经 on_skill_key_pressed 公开入口触发干预，无旁路）
	var stub_sm: StubStateManager = StubStateManager.new()
	var midfly_intent: Dictionary = {"op": "midfly", "aim_direction": Vector2.ZERO, "should_press": true, "reason": "ball_far"}
	_assert("K10a: slot<0 fail-closed 不按", not bool(input_src.apply_operation(midfly_intent, stub_sm, 9003, caster, -1)))
	_assert("K10b: null 状态机 fail-closed 不按", not bool(input_src.apply_operation(midfly_intent, null, 9003, caster, 0)))
	_assert("K10c: should_press=false 不按", not bool(input_src.apply_operation({"op": "midfly", "should_press": false}, stub_sm, 9003, caster, 0)))
	var pressed_ok: bool = bool(input_src.apply_operation(midfly_intent, stub_sm, 9003, caster, 2))
	var pressed_rec: Dictionary = stub_sm.pressed[0] if not stub_sm.pressed.is_empty() else {}
	_assert("K10d: 放行→经公开入口 on_skill_key_pressed(9003, slot=2)", pressed_ok and int(pressed_rec.get("pid", -1)) == 9003 and int(pressed_rec.get("slot", -1)) == 2)
	input_src.detach(sm, 9001)
	_assert("K11: detach 有口→注销成功", not sm.ai_virtual_inputs.has(9001))

	# K12：attach 无口状态机 fail-closed（旧状态机/异构对象不崩）
	_assert("K12: attach 无 register 口→false（fail-closed）", not bool(input_src.attach(RefCounted.new(), 9004, caster)))
	sm.cleanup_player(9001)
	_assert("K13: cleanup_player 清 AI 登记", not sm.ai_virtual_inputs.has(9001))

	# ===== I-集成面：容错与读表 =====
	var live: Dictionary = prim.get_descriptors()
	_assert("I1: get_descriptors 读实表得17标签", live.size() == 17)
	_assert("I2: timing_gate 对空 descriptor fail-closed", not bool(prim.timing_gate({}, {}, {}).get("ok")))
	_assert("I3a: resolve_target_mode 空描述符回落none", prim.resolve_target_mode({}, {}) == "none")
	_assert("I3b: resolve_target_mode 实描述符=ball", prim.resolve_target_mode(descriptors.get("ball_tracking", {}), {}) == "ball")
	_assert("I4a: 坏 JSON 文本不崩溃（空表）", prim._parse_descriptors("{{{not json").is_empty())
	_assert("I4b: 缺 descriptors 键不崩溃（空表）", prim._parse_descriptors(JSON.stringify({"wave": "C"})).is_empty())
	_assert("I5: OPERATION_MODES 3枚举 / OP_POLICIES 3枚举", prim.OPERATION_MODES.size() == 3 and prim.OP_POLICIES.size() == 3)
	_assert("I6: ai_input_source 与 primitives_c 的 operation_mode 词表恒同", str(input_src.OPERATION_MODES) == str(prim.OPERATION_MODES))

	# ===== R-纪律：源码红线 =====
	var src: String = FileAccess.get_file_as_string(C_SOURCE_PATH)
	_assert("R1: primitives_c.gd 源码无 randf(/randi(（确定性铁律）", src.find("randf(") == -1 and src.find("randi(") == -1)
	_assert("R2: primitives_c.gd 源码无 instance_id(（禁不稳定键）", src.find("instance_id(") == -1)
	_assert("R3: primitives_c.gd 源码无 ai_manager 直连（感知只从 ctx 取）", src.find("ai_manager") == -1)
	var src_in: String = FileAccess.get_file_as_string(INPUT_SOURCE_PATH)
	_assert("R4: ai_input_source.gd 无 randf(/randi(（禁墙钟/随机流）", src_in.find("randf(") == -1 and src_in.find("randi(") == -1 and src_in.find("ticks_msec") == -1)
	_assert("R5: ai_input_source.gd 无 instance_id(", src_in.find("instance_id(") == -1)
	_assert("R6: ai_input_source.gd 无 ai_manager 直连", src_in.find("ai_manager") == -1)
	_assert("R7: ai_input_source.gd 禁旁路直调 use_skill", src_in.find("use_skill") == -1)
	var src_sm: String = FileAccess.get_file_as_string(STATE_MANAGER_PATH)
	_assert("R8: skill_state_manager.gd 无 randf(/randi(（存量纪律不回退）", src_sm.find("randf(") == -1 and src_sm.find("randi(") == -1)

	_finish()


func _finish() -> void:
	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（波C交付门槛达成）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
