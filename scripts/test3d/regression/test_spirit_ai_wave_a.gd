## 06接口规约 §6.1 波A验收套件：J-JSON / G-Gate / V-Value / I-集成面 / R-纪律
## 白名单三文件（primitives_a.json / primitives_a.gd / 本文件）由窗口在 commit 前以
## git status 外部核对恰为白名单（套件内无法安全调 git，R 组在此只查源码纪律）。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_wave_a.gd
extends SceneTree

const PrimitivesA = preload("res://scripts/battle/spirit_ai/primitives_a.gd")
const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const TABLE_PATH := "res://data/systems/spirit_ai/primitives_a.json"

## 07§① 波A 39标签全名单（与 registry 逐字对账的基准）
const WAVE_A_IDS: Array[String] = [
	"ball_dmg_up_pct", "ball_dmg_down_pct", "ball_dmg_up_flat", "ball_dmg_down_flat",
	"ball_speed_up_pct", "ball_speed_down_pct", "ball_speed_up_flat", "ball_speed_down_flat",
	"player_atk_up_pct", "player_atk_down_pct", "player_atk_up_flat", "player_atk_down_flat",
	"player_def_up_pct", "player_def_down_pct", "player_def_up_flat", "player_def_down_flat",
	"player_spd_up_pct", "player_spd_down_pct", "player_spd_up_flat", "player_spd_down_flat",
	"player_res_up_pct", "player_res_down_pct", "player_res_up_flat", "player_res_down_flat",
	"player_energy_gain_pct", "player_energy_cost_pct", "player_energy_gain_flat",
	"player_energy_cost_flat", "player_energy_max_up_pct", "player_energy_max_down_pct",
	"player_energy_max_up_flat", "player_energy_max_down_flat",
	"player_spirit_cost_down", "player_spirit_cost_up", "player_spirit_uses_up",
	"player_spirit_cd_down", "player_spirit_cd_up", "player_spirit_double", "player_spirit_half",
]

## 06 §三 冻结的 12 个 gate 键
const GATE_KEYS: Array[String] = [
	"always", "ball_hold", "ball_hold_engage", "enemy_visible", "enemy_carrying_visible",
	"self_threatened", "self_injured", "ally_injured", "calm_state", "pre_burst",
	"ball_flight", "ally_cast_setup",
]

