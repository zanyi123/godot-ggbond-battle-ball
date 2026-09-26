## 14号工单诊断仪：外场（流放）球员技能AI决策链各环节统计（布场窗口交付）
## 只读诊断：零游戏代码改动、零配置文件改动。
## 三层证据：①镜像决策链分段计数（现状=开关全关）②端到端 _decide_skill 对账
## ③开关开启探针：直调各波 primitives timing_gate 模拟开波后闸门存活（不碰 switches.json）。
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_outer_skill_ai_diagnosis.gd
extends SceneTree

const RealSpiritSys = preload("res://scripts/systems/spirit_system/spirit_system_manager.gd")
const SKILLS_JSON := "res://data/spirits/skills.json"
const CYCLES := 20
## 外场隔离区几何（battle_manager._build_penalty_enclosure 实测）：
## 队a=右外场凹字形 x∈[250,510] y∈[-325,325]；队b 镜像。本诊断取队a中心 (380,0)。
const EXILE_POS := Vector2(380, 0)
const WAVE_FILES := {
	"A": "res://data/systems/spirit_ai/primitives_a.json",
	"B": "res://data/systems/spirit_ai/primitives_b.json",
	"C": "res://data/systems/spirit_ai/primitives_c.json",
	"D": "res://data/systems/spirit_ai/primitives_d.json",
}

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var facing_direction: Vector2 = Vector2.LEFT
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var attack_power: float = 50.0
	var defense: float = 50.0
	var speed: float = 50.0
	var resilience: float = 50.0


class StubBall extends Area2D:
	var owner_player: Node2D = null
	var is_active: bool = false
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0


class StubSpiritSystem extends RealSpiritSys:
	var calls: Array = []
	func use_skill(player_id: int, skill_id: String, target_data: Dictionary = {}) -> bool:
		calls.append(skill_id)
		return true
	func get_skill_cooldown(player_id: int, skill_id: String) -> float:
		return 0.0
	func get_player_skills(_player_id: int) -> Array:
		return []


## 镜像 _decide_skill(:739-786) 的分段计数器
class StageStats:
	var cycles: int = 0
	var s0_valid: int = 0
	var s1_energy: int = 0
	var s2_think: int = 0
	var s3_avail_skill_slots: int = 0
	var s4_gated_skill_slots: int = 0
	var s5_scored: int = 0
	var s7_exec: int = 0
	var casts: Array = []


func _initialize() -> void:
	_run()


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ " + test_name)
	else:
		_fail += 1
		print("  ❌ " + test_name)


func _load_real_skills() -> Array:
	var text := FileAccess.get_file_as_string(SKILLS_JSON)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("skills", null)) == TYPE_ARRAY:
		return parsed["skills"]
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


## 开关开启探针的 tag→(descriptor, primitives脚本) 映射（聚合四波表，不碰 switches.json）
func _load_tag_probe() -> Dictionary:
	var probe: Dictionary = {}
	for wave in WAVE_FILES.keys():
		var path: String = WAVE_FILES[wave]
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var script: GDScript = load("res://scripts/battle/spirit_ai/primitives_%s.gd" % str(wave).to_lower())
		if script == null:
			continue
		var descriptors: Dictionary = parsed.get("descriptors", {})
		for tag_id in descriptors.keys():
			probe[str(tag_id)] = {"descriptor": descriptors[tag_id], "script": script, "wave": str(wave)}
	return probe


func _make_player(id: String, team: String, pos: Vector2, facing: Vector2) -> StubPlayer:
	var p: StubPlayer = StubPlayer.new()
	p.character_id = id
	p.team = team
	p.position = pos
	p.facing_direction = facing
	return p


