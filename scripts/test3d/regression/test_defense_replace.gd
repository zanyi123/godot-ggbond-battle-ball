## 24号 S1~S3 验收：判别表+查询口+跳跃平替（headless，零数据文件触碰）
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
	print("
========== 24号 防御平替验收 ==========
")
	for i in range(3):
		await process_frame

	var table: Dictionary = DefenseTable.get_table()
	_assert("T1a: 表加载非空", not table.is_empty())
	_assert("T1b: field_obs_add=hard_block", DefenseTable.action_of("field_obs_add") == "hard_block")
	_assert("T1c: player_root=avoid", DefenseTable.action_of("player_root") == "avoid")
	_assert("T1d: 表外标签返回空", DefenseTable.action_of("ball_dmg_up_pct") == "")
	_assert("T1e: 复合技取最高优先", DefenseTable.best_action_for_tags(["ball_dmg_up_pct", "field_obs_add"] as Array[String]) == "hard_block")

	var sam = load("res://scripts/battle/spirit_ai_manager.gd").new()
	root.add_child(sam)
	var prof = load("res://scripts/battle/ai_profile.gd").new()
	prof.skill_mistake_chance = 0.0
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t24_caster"
	root.add_child(caster)
	var sad: Dictionary = {
		"player": caster, "profile": prof,
		"skill_decide_count": 1, "mistake_hold": {},
		"skills_analysis": [
			{"skill_id": "t24_hard", "skill_data": {"type": "active", "energy_cost": 10},
			 "tags": ["field_obs_add"] as Array[String]},
			{"skill_id": "t24_soft", "skill_data": {"type": "active", "energy_cost": 10},
			 "tags": ["player_def_up_pct"] as Array[String]},
		],
	}
	var choice: Dictionary = sam.get_ready_defense_action(sad, 20.0)
	_assert("T2a: 硬挡优先被选中", str(choice.get("action","")) == "hard_block" and str(choice.get("skill_id","")) == "t24_hard")
	_assert("T2b: 来球超半血→硬挡仍可选", not sam.get_ready_defense_action(sad, 90.0).is_empty())
	sad["skills_analysis"][0]["tags"] = ["ball_dmg_up_pct"] as Array[String]
	var choice2: Dictionary = sam.get_ready_defense_action(sad, 20.0)
	_assert("T2c: 无硬挡→软化兜底", str(choice2.get("action","")) == "soften")
	_assert("T2d: 超半血无硬挡→不硬吃", sam.get_ready_defense_action(sad, 90.0).is_empty())
	sad["mistake_hold"]["t24_soft"] = 99
	_assert("T2e: 失误短冷却中→不选", sam.get_ready_defense_action(sad, 20.0).is_empty())

	var aim = load("res://scripts/battle/ai_manager.gd").new()
	_assert("T3a: 开关默认关", not aim._defense_replace_jump_enabled())

	print("
========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)
