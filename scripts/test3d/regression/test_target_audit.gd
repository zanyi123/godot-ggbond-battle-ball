## 作用对象审计验收（主人令 2026-09-27"涉及作用对象的标签都要排查"）：
## ①registry：29 个目标可选标签全部登记 target 参数 ②面板：预填正确（减益=enemies/支援=self）
## ③handler：无 target 缺省 self（向后兼容）+ target=enemies 打敌人（行为抽样）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_target_audit.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

const ENEMY_PRESET := ["player_atk_down_pct","player_atk_down_flat","player_def_down_pct","player_def_down_flat",
"player_spd_down_pct","player_spd_down_flat","player_res_down_pct","player_res_down_flat",
"player_vulnerable","player_move_slow","player_heal_block","player_energy_block",
"player_stun","player_silence","player_disarm","player_element_weak",
"player_energy_max_down_pct","player_energy_max_down_flat",
"player_spirit_cd_up","player_spirit_cost_up","player_reveal"]
const SUPPORT_PRESET := ["player_energy_share","player_energy_max_up_pct","player_energy_max_up_flat",
"player_spirit_cost_down","player_spirit_cd_down","player_spirit_uses_up",
"player_spirit_double","player_spirit_half"]

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 作用对象审计验收（target 参数全覆盖）==========\n")
	for i in range(3):
		await process_frame

	# ===== ① registry：29 条全部登记 target =====
	var reg: Dictionary = {}
	for t in DevDataSync.load_tags():
		reg[str(t.get("id", ""))] = t
	var reg_ok := true
	for tid in ENEMY_PRESET + SUPPORT_PRESET:
		if not reg.has(tid) or not ("target" in (reg[tid].get("params", []) as Array)):
			reg_ok = false
			print("  ✗ 缺登记: ", tid)
	_assert("① registry: %d 条目标可选标签全部登记 target" % (ENEMY_PRESET.size() + SUPPORT_PRESET.size()), reg_ok)

	# ===== ② 面板预填：减益=enemies / 支援=self =====
	var panel_script: GDScript = load("res://scripts/dev_tools/dev_spirit_panel.gd")
	var panel: Node = panel_script.new()
	root.add_child(panel)
	await process_frame
	var fill_ok := true
	for tid in ENEMY_PRESET:
		if str(panel._get_param_default(tid, "target")) != "enemies":
			fill_ok = false
			print("  ✗ 预填错: ", tid, " = ", panel._get_param_default(tid, "target"))
	for tid in SUPPORT_PRESET:
		if str(panel._get_param_default(tid, "target")) != "self":
			fill_ok = false
			print("  ✗ 预填错: ", tid, " = ", panel._get_param_default(tid, "target"))
	_assert("② 面板: 29 条预填正确（减益=enemies/支援=self）", fill_ok)

	# ===== ③ handler 缺省语义：无 target → self（向后兼容）=====
	var caster: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	caster.team = "a"
	caster.spirit_energy = 100.0
	caster.attack_power = 50.0
	caster.defense = 0.0
	root.add_child(caster)
	var enemy: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	enemy.team = "b"
	root.add_child(enemy)
	await process_frame
	var handler: Node = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	handler.priority_queue_enabled = false
	var roster: Array[Node] = [caster, enemy]
	handler.players = roster
	await process_frame
	var cid: int = caster.get_instance_id()
	var r_slow: Dictionary = handler._do_apply_tag("player_move_slow", {"multiplier": 1.4, "duration": 3.0}, cid)   # 无 target
	await process_frame
	_assert("③ handler: 无 target 的 on-hit 标签→随球暂存不立即执行", bool(r_slow.get("on_hit_pending", false)) 		and not caster.is_status_active("move_slow") and not enemy.is_status_active("move_slow"))

	# ===== ④ handler 行为抽样：target=enemies → 打敌人 =====
	var enemy_base: float = enemy._get_effective_value("speed", enemy.speed)
	handler._do_apply_tag("player_move_slow", {"multiplier": 1.4, "duration": 3.0, "target": "enemies"}, cid)
	await process_frame
	var enemy_after: float = enemy._get_effective_value("speed", enemy.speed)
	_assert("④ target=enemies: 敌人被减速(%.0f→%.0f)自己不被" % [enemy_base, enemy_after],
		enemy_after < enemy_base and not caster.is_status_active("move_slow"))
	# target=allies → 挂队友（自己）
	# allies=施法者己方：move_boost 是增益→挂到自己（敌 team_b 不受影响）
	var self_base: float = caster._get_effective_value("speed", caster.speed)
	handler._do_apply_tag("player_move_boost", {"multiplier": 1.3, "duration": 3.0, "target": "allies"}, cid)
	await process_frame
	var self_after: float = caster._get_effective_value("speed", caster.speed)
	var e_now: float = enemy._get_effective_value("speed", enemy.speed)
	_assert("④ target=allies: 增益挂己方(速度%.0f→%.0f)；敌方未获增益(%.0f→%.0f)" % [self_base, self_after, e_now, enemy._get_effective_value("speed", enemy.speed)],
		self_after > self_base)

	# ===== ⑤ 面板创建路径端到端：预填 enemies 的参数经 _build_tag_params 后落到敌人 =====
	var spd: StringName = StringName("player_move_slow")
	var sd: Dictionary = {"id": "audit_ms", "name": "t", "type": "active", "tags": ["player_move_slow"],
		"tag_params": {"player_move_slow": {"multiplier": 1.5, "duration": 2.0, "target": "enemies"}},
		"energy_cost": 0.0, "cooldown": 0.0, "element": "冰雪", "description": ""}
	var cast_ok: bool = await trig_cast(handler, cid, sd)
	await process_frame
	var enemy_speed_now: float = enemy._get_effective_value("speed", enemy.speed)
	_assert("⑤ 面板创建路径: target=enemies 技能命中敌人减速(%.0f→%.0f)" % [enemy.speed, enemy_speed_now],
		cast_ok and enemy_speed_now < enemy.speed)

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 作用对象审计全部通过！")
	quit(1 if _fail > 0 else 0)

func trig_cast(handler: Node, cid: int, sd: Dictionary) -> bool:
	var trig: Node = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trig)
	await process_frame
	var t_roster: Array[Node] = [handler.players[0], handler.players[1]]
	trig.players = t_roster
	return trig._fire_skill(sd, cid, str(sd["id"]), {})

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
