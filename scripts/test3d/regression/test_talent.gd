## E5 验收测试：天赋树队伍级（headless 可跑）
## ① stat 型点亮→全队 attack 增加 ② event 型（受击反震）→受击后全队防 buff ③ 存档往返 ④ manual 型注入主控
extends Node3D

func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var talent = get_node("/root/TalentSystem")
	var all_ok := true

	# 清空天赋（测试干净起点：存档也重置）
	talent.unlocked.clear()
	PlayerSaveManager.save_team_talent_tree([])

	# ===== ① stat 型：atk_1 弱点洞察（attack_bonus +5）=====
	# 无天赋基线：球员 _ready 时 refresh 可能读过旧存档，先无天赋刷新归零
	for p in arena.team_a_players + arena.team_b_players:
		p.refresh_bonuses()
	var a0: float = arena.team_a_players[0].attack_power
	var b0: float = arena.team_b_players[0].attack_power
	var ok_unlock: bool = talent.try_unlock("atk_1")
	_report("①a 点亮 atk_1", ok_unlock, str(ok_unlock))
	all_ok = all_ok and ok_unlock
	# refresh 后全队 attack 各自 +5
	for p in arena.team_a_players + arena.team_b_players:
		p.refresh_bonuses()
	var a1: float = arena.team_a_players[0].attack_power
	var b1: float = arena.team_b_players[0].attack_power
	var ok_stat: bool = absf((a1 - a0) - 5.0) < 0.51 and absf((b1 - b0) - 5.0) < 0.51
	_report("①b stat 全队生效(各+5)", ok_stat, "A: %.1f→%.1f, B: %.1f→%.1f" % [a0, a1, b0, b1])
	all_ok = all_ok and ok_stat

	# ===== ② event 型：def_2 受击反震（受击后全队防+8 持续4s，内冷却12s）=====
	var ok_def: bool = talent.try_unlock("def_1") and talent.try_unlock("def_2")
	_report("②a 点亮 def_1+def_2（含前置链）", ok_def, str(ok_def))
	all_ok = all_ok and ok_def
	talent.setup_battle()
	# 模拟受击事件
	var bus = BattleEventBus.get_bus(get_tree())
	bus.emit_event(BattleEventBus.GameEvent.HIT_TAKEN, {"defender": arena.team_a_players[0], "damage": 10})
	await get_tree().create_timer(0.3).timeout
	# 全队应有 defense buff（含 B 队——队伍级天赋全队生效）
	var buffed := 0
	for p in arena.team_a_players + arena.team_b_players:
		if p._buffs != null and p._buffs.size() > 0:
			buffed += 1
	# 诊断：talent 状态
	print("[E5][diag] unlocked=", talent.unlocked, " _subscribed=", talent._subscribed,
		" cd=", talent._event_cooldowns, " handler=", talent._find_tag_handler() != null)
	_report("②b 受击反震全队 buff", buffed >= 6, "buffed=%d/6" % buffed)
	all_ok = all_ok and buffed >= 6
	# 内冷却：立即再发一次不应重复（次数难直接断言，验证不崩溃即可）
	bus.emit_event(BattleEventBus.GameEvent.HIT_TAKEN, {"defender": arena.team_a_players[0], "damage": 10})
	await get_tree().create_timer(0.1).timeout
	print("[E2-note] 内冷却第二次触发已执行（不崩溃即过）")

	# ===== ③ 存档往返 =====
	talent.unlocked.assign(["atk_1", "def_1", "def_2"])
	PlayerSaveManager.save_team_talent_tree(talent.unlocked)
	print("[E5][diag3] save 后立即 get=", PlayerSaveManager.get_team_talent_tree(),
		" save_data键=", PlayerSaveManager.save_data.has("team_talent_tree"))
	var talent2 = get_node("/root/TalentSystem")
	talent2.unlocked.clear()
	var saved: Array = PlayerSaveManager.get_team_talent_tree()
	print("[E5][diag3b] get 返回=", saved, " size=", saved.size(), " 元素类型=", saved[0] if saved.size() > 0 else "无")
	talent2.unlocked.assign(saved)
	print("[E5][diag3b] assign 后=", talent2.unlocked, " size=", talent2.unlocked.size())
	var ok_save: bool = talent2.unlocked.size() == 3 and "def_2" in talent2.unlocked
	_report("③ 存档往返", ok_save, str(talent2.unlocked))
	all_ok = all_ok and ok_save

	# ===== ④ manual 型：buf_2 → buf_1 → 注入主控 =====
	talent.unlocked.assign(["buf_1", "buf_2"])
	talent.apply_manual_skills(arena.input_mgr.controlled_player)
	var ctrl = arena.input_mgr.controlled_player
	var ok_manual: bool = ctrl != null and "skill_大地_2" in ctrl.equipped_skills
	_report("④ manual 技能注入主控", ok_manual, str(ctrl.equipped_skills))
	all_ok = all_ok and ok_manual

	print("[E5] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)

func _report(item: String, ok: bool, detail: String) -> void:
	print("[E5][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
