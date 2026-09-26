## 11号工单诊断仪器：三大分类运用缺陷——漏斗量化 + 断点定位（只读诊断，零热文件改动）
## 工单：元灵技能AI规划/11_三大分类运用缺陷修复工单.md §二（嫌疑a/b/d 漏斗统计 + 嫌疑c 执行链）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_class3_usage_diagnosis.gd
## 纪律：开关注入走 user:// 临时文件，结束恢复；本套件断言=诊断结论锚点（防回归漂移）
extends SceneTree

const RegistryScript = preload("res://scripts/battle/spirit_ai/primitive_registry.gd")
const SWITCHES_REAL := "res://data/systems/spirit_ai/switches.json"
const SWITCHES_TMP := "user://switches_diag_tmp.json"

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_carrying_ball: bool = false
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _write_switches(content: String) -> void:
	var f = FileAccess.open(SWITCHES_TMP, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	RegistryScript.reload_switches(SWITCHES_TMP)


func _make_player(team: String = "b", carrying: bool = false, pos: Vector2 = Vector2(60, 0), stamina_ratio: float = 1.0) -> StubPlayer:
	var e = StubPlayer.new()
	e.team = team
	e.is_carrying_ball = carrying
	e.position = pos
	e.stamina = 100.0 * stamina_ratio
	return e


func _run() -> void:
	print("\n========== 11号工单诊断：三大分类运用漏斗 ==========\n")
	for i in range(3):
		await process_frame

	# 开全（诊断态：所有波描述符可查）
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true, \"C\": true, \"D\": true}}")

	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	sam.ai_manager = null
	sam.ball_node = null
	sam.battle_manager = null

	var skills_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/spirits/skills.json"))["skills"]
	var by_id: Dictionary = {}
	for s in skills_json:
		if s is Dictionary:
			by_id[str(s.get("id", ""))] = s

	# ===== 漏斗第1环：原语计价（嫌疑b：评分 vs 阈值15，难度normal）=====
	print("[漏斗1] base_value（原语计价，实配参数）vs 阈值15（normal）")
	var cases := [
		["skill_大地_1", "field_obs_add"],
		["skill_草木_2", "field_obs_add"],
		["skill_雷火_4", "field_zone_danger"],
		["skill_草木_1", "player_hp_regen"],
		["skill_梦幻_1", "player_stealth"],
		["skill_雷火_3", "player_root"],
		["skill_雷火_1", "ball_dmg_up_pct"],
	]
	var base_values: Dictionary = {}
	for c in cases:
		var sd: Dictionary = by_id[str(c[0])]
		var tp: Dictionary = sd.get("tag_params", {})
		var tags: Array[String] = []
		if str(c[1]).begins_with("field"):
			tags = ["on_field"] as Array[String]
		elif str(c[1]).begins_with("ball"):
			tags = ["on_ball"] as Array[String]
		else:
			tags = ["on_player"] as Array[String]
		var bv: float = sam._compute_base_value(tags, tp, int(sd.get("energy_cost", 20)), float(sd.get("cooldown", 10.0)))
		base_values[str(c[0])] = bv
		var gate_list: Array = []
		for tag_id in tp:
			var hit: Dictionary = sam._query_primitive(str(tag_id))
			if not hit.is_empty():
				gate_list.append(str(hit["descriptor"].get("timing_gate", "?")))
		print("  %s → base=%.1f 阈值15 %s | gate=%s" % [c[0], bv, "≥✓" if bv >= 15.0 else "<✗", str(gate_list)])

	_check(float(base_values["skill_大地_1"]) >= 15.0, "F1 大地_1 计价≥阈值15（评分非根因）实测%.1f" % float(base_values["skill_大地_1"]))
	_check(float(base_values["skill_草木_1"]) >= 15.0, "F2 草木_1 计价≥阈值15 实测%.1f" % float(base_values["skill_草木_1"]))

	# ===== 漏斗第2环：闸门场景矩阵（嫌疑a：场景难触发）=====
	print("[漏斗2] 闸门场景矩阵（ok/bonus）")
	var caster = _make_player("a", false, Vector2.ZERO)
	var scenarios := [
		["S1 敌持球近(60px)", [_make_player("b", true, Vector2(60, 0))]],
		["S2 敌持球远(300px)", [_make_player("b", true, Vector2(300, 0))]],
		["S3 敌可见未持球", [_make_player("b", false, Vector2(100, 0))]],
		["S4 无敌满血", []],
		["S5 无敌自残血", []],
		["S6 持球+敌持球近", [_make_player("b", true, Vector2(60, 0))]],
	]
	var skill_tags: Dictionary = {
		"skill_大地_1": ["field_obs_add"],
		"skill_雷火_4": ["field_zone_danger"],
		"skill_草木_1": ["player_hp_regen", "player_def_up_pct"],
		"skill_梦幻_1": ["player_stealth", "player_spd_up_pct"],
		"skill_雷火_3": ["player_root"],
	}
	for si in range(scenarios.size()):
		var enemies: Array = scenarios[si][1]
		var stamina_ratio := 1.0
		if si == 4:
			stamina_ratio = 0.3
		var carrying := si == 5
		var sad := {"player": (caster if not carrying else _make_player("a", true, Vector2.ZERO))}
		var ctx_box := {"ctx": {
			"player": sad["player"], "visible_enemies": enemies,
			"stamina_ratio": stamina_ratio, "energy_ratio": 1.0,
			"has_energy_blocked_burst": false, "threat_radius": 200.0,
		}}
		var line := "  " + str(scenarios[si][0]) + " :"
		for skill_id in skill_tags:
			var g: Dictionary = sam._evaluate_primitive_gates(sad, {"raw_tags": skill_tags[skill_id]}, ctx_box)
			line += " %s=%s/%.2f" % [skill_id.substr(7), ("过" if bool(g.get("ok", false)) else "拒"), float(g.get("bonus", 1.0))]
		print(line)

	# 诊断锚点断言（结论防漂移）
	var ctx_carrier := {"ctx": {"player": caster, "visible_enemies": [_make_player("b", true, Vector2(300, 0))], "stamina_ratio": 1.0, "energy_ratio": 1.0, "has_energy_blocked_burst": false, "threat_radius": 200.0}}
	var g_wall: Dictionary = sam._evaluate_primitive_gates({"player": caster}, {"raw_tags": ["field_obs_add"]}, ctx_carrier)
	_check(bool(g_wall.get("ok", false)), "F3 大地_1 闸门：敌持球可见即放行（gate 非根因）")
	var ctx_noenemy := {"ctx": {"player": caster, "visible_enemies": [], "stamina_ratio": 1.0, "energy_ratio": 1.0, "has_energy_blocked_burst": false, "threat_radius": 200.0}}
	var g_wall2: Dictionary = sam._evaluate_primitive_gates({"player": caster}, {"raw_tags": ["field_obs_add"]}, ctx_noenemy)
	_check(not bool(g_wall2.get("ok", true)), "F4 大地_1 闸门：无敌可见拒放（enemy_carrying_visible 语义）")

	# ===== 漏斗第3环：执行链审计（嫌疑c：放置流）=====
	print("[漏斗3] 执行链（代码审计锚点）")
	var route_src := FileAccess.get_file_as_string("res://scripts/systems/spirit_system/handler/field_route.gd")
	var placer_src := FileAccess.get_file_as_string("res://scripts/battle/field_zone_placer.gd")
	var trigger_src := FileAccess.get_file_as_string("res://scripts/systems/spirit_system/spirit_skill_trigger.gd")
	_check(route_src.contains("manager.start_placing(params, mouse_ops)"), "C1 field_obs_add 路由=start_placing（鼠标交互放置模式）")
	_check(not route_src.contains("_target_data"), "C2 field_route 全文零 _target_data 消费（AI 传入 field_position 被丢弃）")
	_check(placer_src.contains("MOUSE_BUTTON_LEFT") and placer_src.contains("_on_left_click"), "C3 placer 仅鼠标左键生成障碍（AI 无鼠标=永不落地）")
	_check(trigger_src.contains("params[\"_target_data\"] = target_data"), "C4 trigger 注入 _target_data（数据到 handler 即断）")
	_check(route_src.contains("spawn_at == \"ball_land\""), "C5 zone_danger 有 ball_land 自动路径（雷火_4 不受 C1-C3 影响）")

	# ===== 能量环（嫌疑d）=====
	print("[漏斗4] 能量/冷却")
	for c in cases:
		var sd: Dictionary = by_id[str(c[0])]
		var ec := float(sd.get("energy_cost", 20))
		var cd := float(sd.get("cooldown", 10.0))
		print("  %s energy_cost=%.0f cooldown=%.1f（初始能量100/min10 → 无卡口）" % [c[0], ec, cd])
	_check(float(by_id["skill_大地_1"].get("energy_cost", 99)) <= 20.0, "F5 大地_1 能量门槛≤20（能量非根因）")

	# ===== 恢复 =====
	RegistryScript.reload_switches(SWITCHES_REAL)
	print("\n========== 诊断结论锚点：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	print("""
【诊断结论（证据链）】
  根因=c 放置流断裂：AI 决策面畅通（计价/闸门/能量全部无卡口，F1~F5），
  use_skill 返回成功并进鼠标放置模式，但 placer 只认鼠标左键（C3），
  handler 全文不消费 _target_data.field_position（C2）→ AI 放墙/清除类必然永不落地。
  旁证：雷火_4 走 spawn_at=ball_land 自动路径（C5），预期 sim 有释放记录。
  修复方向（待规划窗口确认）：AI 非交互放置路径——field_position 经 _target_data
  传入时直接生成（跳过鼠标模式），落点用 manager.create/直接构造，1-3 文件内闭环。
""")
	quit(1 if _fail > 0 else 0)
