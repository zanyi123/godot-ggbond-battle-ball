## player_root target 参数修复验收（主人批 2026-09-27）：缠敌人/缺省自己/registry 登记/面板预填
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_root_target.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== player_root target 参数修复验收 ==========\n")
	for i in range(3):
		await process_frame
	var trig: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trig)
	await process_frame
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "a"
	caster.spirit_energy = 100.0
	root.add_child(caster)
	var enemy: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	enemy.team = "b"
	root.add_child(enemy)
	await process_frame
	var roster: Array[Node] = [caster, enemy]
	trig.players = roster
	trig._effect_handler.players = roster   # 标签目标的查找名册在 handler 上
	var cid: int = caster.get_instance_id()
	trig.set_player_skills(cid, ["skill_雷火_3"] as Array[String])   # ① 生产资格路径：名册在册
	trig._effect_handler.priority_queue_enabled = false              # 标签即时应用（去队列窗口）

	# ① target=enemies → 敌人被定身，自己不被定身（生产路径 trigger_skill）
	trig.trigger_skill(cid, "skill_雷火_3", {})
	await process_frame
	var enemy_rooted: bool = enemy.is_status_active("rooted")
	var self_rooted: bool = caster.is_status_active("rooted")
	_assert("蔓藤(测) target=enemies: 敌人定身且自己不定身", enemy_rooted and not self_rooted)
	enemy.turn_off_light("rooted")
	caster.turn_off_light("rooted")

	# ② 缺省（无 target）→ 默认挂自己（既有语义不变；直测 _do_apply_tag 缺省路径）
	var r2: Dictionary = trig._effect_handler._do_apply_tag("player_root", {"duration": 2.0}, cid)
	await process_frame
	_assert("缺省无 target: 默认挂自己（既有语义）", bool(r2.get("success", false)) 		and caster.is_status_active("rooted") and not enemy.is_status_active("rooted"))

	# ③ registry 登记 + 面板预填
	var reg_ok := false
	for t in DevDataSync.load_tags():
		if str(t.get("id")) == "player_root":
			reg_ok = "target" in (t.get("params", []) as Array)
	var panel_script: GDScript = load("res://scripts/dev_tools/dev_spirit_panel.gd")
	var panel_default: String = str(panel_script.new()._get_param_default("player_root", "target"))
	_assert("registry: player_root 已登记 target 参数", reg_ok)
	_assert("面板: 新建技能时 target 预填 enemies", panel_default == "enemies")

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