func _run() -> void:
	print("\n========== 14诊断：外场（流放）球员技能AI决策链统计 ==========\n")
	for i in range(3):
		await process_frame
	# 看门狗：运行时错误会跳过 _finish 的 quit()，90s 强制退出防挂死
	create_timer(90.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG：诊断超时强退（存在未捕获脚本错误，见上方 ERROR）")
		quit(3))

	var sam_script: GDScript = load("res://scripts/battle/spirit_ai_manager.gd")
	var aim_script: GDScript = load("res://scripts/battle/ai_manager.gd")
	var profile_script: GDScript = load("res://scripts/battle/ai_profile.gd")

	var skills: Array = _load_real_skills()
	_assert("实表技能载入（>=10）", skills.size() >= 10)
	var probe: Dictionary = _load_tag_probe()
	print("[探针] 四波描述符聚合 %d tag" % probe.size())

	# ===== 场景骨架（队a流放者+队友+敌持球者+敌2）=====
	var exile: StubPlayer = _make_player("t_diag_exile", "a", EXILE_POS, Vector2(-1, 0))
	exile.is_penalized = true
	root.add_child(exile)
	var mate: StubPlayer = _make_player("t_diag_mate", "a", Vector2(0, 100), Vector2.RIGHT)
	root.add_child(mate)
	var e_carrier: StubPlayer = _make_player("t_diag_ecarrier", "b", Vector2(0, 0), Vector2.RIGHT)
	e_carrier.is_carrying_ball = true
	root.add_child(e_carrier)
	var e2: StubPlayer = _make_player("t_diag_e2", "b", Vector2(150, -80), Vector2.RIGHT)
	root.add_child(e2)

	var aim: Node = aim_script.new()
	var profile = profile_script.new()
	var ap_exile: Dictionary = {"player": exile, "profile": profile}
	var ap_mate: Dictionary = {"player": mate, "profile": profile}
	var ap_e1: Dictionary = {"player": e_carrier, "profile": profile}
	var ap_e2: Dictionary = {"player": e2, "profile": profile}
	var aps: Array[Dictionary] = [ap_exile, ap_mate, ap_e1, ap_e2]
	aim.ai_players = aps

	var ball: StubBall = StubBall.new()
	ball.position = Vector2(0, 0)
	root.add_child(ball)

	print("[环境] field_of_view=%.0f vision_range=%.0f(ctx闸无距离上限/感知层有) 隔离区中心=(380,0) 敌距=%.0fpx 开关=全关(交付态)" % [
		float(profile.field_of_view), float(profile.vision_range), EXILE_POS.distance_to(Vector2(0, 0))])

	# ===== 场景矩阵 =====
	var scenarios: Array = [
		{"name": "S1战败流放+敌持球+面向场内(主人报障)", "defeated": true, "ball": "enemy_carry", "facing": Vector2(-1, 0), "filter": "all"},
		{"name": "S2违规流放+敌持球+面向场内", "defeated": false, "ball": "enemy_carry", "facing": Vector2(-1, 0), "filter": "all"},
		{"name": "S3违规流放+敌持球+面向墙", "defeated": false, "ball": "enemy_carry", "facing": Vector2(1, 0), "filter": "all"},
		{"name": "S4违规流放+己方持球+面向场内", "defeated": false, "ball": "team_carry", "facing": Vector2(-1, 0), "filter": "all"},
		{"name": "S5违规流放+球飞行+面向场内", "defeated": false, "ball": "flight", "facing": Vector2(-1, 0), "filter": "all"},
		{"name": "S6违规流放+球空闲+面向场内", "defeated": false, "ball": "idle", "facing": Vector2(-1, 0), "filter": "all"},
		{"name": "S7违规流放+敌持球+无场地技元灵(金刚类)+面向场内", "defeated": false, "ball": "enemy_carry", "facing": Vector2(-1, 0), "filter": "no_field"},
	]

	var results: Dictionary = {}
	for sc in scenarios:
		results[str(sc["name"])] = _run_scenario(sam_script, profile, skills, aim, ball, exile, mate, e_carrier, e2, sc, probe)

	# ===== 诊断结论断言 =====
	# 2026-09-27 集成窗口按 14a提案§四1/2/4/5 完成 RC0/RC1/RC3/视距护栏修复（裁定d）后，
	# D1/D1b/D3/D4 由"缺陷存在"诊断断言翻转为修复后语义（14§六验收1：S1 应进入且出手）
	var s1r: Dictionary = results["S1战败流放+敌持球+面向场内(主人报障)"]
	var s1: StageStats = s1r["mirror"]
	_assert("D1(修复后) 战败流放与内场同权：决策循环进入（%d/%d）" % [int(s1.s0_valid), CYCLES], int(s1.s0_valid) > 0)
	_assert("D1b(修复后) 战败流放端到端可出手（含调用方闸镜像）", not (s1r["e2e_calls"] as Array).is_empty())
	var s2r: Dictionary = results["S2违规流放+敌持球+面向场内"]
	var s2: StageStats = s2r["mirror"]
	_assert("D2 现状反直觉证据：违规流放+开关全关走旧评分路径，隔离区内实际连放技能（%d次/%d周期）" % [int(s2.s7_exec), CYCLES], int(s2.s7_exec) > 0)
	var s3r: Dictionary = results["S3违规流放+敌持球+面向墙"]
	# 视距护栏后：面向场内只剩 243px 的 e2（380px 敌持球者 > vision_range 被滤除），面向墙仍 0
	_assert("D3(修复后) 视距护栏：面向墙 visible=0，面向场内=%d（380px敌持球者越界被滤，243px保留）" % int(s2r["visible_n"]), int(s3r["visible_n"]) == 0 and int(s2r["visible_n"]) == 1)
	var s7: StageStats = results["S7违规流放+敌持球+无场地技元灵(金刚类)+面向场内"]["mirror"]
	# RC1 修复后：流放球员 think 无条件放行（原"无场地技元灵 think 全灭"缺陷消除）
	_assert("D4(修复后) 流放球员think全放行（%d/%d，RC1裁定d）" % [int(s7.s2_think), CYCLES], int(s7.s2_think) == CYCLES)
	var s4: StageStats = results["S4违规流放+己方持球+面向场内"]["mirror"]
	_assert("D5 己方持球时think全放行（%d/%d）" % [int(s4.s2_think), CYCLES], int(s4.s2_think) == CYCLES)

	# 开关开启探针结论（开波后世界的闸门存活预测）
	var probe_matrix: Dictionary = results["S2违规流放+敌持球+面向场内"]["probe_by_skill"]
	var leihuo1: int = int(probe_matrix.get("skill_雷火_1", 0))
	var caomu1: int = int(probe_matrix.get("skill_草木_1", 0))
	_assert("D6 探针·开波后：持球闸技能（雷火_1等）外场全灭（would-pass=%d）" % leihuo1, leihuo1 == 0)
	_assert("D7 探针·开波后：自护闸技能满血态全灭（草木_1 would-pass=%d）→ 外场自护时机缺口坐实" % caomu1, caomu1 == 0)

	_finish()


