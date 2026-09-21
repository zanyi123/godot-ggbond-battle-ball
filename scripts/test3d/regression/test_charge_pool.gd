## 波3 #20 方案A 验收：技能充能池（主人裁决 2026-09-22，headless 可跑）
## 数据由测试内临时 skill 定义注入 trigger（零 skills.json 触碰，R1 合规）
## 断言：初始化满池/释放扣格/空池拒放/回充计时/不超max/无配置技能不受影响
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_charge_pool.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 技能充能池测试（方案A）==========\n")
	var trigger = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trigger)
	await process_frame
	await process_frame

	# 注入临时技能定义（内存缓存，不落 skills.json）
	trigger._skills_cache["test_charge_1"] = {
		"id": "test_charge_1", "type": "active", "energy_cost": 0, "cooldown": 0.0,
		"charges": {"max": 3, "recharge_time": 2.0}, "tags": [], "tag_params": {},
	}
	trigger._skills_cache["test_plain"] = {
		"id": "test_plain", "type": "active", "energy_cost": 0, "cooldown": 0.0,
		"tags": [], "tag_params": {},
	}
	var pid: int = 777
	var skills: Array[String] = ["test_charge_1", "test_plain"]
	trigger.set_player_skills(pid, skills)

	# ① 初始化满池
	_assert("初始化: 充能池满 3 格", trigger.get_skill_charges(pid, "test_charge_1") == 3)
	# ② 无配置技能不受影响（-1 = 不走充能门槛）
	_assert("无配置: 普通技能不走充能门槛 (-1)", trigger.get_skill_charges(pid, "test_plain") == -1)

	# ③ 释放扣格（_fire_skill 全链：能量0也能放——_consume_energy 找不到 player 时兼容放行）
	var cast_ok: bool = trigger.trigger_skill(pid, "test_charge_1", {})
	_assert("释放: 第一次成功且扣到 2 格", cast_ok and trigger.get_skill_charges(pid, "test_charge_1") == 2)

	# ④ 空池拒放：连放 2 次耗尽 → 第 4 次拒绝
	trigger.trigger_skill(pid, "test_charge_1", {})
	trigger.trigger_skill(pid, "test_charge_1", {})
	_assert("耗尽: 连放后 0 格", trigger.get_skill_charges(pid, "test_charge_1") == 0)
	var cast_deny: bool = trigger.trigger_skill(pid, "test_charge_1", {})
	_assert("空池拒放: 0 格时 trigger_skill=false", cast_deny == false and trigger.get_skill_charges(pid, "test_charge_1") == 0)

	# ⑤ 回充计时：_process 推进 2 秒回 1 格（不超 max）
	var recharged := false
	for i in range(130):  # 130 帧 × 1/60 ≈ 2.2s
		trigger._process(1.0 / 60.0)
		if trigger.get_skill_charges(pid, "test_charge_1") >= 1:
			recharged = true
			break
	_assert("回充: 2 秒后回 1 格", recharged)
	for i in range(400):
		trigger._process(1.0 / 60.0)
	_assert("回充: 不超 max=3", trigger.get_skill_charges(pid, "test_charge_1") == 3)

	# ⑥ CD 正交：带充能技能仍可同时配 CD（回归：_skill_cooldowns 独立工作）
	_assert("CD正交: 冷却表独立不受充能影响", not trigger._skill_cooldowns[pid]["test_charge_1"] > 0.0)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