## 06 §2.1 schema 冻结字段（禁新增）
const SCHEMA_FIELDS: Array[String] = [
	"family", "direction", "timing_gate", "value_param", "value_unit",
	"value_min", "value_cap", "intent", "intent_strength", "target_mode", "notes",
]
const FAMILIES: Array[String] = ["ball_stat", "player_attr", "energy_mgmt"]
const DIRECTIONS: Array[String] = ["self", "enemy"]
const INTENTS: Array[String] = ["attack", "defense", "support", "control"]
const TARGET_MODES: Array[String] = ["ball", "self", "enemy_visible", "ally_support", "none"]

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_carrying_ball: bool = false
	var stamina_ratio: float = 1.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 06规约 波A验收：纯增益/资源族 39 标签 ==========\n")
	for i in range(3):
		await process_frame

	var descs: Dictionary = PrimitivesA.get_descriptors()
	var registry: Dictionary = _load_registry()

	# ===== J-JSON：39标签 × registry 逐字一致 × schema 冻结 =====
	_assert("J1: 表内恰为39个标签（不缺不多）", descs.size() == 39 and _same_set(descs.keys(), WAVE_A_IDS))
	var schema_ok: bool = true
	var enum_ok: bool = true
	var param_ok: bool = true
	var bound_ok: bool = true
	var gate_ok: bool = true
	for id in WAVE_A_IDS:
		var d: Dictionary = descs[id]
		if d.keys().size() != SCHEMA_FIELDS.size():
			schema_ok = false
		for f in SCHEMA_FIELDS:
			if not d.has(f):
				schema_ok = false
		if not (str(d["family"]) in FAMILIES and str(d["direction"]) in DIRECTIONS \
				and str(d["intent"]) in INTENTS and str(d["target_mode"]) in TARGET_MODES):
			enum_ok = false
		if not (str(d["timing_gate"]) in GATE_KEYS):
			gate_ok = false
		var reg_params: Array = registry.get(id, {}).get("params", [])
		if not (str(d["value_param"]) in reg_params):
			param_ok = false
		if not (float(d["value_min"]) <= float(d["value_cap"]) and float(d["value_cap"]) <= 90.0):
			bound_ok = false
		if float(d["value_unit"]) <= 0.0:
			bound_ok = false
	_assert("J2: schema 字段齐全且无多余（禁新增字段）", schema_ok)
	_assert("J3: family/direction/intent/target_mode 枚举合法", enum_ok)
	_assert("J4: timing_gate 全部为 §三 冻结键", gate_ok)
	_assert("J5: value_param 逐一存在于 registry params 数组", param_ok)
	_assert("J6: value_min ≤ value_cap ≤ 90 且 value_unit > 0", bound_ok)

	# ===== G-Gate：12 键逐一正反例 + 未知键 fail-closed + bonus 两档 =====
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_wa_caster"
	caster.team = "a"
	var enemy_far: StubPlayer = StubPlayer.new()
	enemy_far.team = "b"
	enemy_far.position = Vector2(300, 0)
	var enemy_near: StubPlayer = StubPlayer.new()
	enemy_near.team = "b"
	enemy_near.position = Vector2(150, 0)
	var enemy_close: StubPlayer = StubPlayer.new()
	enemy_close.team = "b"
	enemy_close.position = Vector2(80, 0)
	var enemy_hold: StubPlayer = StubPlayer.new()
	enemy_hold.team = "b"
	enemy_hold.position = Vector2(120, 0)
	enemy_hold.is_carrying_ball = true

	var ctx_base: Dictionary = {"player": caster, "stamina_ratio": 1.0}
	var sad: Dictionary = {"skill_decide_count": 3}

	var g := func(key: String, ctx: Dictionary) -> Dictionary:
		return PrimitivesA.timing_gate({"timing_gate": key}, sad, ctx)

	caster.is_carrying_ball = true
	_assert("G1 always: 恒真 bonus=1.0", g.call("always", ctx_base)["ok"] and float(g.call("always", ctx_base)["bonus"]) == 1.0)
	_assert("G2 ball_hold: 持球过/不持球不过", g.call("ball_hold", ctx_base)["ok"])
	caster.is_carrying_ball = false
	_assert("G2b ball_hold 反例", not g.call("ball_hold", ctx_base)["ok"])

	caster.is_carrying_ball = true
	ctx_base["visible_enemies"] = [enemy_near]
	_assert("G3 ball_hold_engage: 持球+视野内敌 过", g.call("ball_hold_engage", ctx_base)["ok"])
	ctx_base["visible_enemies"] = []
	_assert("G3b ball_hold_engage 反例：持球无敌", not g.call("ball_hold_engage", ctx_base)["ok"])
	caster.is_carrying_ball = false
	ctx_base["visible_enemies"] = [enemy_near]
	_assert("G3c ball_hold_engage 反例：不持球", not g.call("ball_hold_engage", ctx_base)["ok"])

	_assert("G4 enemy_visible: 有敌过/无敌不过", g.call("enemy_visible", ctx_base)["ok"])
	ctx_base["visible_enemies"] = []
	_assert("G4b enemy_visible 反例", not g.call("enemy_visible", ctx_base)["ok"])

	ctx_base["visible_enemies"] = [enemy_hold]
	_assert("G5 enemy_carrying_visible: 敌持球可见 过", g.call("enemy_carrying_visible", ctx_base)["ok"])
	ctx_base["visible_enemies"] = [enemy_near]
	_assert("G5b enemy_carrying_visible 反例：敌未持球", not g.call("enemy_carrying_visible", ctx_base)["ok"])

	# self_threatened：默认 threat_radius=200；<100px 强触发 1.25
	ctx_base["visible_enemies"] = [enemy_near]  # 150px
	_assert("G6 self_threatened: 150px<200 过 且 bonus=1.0",
			g.call("self_threatened", ctx_base)["ok"] and float(g.call("self_threatened", ctx_base)["bonus"]) == 1.0)
	ctx_base["visible_enemies"] = [enemy_close]  # 80px
	_assert("G6b self_threatened 强触发: <100px bonus=1.25", float(g.call("self_threatened", ctx_base)["bonus"]) == 1.25)
	ctx_base["visible_enemies"] = [enemy_far]  # 300px
	_assert("G6c self_threatened 反例：远敌+满体力", not g.call("self_threatened", ctx_base)["ok"])
	ctx_base["stamina_ratio"] = 0.3
	_assert("G6d self_threatened: 体力<0.4 兜底触发", g.call("self_threatened", ctx_base)["ok"])
	ctx_base["stamina_ratio"] = 1.0

	_assert("G7 self_injured: 0.3<0.35 过", g.call("self_injured", {"player": caster, "stamina_ratio": 0.3})["ok"])
	_assert("G7b self_injured 反例：0.5", not g.call("self_injured", {"player": caster, "stamina_ratio": 0.5})["ok"])

	var hurt_ally: StubPlayer = StubPlayer.new()
	hurt_ally.stamina_ratio = 0.3
	var ok_ally: StubPlayer = StubPlayer.new()
	ok_ally.stamina_ratio = 0.9
	_assert("G8 ally_injured: 队友残血 过", g.call("ally_injured", {"allies": [ok_ally, hurt_ally]})["ok"])
	_assert("G8b ally_injured 反例：全员健康", not g.call("ally_injured", {"allies": [ok_ally]})["ok"])
	_assert("G8c ally_injured: ctx 缺 allies fail-closed", not g.call("ally_injured", {})["ok"])

	caster.is_carrying_ball = false
	ctx_base["visible_enemies"] = []
	ctx_base["stamina_ratio"] = 0.8
	_assert("G9 calm_state: 不持球+无敌+体力>0.5 过", g.call("calm_state", ctx_base)["ok"])
	caster.is_carrying_ball = true
	_assert("G9b calm_state 反例：持球", not g.call("calm_state", ctx_base)["ok"])
	caster.is_carrying_ball = false
	ctx_base["visible_enemies"] = [enemy_near]
	_assert("G9c calm_state 反例：视野有敌", not g.call("calm_state", ctx_base)["ok"])
	ctx_base["visible_enemies"] = []
	ctx_base["stamina_ratio"] = 0.4
	_assert("G9d calm_state 反例：体力≤0.5", not g.call("calm_state", ctx_base)["ok"])
	ctx_base["stamina_ratio"] = 1.0

	_assert("G10 pre_burst: 能量卡大招 过", g.call("pre_burst", {"has_energy_blocked_burst": true})["ok"])
	_assert("G10b pre_burst 反例", not g.call("pre_burst", {"has_energy_blocked_burst": false})["ok"])
	_assert("G11 ball_flight: ctx 缺省 fail-closed / true 过",
			not g.call("ball_flight", {})["ok"] and g.call("ball_flight", {"ball_in_flight": true})["ok"])
	_assert("G12 ally_cast_setup: ctx 缺省 fail-closed / true 过",
			not g.call("ally_cast_setup", {})["ok"] and g.call("ally_cast_setup", {"combo_setup_active": true})["ok"])
	_assert("G13 未知 gate 键 fail-closed", not g.call("__no_such_gate__", ctx_base)["ok"])
	_assert("G14 空 descriptor fail-closed", not PrimitivesA.timing_gate({}, sad, ctx_base)["ok"])

	# ===== V-Value：每家族计价 + clamp 上下限 + 缺参数回落（浮点一律 is_equal_approx）=====
	var d_ball: Dictionary = descs["ball_dmg_up_pct"]
	_assert("V1 ball_stat 计价: 20×1.5=30", is_equal_approx(PrimitivesA.compute_value(d_ball, {"value": 20}), 30.0))
	_assert("V1b clamp 上限: 100×1.5→cap 90", is_equal_approx(PrimitivesA.compute_value(d_ball, {"value": 100}), 90.0))
	_assert("V1c clamp 下限: 1×1.5→min 15", is_equal_approx(PrimitivesA.compute_value(d_ball, {"value": 1}), 15.0))
	_assert("V1d 缺参数回落 value_min", is_equal_approx(PrimitivesA.compute_value(d_ball, {}), 15.0))
	var d_attr: Dictionary = descs["player_atk_up_pct"]
	_assert("V2 player_attr 计价: 30×1.2=36", is_equal_approx(PrimitivesA.compute_value(d_attr, {"value": 30}), 36.0))
	var d_energy: Dictionary = descs["player_spirit_cd_down"]
	_assert("V3 energy_mgmt 计价: 0.7×70=49", is_equal_approx(PrimitivesA.compute_value(d_energy, {"multiplier": 0.7}), 49.0))
	var d_half: Dictionary = descs["player_spirit_half"]
	_assert("V3b spirit_half 计价: 5s×7=35（registry 裁决敌向）", is_equal_approx(PrimitivesA.compute_value(d_half, {"duration": 5}), 35.0))

	# ===== I-集成面：空表/坏 JSON 不崩溃；空 descriptor fail-closed =====
	_assert("I1: get_descriptors 39条不崩溃（真实表）", descs.size() == 39)
	_assert("I2: 表文件不存在 → {} 不崩溃",
			PrimitivesA._load_table("res://data/systems/spirit_ai/__no_such_table__.json").is_empty())
	var bad_path: String = "user://wave_a_bad_json_test.json"
	var f: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("{ this is not valid json !!!")
	f.close()
	_assert("I3: 坏 JSON → {} 不崩溃", PrimitivesA._load_table(bad_path).is_empty())
	DirAccess.remove_absolute(bad_path)
	_assert("I4: resolve_target_mode 空 descriptor → none", PrimitivesA.resolve_target_mode({}, sad) == "none")
	var tm: String = PrimitivesA.resolve_target_mode(descs["player_atk_down_pct"], sad)
	_assert("I5: resolve_target_mode 静态读表", tm == "enemy_visible")

	# ===== R-纪律：源码无随机函数调用（注释中的禁令字样不算，查调用形态）=====
	var src: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai/primitives_a.gd")
	_assert("R1: primitives_a.gd 源码无 randf/randf_range 调用",
			src.find("randf(") == -1 and src.find("randf_range") == -1)
	_assert("R2: primitives_a.gd 源码无 randi 调用", src.find("randi(") == -1)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 波A套件全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func _load_registry() -> Dictionary:
	var out: Dictionary = {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if parsed is Dictionary:
		for tag in parsed.get("tags", []):
			out[str(tag["id"])] = tag
	return out


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for v in b:
		if not (v in a):
			return false
	return true
