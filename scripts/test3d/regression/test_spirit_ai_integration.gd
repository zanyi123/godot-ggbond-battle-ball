## 集成接线工单验收：spirit_ai_manager 原语层接线（06§五集成契约，2026-09-26 集成窗口）
## 覆盖：registry波次查询 / 价值原语路径（开/关/混合波/部分覆盖/clamp）/ 闸门OR语义与bonus取大 /
## intent校准 / ctx组装（Q5/Q7/Q8键）/ pre_burst / 场地放置委托与fail-closed / 全关零扰动（逐位=旧公式）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_integration.gd
## 纪律：开关注入走 user:// 临时文件（零仓库污染），结束恢复真实开关态（08工单测试矩阵同款）
extends SceneTree

const RegistryScript = preload("res://scripts/battle/spirit_ai/primitive_registry.gd")
const RealSpiritSys = preload("res://scripts/systems/spirit_system/spirit_system_manager.gd")
const SWITCHES_REAL := "res://data/systems/spirit_ai/switches.json"
const SWITCHES_TMP := "user://switches_itest_tmp.json"

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


class StubBall extends Area2D:
	var is_active: bool = false
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0


class StubAIManager extends Node:
	var ai_players: Array = []   # [{player: Node}] 同 manager._get_team_members 消费形态


class StubSpiritSystem extends RealSpiritSys:
	var cooldown_table: Dictionary = {}
	func get_skill_cooldown(player_id: int, skill_id: String) -> float:
		return float(cooldown_table.get(skill_id, 0.0))


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


func _restore_switches() -> void:
	RegistryScript.reload_switches(SWITCHES_REAL)


func _make_manager() -> Node:
	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	sam.ai_manager = null
	sam.ball_node = null
	sam.battle_manager = null
	return sam


