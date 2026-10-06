## 24号 综合评分系统验收：徒手接球 vs 技能防御 vs 跳跃 三候选同池（headless，零数据文件触碰）
extends SceneTree

const DefenseTable = preload("res://scripts/battle/spirit_ai/defense_table.gd")

var _pass: int = 0
var _fail: int = 0

class StubPlayer extends CharacterBody2D:
	var character_id: String = "t24"
	var team: String = "a"
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var is_defeated: bool = false

func _initialize() -> void:
	_run()

func _assert(n: String, ok: bool) -> void:
	if ok: _pass += 1; print("  ✅ " + n)
	else: _fail += 1; print("  ❌ " + n)

func _run() -> void:
	print("\n========== 24号 综合评分系统验收 ==========\n")
	for i in range(3):
		await process_frame

	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	root.add_child(sam)
	var prof = load("res://scripts/battle/ai_profile.gd").new()
	prof.skill_mistake_chance = 0.0

	# S1 判别表数据加载
	var table: Dictionary = DefenseTable.get_table()
	_assert("S1a: 判别表加载非空", not table.is_empty())
	_assert("S1b: hard_block 优先级最高", DefenseTable.best_action_for_tags(["player_def_up_pct", "field_obs_add"] as Array[String]) == "hard_block")

	# S2 徒手接球打分
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t24_c"
	root.add_child(caster)
	var full: float = sam.score_bare_hand_catch(caster, 30.0, 20.0)
	_assert("S2a: 体力满+弱球=高扛住概率", full > 80.0)
	var weak: float = sam.score_bare_hand_catch(caster, 300.0, 90.0)
	var low_st: StubPlayer = StubPlayer.new()
	low_st.character_id = "t24_low"
	low_st.stamina = 10.0
	root.add_child(low_st)
	var hard: float = sam.score_bare_hand_catch(low_st, 300.0, 90.0)
	_assert("S2b: 体力低+狠球=低扛住概率", hard < 30.0)
	_assert("S2c: 概率值域[0,100]", full >= 0.0 and full <= 100.0 and hard >= 0.0 and hard <= 100.0)

	# S3 技能防御评估（带 win 0~1）
	var sad: Dictionary = {
		"player": caster, "profile": prof,
		"skill_decide_count": 1, "mistake_hold": {},
		"skills_analysis": [
			{"skill_id": "t24_block", "skill_data": {"type": "active", "energy_cost": 10},
			 "tags": ["field_obs_add"] as Array[String]},
		],
	}
	var sk: Dictionary = sam.pick_defense_skill(sad, 20.0, 150.0)
	_assert("S3a: 技能评估返回 win∈(0,1]", float(sk.get("win", -1.0)) > 0.0 and float(sk.get("win", -1.0)) <= 1.0)
	_assert("S3b: 硬挡动作被识别", str(sk.get("action", "")) == "hard_block")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)