func _run_scenario(sam_script: GDScript, profile, skills: Array, aim: Node, ball: StubBall, exile: StubPlayer, mate: StubPlayer, e_carrier: StubPlayer, e2: StubPlayer, sc: Dictionary, probe: Dictionary) -> Dictionary:
	exile.is_defeated = bool(sc["defeated"])
	exile.facing_direction = sc["facing"]
	exile.spirit_energy = 100.0
	e_carrier.is_carrying_ball = bool(str(sc["ball"]) == "enemy_carry")
	mate.is_carrying_ball = bool(str(sc["ball"]) == "team_carry")
	ball.owner_player = e_carrier if str(sc["ball"]) == "enemy_carry" else (mate if str(sc["ball"]) == "team_carry" else null)
	ball.is_active = bool(str(sc["ball"]) == "flight")

	var sam: Node = sam_script.new()
	sam.ai_manager = aim
	var stub_sys: StubSpiritSystem = StubSpiritSystem.new()
	sam.spirit_system = stub_sys
	sam.ball_node = ball
	var pa: Dictionary = sam._analyze_player_attributes(exile)
	print("[调试] pa类型=%d skills=%d" % [typeof(pa), skills.size()])
	var analyses: Array[Dictionary] = []
	for sd in skills:
		if typeof(sd) != TYPE_DICTIONARY:
			print("[调试] 非dict技能元素 type=%d" % typeof(sd))
			continue
		var analysis: Dictionary = sam._analyze_single_skill(sd, pa)
		analysis["skill_id"] = str(sd.get("id", "?"))
		analysis["skill_data"] = sd
		if str(sc["filter"]) == "no_field" and bool(analysis.get("has_field_tag", false)):
			continue
		analyses.append(analysis)

	var sad: Dictionary = {
		"player": exile, "profile": profile, "skill_decide_count": 0, "skill_exec_count": 0,
		"skills_analysis": analyses, "last_skill_use_time": 0.0,
	}

	var st: StageStats = StageStats.new()
	for i in range(CYCLES):
		sad["skill_decide_count"] = int(sad["skill_decide_count"]) + 1
		st.cycles += 1
		if not sam._is_valid(sad):
			continue
		st.s0_valid += 1
		if exile.spirit_energy < profile.skill_energy_min:
			continue
		st.s1_energy += 1
		if not sam._should_think_about_skills(sad):
			continue
		st.s2_think += 1
		var available: Array = sam._get_available_skills(sad)
		st.s3_avail_skill_slots += available.size()
		var scored: Array[Dictionary] = []
		var ctx_box: Dictionary = {}
		for skill_info in available:
			var gate: Dictionary = sam._evaluate_primitive_gates(sad, skill_info, ctx_box)
			if bool(gate.get("gated", false)):
				st.s4_gated_skill_slots += 1
			var score: float = sam._compute_skill_score(sad, skill_info)
			if bool(gate.get("gated", false)):
				score *= float(gate.get("bonus", 1.0))
			if score > 0:
				st.s5_scored += 1
				scored.append({"skill": skill_info, "score": score})
		if scored.is_empty():
			continue
		var best: Dictionary = sam._select_skill_with_softmax(sad, scored, profile.skill_selection_temperature)
		if best and float(best["score"]) >= profile.skill_use_threshold:
			var calls_before: int = stub_sys.calls.size()
			sam._execute_skill(sad, best["skill"])
			if stub_sys.calls.size() > calls_before:
				st.casts.append(str(stub_sys.calls[stub_sys.calls.size() - 1]))
				st.s7_exec += 1

	var calls_after_mirror: int = stub_sys.calls.size()

	# 端到端对账（独立 sad；镜像真实调用方：think循环先 _is_valid 再 _decide_skill）
	var sad2: Dictionary = {
		"player": exile, "profile": profile, "skill_decide_count": 0, "skill_exec_count": 0,
		"skills_analysis": analyses, "last_skill_use_time": 0.0,
	}
	for i in range(CYCLES):
		if sam._is_valid(sad2):
			sam._decide_skill(sad2)
	var e2e_calls: Array = stub_sys.calls.slice(calls_after_mirror)

	# ctx 快照 + 开关开启探针（直调各波 timing_gate，模拟开波后闸门存活）
	var ctx: Dictionary = sam._build_primitive_ctx(sad)
	var visible_n: int = (ctx.get("visible_enemies", []) as Array).size()
	var probe_by_skill: Dictionary = {}
	for skill_info in analyses:
		var would_pass: int = 0
		for tag in skill_info.get("raw_tags", []) as Array:
			var hit: Dictionary = probe.get(str(tag), {})
			if hit.is_empty():
				continue
			var gr: Dictionary = (hit["script"] as GDScript).timing_gate(hit["descriptor"], sad, ctx)
			if bool(gr.get("ok", false)):
				would_pass += 1
		probe_by_skill[str(skill_info["skill_id"])] = would_pass

	print("\n[场景] %s" % str(sc["name"]))
	print("  S0入环 %d/%d → S1能量 %d → S2think %d → S3可用槽 %d → S4闸评槽 %d → S5正分 %d → S7出手 %d %s" % [
		st.s0_valid, st.cycles, st.s1_energy, st.s2_think, st.s3_avail_skill_slots,
		st.s4_gated_skill_slots, st.s5_scored, st.s7_exec,
		("casts=" + str(st.casts)) if not st.casts.is_empty() else ""])
	print("  ctx快照: visible_enemies=%d enemy_carrier_visible=%s ball_in_flight=%s" % [
		visible_n, str(ctx.get("enemy_carrier_visible", false)), str(ctx.get("ball_in_flight", false))])

	return {"mirror": st, "e2e_calls": e2e_calls, "visible_n": visible_n, "probe_by_skill": probe_by_skill}


func _finish() -> void:
	print("\n========== 诊断结论: %d/%d 断言成立 ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 存在与预期不符的环节——见上方分段表")
	else:
		print("🎉 诊断链路完整（详见14a报告）")
	quit(1 if _fail > 0 else 0)
