## 02前置地基工单验收：技能AI确定性化（工单A）+ 选中对象180°视野闸门（工单B）
## 零数据文件触碰。运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_spirit_ai_foundation.gd
extends SceneTree

const RealSpiritSys = preload("res://scripts/systems/spirit_system/spirit_system_manager.gd")

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = ""
	var team: String = "a"
	var is_defeated: bool = false
	var is_carrying_ball: bool = false
	var facing_direction: Vector2 = Vector2.RIGHT
	var stamina: float = 100.0
	var max_stamina: float = 100.0
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0


class StubSpiritSystem extends RealSpiritSys:
	var calls: Array = []
	func use_skill(player_id: int, skill_id: String, target_data: Dictionary = {}) -> bool:
		calls.append(skill_id)
		return true
	func get_skill_cooldown(player_id: int, skill_id: String) -> float:
		return 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 02前置地基工单：确定性化 + 视野选中闸门 ==========\n")
	for i in range(3):
		await process_frame

	var sam_script: GDScript = load("res://scripts/battle/spirit_ai_manager.gd")
	var aim_script: GDScript = load("res://scripts/battle/ai_manager.gd")
	var profile_script: GDScript = load("res://scripts/battle/ai_profile.gd")

	var sam1: Node = sam_script.new()
	var sam2: Node = sam_script.new()

	# ===== 工单A1：骰子确定性 =====
	var d1: float = sam1._deterministic_dice(12345, 678, 9)
	var d2: float = sam2._deterministic_dice(12345, 678, 9)
	_assert("A1a: 同输入跨实例恒同值", d1 == d2)
	_assert("A1b: 值域 [0,1)", d1 >= 0.0 and d1 < 1.0)
	var all_same: bool = true
	for i in range(50):
		if sam1._deterministic_dice(i, 42, 7) != sam1._deterministic_dice(i, 42, 7):
			all_same = false
	_assert("A1c: 50组重复调用零漂移（无内部状态依赖）", all_same)
	var distinct: bool = false
	for i in range(50):
		if sam1._deterministic_dice(i, 1) != sam1._deterministic_dice(i, 2):
			distinct = true
	_assert("A1d: 不同输入产生不同值", distinct)
	# 计数器维度发散性（2026-09-25 实证修复项：小步长乘数→相邻计数骰值~1e-5→失误死循环）
	var vals: Array[float] = []
	for i in range(100):
		vals.append(sam1._deterministic_dice(999331, 424243, i))
	var spread: float = vals.max() - vals.min()
	_assert("A1e: 连续100计数骰值充分发散（极差>0.6）", spread > 0.6)

	# ===== 工单A2：randf 清零 =====
	var src: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai_manager.gd")
	_assert("A2: spirit_ai_manager.gd 源码无 randf()（6处全换骰子）", src.find("randf()") == -1)

	# ===== 工单A3：Softmax 确定性 =====
	# AIProfile extends RefCounted（非 Resource），用无类型变量承接
	var prof = profile_script.new()
	var caster: StubPlayer = StubPlayer.new()
	caster.character_id = "t_fa_caster"
	caster.team = "a"
	root.add_child(caster)
	var sad: Dictionary = {
		"player": caster,
		"profile": prof,
		"skill_decide_count": 7,
		"skill_exec_count": 2,
		"skills_analysis": [],
		"last_skill_use_time": 0.0,
	}
	var pool: Array[Dictionary] = [
		{"skill": {"skill_id": "s_low"}, "score": 30.0},
		{"skill": {"skill_id": "s_high"}, "score": 60.0},
		{"skill": {"skill_id": "s_mid"}, "score": 45.0},
	]
	var pick1: Dictionary = sam1._select_skill_with_softmax(sad, pool, 15.0)
	var pick2: Dictionary = sam2._select_skill_with_softmax(sad, pool, 15.0)
	_assert("A3a: 同输入同温度两次选技同结果", str(pick1["skill"]["skill_id"]) == str(pick2["skill"]["skill_id"]))
	var pick3: Dictionary = sam1._select_skill_with_softmax(sad, pool, 0.0)
	_assert("A3b: temp=0 走确定性 argmax", str(pick3["skill"]["skill_id"]) == "s_high")

	# ===== 工单B：视野选中闸门 =====
	var ai_mgr: Node = aim_script.new()
	var profile_b = profile_script.new()
	var front: StubPlayer = StubPlayer.new()
	front.character_id = "t_fa_front"
	front.team = "b"
	front.position = Vector2(200, 0)
	root.add_child(front)
	var behind: StubPlayer = StubPlayer.new()
	behind.character_id = "t_fa_behind"
	behind.team = "b"
	behind.position = Vector2(-200, 0)
	root.add_child(behind)
	var ap_caster: Dictionary = {"player": caster, "profile": profile_b}
	var ap_front: Dictionary = {"player": front, "profile": profile_b}
	var ap_behind: Dictionary = {"player": behind, "profile": profile_b}

	var aps_all: Array[Dictionary] = [ap_caster, ap_front, ap_behind]
	ai_mgr.ai_players = aps_all
	sam1.ai_manager = ai_mgr

	_assert("B0: get_ap_for_player 命中注册球员", ai_mgr.get_ap_for_player(caster).get("player", null) == caster)
	_assert("B0b: get_ap_for_player 未注册返回空", ai_mgr.get_ap_for_player(StubPlayer.new()).is_empty())

	var sad_atk: Dictionary = {
		"player": caster,
		"profile": prof,
		"skill_decide_count": 7,
		"skill_exec_count": 2,
		"skills_analysis": [],
		"last_skill_use_time": 0.0,
	}

	var tgt1 = sam1._select_attack_target(sad_atk)
	_assert("B1: 视野内敌人被选中、身后敌人被过滤", tgt1 == front)

	var aps_behind: Array[Dictionary] = [ap_caster, ap_behind]
	ai_mgr.ai_players = aps_behind
	var tgt2 = sam1._select_attack_target(sad_atk)
	_assert("B2: 仅身后敌人 → 返回 null（视野过滤 fail-closed）", tgt2 == null)

	# B3: 攻击技能无合法（视野内）目标 → 不释放
	var sys_stub: StubSpiritSystem = StubSpiritSystem.new()
	sam1.spirit_system = sys_stub
	prof.skill_mistake_chance = 0.0
	var atk_skill: Dictionary = {
		"skill_id": "t_fa_atk",
		"has_player_tag": true,
		"intents": {"attack": 0.8, "defense": 0.0, "support": 0.0, "control": 0.1},
		"primary_intent": "attack",
		"skill_data": {"name": "t_fa_atk", "energy_cost": 10},
		"base_value": 50.0,
		"tags": ["on_player"] as Array[String],
	}
	sam1._execute_skill(sad_atk, atk_skill)
	_assert("B3: 仅视野外目标 → use_skill 不被调用（禁卡视野）", sys_stub.calls.is_empty())

	# B4: 视野内目标正常释放路径不受影响
	var aps_front: Array[Dictionary] = [ap_caster, ap_front]
	ai_mgr.ai_players = aps_front
	sam1._execute_skill(sad_atk, atk_skill)
	_assert("B4: 视野内目标 → use_skill 正常调用", sys_stub.calls.size() == 1 and str(sys_stub.calls[0]) == "t_fa_atk")

	# ===== 工单A追加：失误→局部短冷却（封死重选重掷循环）=====
	prof.skill_mistake_chance = 1.0  # 必失误
	var hold_skill: Dictionary = {
		"skill_id": "t_fa_hold",
		"has_player_tag": false,
		"has_field_tag": false,
		"has_ball_tag": false,
		"intents": {"attack": 0.0, "defense": 0.0, "support": 1.0, "control": 0.0},
		"primary_intent": "support",
		"skill_data": {"name": "t_fa_hold", "type": "active", "energy_cost": 5},
		"base_value": 40.0,
		"tags": ["on_player"] as Array[String],
	}
	sad_atk["skills_analysis"] = [hold_skill]
	sam1._execute_skill(sad_atk, hold_skill)
	var hold_map: Dictionary = sad_atk.get("mistake_hold", {})
	_assert("C1: 失误后按周期计数登记短冷却", int(hold_map.get("t_fa_hold", 0)) == int(sad_atk["skill_decide_count"]) + 3)
	_assert("C2: 冷却期内技能不可用（重选循环封死）", _first_available_id(sam1, sad_atk) == "")
	sad_atk["skill_decide_count"] = int(hold_map["t_fa_hold"])
	_assert("C3: 冷却期满技能恢复可用", _first_available_id(sam1, sad_atk) == "t_fa_hold")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！（零数据文件触碰）")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)


func _first_available_id(sam: Node, sad: Dictionary) -> String:
	var avail: Array[Dictionary] = sam._get_available_skills(sad)
	if avail.is_empty():
		return ""
	return str(avail[0]["skill_id"])