func _run() -> void:
	print("\n========== 集成接线工单：原语层接线验收 ==========\n")
	for i in range(3):
		await process_frame

	var sam = _make_manager()

	# ===== S 组：registry 波次查询（get_descriptor_entry）=====
	print("[S] registry 波次查询")
	_restore_switches()
	_check(RegistryScript.get_descriptor_entry("ball_dmg_up_pct").is_empty(), "S1 全关(真实开关)时 entry 返回空")
	_check(RegistryScript.get_descriptor("ball_dmg_up_pct").is_empty(), "S2 全关时 get_descriptor 同样为空(口径一致)")

	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true}}")
	var entry: Dictionary = RegistryScript.get_descriptor_entry("ball_dmg_up_pct")
	_check(not entry.is_empty() and str(entry.get("wave", "")) == "A", "S3 开波A后 entry 命中且 wave=A")
	_check(str(entry.get("descriptor", {}).get("timing_gate", "")) == "ball_hold_engage", "S4 entry.descriptor 内容正确")
	_check(not RegistryScript.get_descriptor("ball_dmg_up_pct").is_empty(), "S5 get_descriptor 与 entry 口径一致")

	_write_switches("{\"master_enabled\": true, \"waves\": {\"B\": true}}")
	_check(RegistryScript.get_descriptor_entry("ball_dmg_up_pct").is_empty(), "S6 仅开B时波A标签 entry 为空")
	_check(str(RegistryScript.get_descriptor_entry("player_root").get("wave", "")) == "B", "S7 波B标签 entry 命中 wave=B")

	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true, \"C\": true, \"D\": true}}")
	_check(str(RegistryScript.get_descriptor_entry("ball_range_up").get("wave", "")) == "C", "S8 波C标签 entry 命中 wave=C")
	_check(str(RegistryScript.get_descriptor_entry("field_obs_add").get("wave", "")) == "D", "S9 波D标签 entry 命中 wave=D")

	# ===== V 组：价值原语路径（manager._compute_base_value）=====
	print("[V] 价值原语路径")
	# 全关：逐位=旧公式（雷火_1 同参：45+1.4=46.4, eff=46.4/25, cd=1.25 → 29+9.28=38.28）
	_restore_switches()
	var legacy1: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 30.0}}, 20, 10.0)
	_check(is_equal_approx(legacy1, 33.75), "V1 全关=旧公式逐位(45×0.5+2.25×5=33.75) 实测%.4f" % legacy1)
	var legacy2: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.4}}, 25, 8.0)
	_check(is_equal_approx(legacy2, 38.28), "V2 全关=旧公式逐位(双标签雷火_1同参=38.28) 实测%.4f" % legacy2)

	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true}}")
	var v1: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 30.0}}, 20, 10.0)
	_check(is_equal_approx(v1, 45.0), "V3 波A命中：30×1.5=45(权重1) 实测%.4f" % v1)
	var v2: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 100.0}}, 20, 10.0)
	_check(is_equal_approx(v2, 90.0), "V4 clamp上限：100×1.5=150→cap90 实测%.4f" % v2)
	var v3: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {}}, 20, 10.0)
	_check(is_equal_approx(v3, 15.0), "V5 缺参数回落 value_min=15 实测%.4f" % v3)
	var v4: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 30.0}, "ball_speed_up_pct": {"multiplier": 1.4}}, 25, 8.0)
	_check(is_equal_approx(v4, 60.9), "V6 双标签权重0.7：(45+42)×0.7=60.9 实测%.4f" % v4)
	# 部分覆盖：C 未开时 ball_range_up 按未知标签缺省 10 计
	var v5: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 20.0}, "ball_range_up": {"damage_pct": 10.0}}, 20, 10.0)
	_check(is_equal_approx(v5, 28.0), "V7 部分覆盖：A命中30+未命中10 → 40×0.7=28 实测%.4f" % v5)
	# 混合波（A+B 同技能，冰雪_1 同参）：dmg_down 20×0.8=16 + move_slow 1.5×10=15 → 31×0.7=21.7
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true}}")
	var v6: float = sam._compute_base_value(["on_player", "on_ball"] as Array[String], {"ball_dmg_down_pct": {"value": 20.0}, "player_move_slow": {"multiplier": 1.5, "duration": 3.0}}, 22, 9.0)
	_check(is_equal_approx(v6, 21.7), "V8 A+B混合波逐标签分发：(16+15)×0.7=21.7 实测%.4f" % v6)

	# ===== G 组：闸门 OR 语义与 bonus 取大 =====
	print("[G] 时机闸门")
	_restore_switches()
	var stub = StubPlayer.new()
	stub.position = Vector2.ZERO
	var sad_ctx := {"player": stub}
	var box_off: Dictionary = {"ctx": {"player": stub, "visible_enemies": [], "stamina_ratio": 1.0}}
	var g0: Dictionary = sam._evaluate_primitive_gates(sad_ctx, {"raw_tags": ["player_root"]}, box_off)
	_check(not bool(g0.get("gated", true)), "G1 全关：闸门不参与(gated=false)")

	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true}}")
	var carrier = StubPlayer.new()
	carrier.is_carrying_ball = true
	carrier.position = Vector2(60, 0)
	var far_enemy = StubPlayer.new()
	far_enemy.position = Vector2(500, 0)

	var box_no_vis: Dictionary = {"ctx": {"player": stub, "visible_enemies": [], "stamina_ratio": 1.0}}
	var g1: Dictionary = sam._evaluate_primitive_gates(sad_ctx, {"raw_tags": ["player_root"]}, box_no_vis)
	_check(bool(g1.get("gated", false)) and not bool(g1.get("ok", true)), "G1b 波B root闸门：无可见持球敌 → 放行失败")

	var box_carrier: Dictionary = {"ctx": {"player": stub, "visible_enemies": [carrier], "stamina_ratio": 1.0}}
	var g2: Dictionary = sam._evaluate_primitive_gates(sad_ctx, {"raw_tags": ["player_root"]}, box_carrier)
	_check(bool(g2.get("gated", false)) and bool(g2.get("ok", false)) and is_equal_approx(float(g2.get("bonus", 0)), 1.0), "G2 可见持球敌 → root 放行 bonus=1.0")

	# OR + 取大：def_up(self_threatened) + dmg_up(ball_hold_engage) 双A标签
	var skill2 := {"raw_tags": ["player_def_up_pct", "ball_dmg_up_pct"]}
	var box_calm: Dictionary = {"ctx": {"player": stub, "visible_enemies": [], "stamina_ratio": 1.0}}
	var g3: Dictionary = sam._evaluate_primitive_gates(sad_ctx, skill2, box_calm)
	_check(bool(g3.get("gated", false)) and not bool(g3.get("ok", true)), "G3 双标签全不过 → ok=false")
	var box_far: Dictionary = {"ctx": {"player": stub, "visible_enemies": [far_enemy], "stamina_ratio": 1.0}}
	var stub_carry = StubPlayer.new()
	stub_carry.is_carrying_ball = true
	var sad_carry := {"player": stub_carry}
	var box_far_carry: Dictionary = {"ctx": {"player": stub_carry, "visible_enemies": [far_enemy], "stamina_ratio": 1.0}}
	var g4: Dictionary = sam._evaluate_primitive_gates(sad_carry, skill2, box_far_carry)
	_check(bool(g4.get("gated", false)) and bool(g4.get("ok", false)) and is_equal_approx(float(g4.get("bonus", 0)), 1.0), "G4 OR放行：持球+远敌 → ball_hold_engage 过 bonus=1.0")
	var box_close_carry: Dictionary = {"ctx": {"player": stub_carry, "visible_enemies": [carrier], "stamina_ratio": 1.0}}
	var g5: Dictionary = sam._evaluate_primitive_gates(sad_carry, skill2, box_close_carry)
	_check(bool(g5.get("ok", false)) and is_equal_approx(float(g5.get("bonus", 0)), 1.25), "G5 bonus取大：敌贴脸60px → self_threatened 强触发1.25")

	# ===== I 组：ctx 组装 + pre_burst =====
	print("[I] ctx 组装")
	var stub_sys = StubSpiritSystem.new()
	sam.spirit_system = stub_sys
	var stub_ai = StubAIManager.new()
	var ally = StubPlayer.new()
	ally.max_stamina = 100.0
	ally.stamina = 20.0
	stub_ai.ai_players = [{"player": ally}]
	sam.ai_manager = stub_ai
	var low_stub = StubPlayer.new()
	low_stub.stamina = 50.0
	low_stub.max_stamina = 100.0
	low_stub.spirit_energy = 30.0
	low_stub.max_spirit_energy = 100.0
	var sad_full := {
		"player": low_stub,
		"skills_analysis": [{"skill_id": "s1", "base_value": 40.0, "skill_data": {"type": "active", "energy_cost": 20}}],
	}
	var ctx: Dictionary = sam._build_primitive_ctx(sad_full)
	_check(is_equal_approx(float(ctx.get("stamina_ratio", 0)), 0.5) and is_equal_approx(float(ctx.get("energy_ratio", 0)), 0.3), "I1 体力/能量比值正确")
	_check(ctx.get("visible_enemies", ["x"]).is_empty(), "I2 stub无感知口：fov fail-closed 空表")
	_check(ctx.get("own_goal", Vector2.ZERO) == Vector2(300, 0) and ctx.get("enemy_goal", Vector2.ZERO) == Vector2(-300, 0), "I3 a队球门键正确(GOAL_A/GOAL_B)")
	_check(not ctx.has("ball_position") and not ctx.has("ball_in_flight"), "I4 无球时省略球面键(fail-closed)")
	var ratios: Array = ctx.get("ally_stamina_ratios", [])
	_check(ratios.size() == 1 and is_equal_approx(float(ratios[0]), 0.2), "I6 队友比值表(ally_stamina_ratios)=0.2")
	var allies_arr: Array = ctx.get("allies", [])
	_check(allies_arr.size() == 1 and is_instance_valid(allies_arr[0].get("player")) and is_equal_approx(float(allies_arr[0].get("stamina_ratio", 0)), 0.2), "I7 队友字典表(allies)双形态同源")
	_check(not bool(ctx.get("has_energy_blocked_burst", true)), "I8 最高分技能可用 → pre_burst=false")
	low_stub.spirit_energy = 10.0
	var ctx2: Dictionary = sam._build_primitive_ctx(sad_full)
	_check(bool(ctx2.get("has_energy_blocked_burst", false)), "I9 能量不足(cost 20 > 10) → pre_burst=true")
	low_stub.spirit_energy = 30.0
	stub_sys.cooldown_table = {"s1": 5.0}
	var ctx3: Dictionary = sam._build_primitive_ctx(sad_full)
	_check(bool(ctx3.get("has_energy_blocked_burst", false)), "I10 最高分技能冷却中 → pre_burst=true")
	stub_sys.cooldown_table = {}
	var stub_ball = StubBall.new()
	stub_ball.is_active = true
	stub_ball.ball_direction = Vector2.LEFT
	stub_ball.ball_speed = 400.0
	sam.ball_node = stub_ball
	var ctx4: Dictionary = sam._build_primitive_ctx(sad_full)
	_check(bool(ctx4.get("ball_in_flight", false)) and ctx4.get("ball_velocity", Vector2.ZERO) == Vector2(-400, 0), "I11 球面键：飞行中+速度=方向×速度")

	# ===== F 组：场地放置委托（波D）=====
	print("[F] 场地放置委托")
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true, \"C\": true, \"D\": true}}")
	var caster = StubPlayer.new()
	caster.position = Vector2(100, 100)
	var sad_field := {"player": caster, "skills_analysis": []}
	var skill_field := {"has_field_tag": true, "intents": {"attack": 0.0, "defense": 0.9, "support": 0.0, "control": 0.0}, "primary_intent": "defense", "skill_data": {"tag_params": {"field_obs_add": {"duration": 12.0}}}}
	sam.ball_node = null  # F1 缺球场景（I11 挂上的 stub 球先摘掉）
	var f1: Vector2 = sam._select_field_position(sad_field, skill_field)
	_check(f1 == Vector2(100, 100), "F1 goal_ball_line 缺球 ctx → 原语 fail-closed 回自站位")
	stub_ball.position = Vector2.ZERO
	sam.ball_node = stub_ball  # F2 有球场景
	var f2: Vector2 = sam._select_field_position(sad_field, skill_field)
	_check(f2 == Vector2(220, 0), "F2 goal_ball_line 有球(0,0)：GOAL_A(300,0)→球连线0.6系数cap80=(220,0) 实测%s" % str(f2))
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true, \"B\": true}}")
	var f3: Vector2 = sam._select_field_position(sad_field, skill_field)
	_check(f3 == Vector2(100, 100), "F3 波D关：走旧分支(无values)回自站位，忽略球 实测%s" % str(f3))

	# ===== N 组：意图校准 =====
	print("[N] intent 校准")
	# 单类别标签(tags 权重1.0)：_compute_tag_intents 全量扫描 tag_params（旧代码口径），
	# legacy: control 0.5 + defense 0.8；校准(A开)：control max(0.5,0.6)=0.6, defense 0.8
	_restore_switches()
	var params_mixed := {"ball_dmg_down_pct": {"value": 20.0}, "player_def_up_pct": {"value": 25.0}}
	var n_off: Dictionary = sam._determine_intents(["on_ball"] as Array[String], params_mixed)
	_check(is_equal_approx(float(n_off.get("control", 0)), 0.5 / 1.3) and is_equal_approx(float(n_off.get("defense", 0)), 0.8 / 1.3), "N1 全关=旧归一化(control .5/def .8 → 1.3)")
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true}}")
	var n_on: Dictionary = sam._determine_intents(["on_ball"] as Array[String], params_mixed)
	# 校准后：control max(0.5,0.6)=0.6, defense 0.8 → total 1.4
	_check(is_equal_approx(float(n_on.get("control", 0)), 0.6 / 1.4) and is_equal_approx(float(n_on.get("defense", 0)), 0.8 / 1.4), "N2 开A：意图校准 max 并入(control .6/def .8 → 1.4) 实测%s" % str(n_on))

	# ===== R 组：全关零扰动总证 + 开关恢复 =====
	print("[R] 全关零扰动与恢复")
	_restore_switches()
	var r1: float = sam._compute_base_value(["on_ball"] as Array[String], {"ball_dmg_up_pct": {"value": 30.0}}, 20, 10.0)
	_check(is_equal_approx(r1, 33.75), "R1 恢复真实开关后回归旧公式(33.75)")
	var box_r: Dictionary = {"ctx": {"player": stub, "visible_enemies": [carrier], "stamina_ratio": 1.0}}
	var r2: Dictionary = sam._evaluate_primitive_gates(sad_ctx, {"raw_tags": ["player_root"]}, box_r)
	_check(not bool(r2.get("gated", true)), "R2 恢复后闸门不参与")
	_check(FileAccess.file_exists(SWITCHES_REAL) and not RegistryScript.is_wave_enabled("A"), "R3 真实 switches.json 保持 master=false")

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	_restore_switches()
	quit(1 if _fail > 0 else 0)
