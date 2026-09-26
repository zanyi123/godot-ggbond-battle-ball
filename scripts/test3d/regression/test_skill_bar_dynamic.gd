## 快捷技能栏管理验收（主人模型 2026-09-25）：复制传入队友→名册可释放/过期摘除/HUD动态格/换装重置
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_skill_bar_dynamic.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("\n========== 快捷技能栏管理（复制传入/动态格）==========\n")
	for i in range(3):
		await process_frame

	var trig: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trig)
	await process_frame
	var mate: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	mate.team = "a"
	mate.spirit_energy = 100.0
	root.add_child(mate)
	await process_frame
	var mate_id: int = mate.get_instance_id()
	var roster_a: Array[Node] = [mate]
	trig.players = roster_a
	# 名册基线：装备一个原技
	var base: Array[String] = ["skill_大地_1"]
	trig.set_player_skills(mate_id, base)

	var changes: Array = []
	trig.player_skills_changed.connect(func(pid): changes.append(pid))

	# ===== ① 复制传入：put_shared_copy → 队友名册注入 + 可释放 =====
	var snap := {"skill_id": "skill_雷火_1", "caster_id": 999, "team": "b"}
	trig.put_shared_copy(mate_id, snap, 5.0)
	await process_frame
	var roster: Array[String] = trig.get_player_skills(mate_id)
	_assert("①: 共享槽写入→队友名册注入复制技", "skill_雷火_1" in roster and "skill_大地_1" in roster)
	_assert("①: player_skills_changed 信号发出", changes.size() >= 1)
	# 释放资格：复制技可触发（真数据技能）
	var cast_ok: bool = trig.trigger_skill(mate_id, "skill_雷火_1")
	_assert("①: 队友可释放复制技（资格判定通过）", cast_ok)

	# ===== ② 过期摘除（_clock 推进）=====
	trig._process(6.0)   # 推进时钟越过 5s 时限
	await process_frame
	roster = trig.get_player_skills(mate_id)
	_assert("②: 超时→复制技自动摘除（原技保留）", not ("skill_雷火_1" in roster) and "skill_大地_1" in roster)

	# ===== ③ 换装重置：set_player_skills 清动态技能 =====
	trig.put_shared_copy(mate_id, snap, 30.0)
	await process_frame
	_assert("③前置: 二次注入在册", "skill_雷火_1" in trig.get_player_skills(mate_id))
	var new_base: Array[String] = ["skill_大地_1", "skill_草木_1"]
	trig.set_player_skills(mate_id, new_base)
	await process_frame
	_assert("③: 换装→动态技能清空（重置语义）", not ("skill_雷火_1" in trig.get_player_skills(mate_id)))

	# ===== ④ HUD 3 格上限（2026-09-27 主人裁定：无动态格，动态技占空槽、满 3 拒收）=====
	var hud: Control = load("res://scripts/battle/battle_hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.spirit_trigger = trig
	var team: Array[CharacterBody2D] = [mate]
	var enemies: Array[CharacterBody2D] = []
	hud.setup_players(team, enemies)
	await process_frame
	_assert("④: HUD 保持 3 格（上限=一局主动技能数）", hud.player_skill_boxes[0].size() == 3)
	# 有空槽：重置名册至 1 技（空 2 槽）→ 复制注入占空槽（名册 2/3）
	var reset_base: Array[String] = ["skill_大地_1"]
	trig.set_player_skills(mate_id, reset_base)
	await process_frame
	trig.put_shared_copy(mate_id, snap, 30.0)
	await process_frame
	_assert("④: 有空槽→复制技占空槽（名册 2/3）", trig.get_player_skills(mate_id).size() == 2)
	# 满 3：连续注入至达上限后第四个拒收
	trig.put_shared_copy(mate_id, {"skill_id": "skill_冰雪_1", "caster_id": 999, "team": "b"}, 30.0)
	trig.put_shared_copy(mate_id, {"skill_id": "skill_金刚_1", "caster_id": 999, "team": "b"}, 30.0)
	await process_frame
	var reject_ok: bool = trig.get_player_skills(mate_id).size() == 3
	trig.put_shared_copy(mate_id, {"skill_id": "skill_草木_1", "caster_id": 999, "team": "b"}, 30.0)
	_assert("④: 满 3 后再注入被拒（上限=3）", reject_ok and trig.get_player_skills(mate_id).size() == 3)
	# 过期腾位后可再收
	trig._process(31.0)
	await process_frame
	trig.put_shared_copy(mate_id, snap, 30.0)
	await process_frame
	_assert("④: 过期腾位→可再接收", "skill_雷火_1" in trig.get_player_skills(mate_id))
	trig._process(31.0)


	# ===== ⑤ AI 池自动包含动态技（get_player_skills 即 AI 选技池）=====
	trig.put_shared_copy(mate_id, snap, 30.0)
	await process_frame
	_assert("⑤: 动态技进入名册=AI 选技池自动覆盖", "skill_雷火_1" in trig.get_player_skills(mate_id))

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
