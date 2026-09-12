## 流程化验证：纯 JSON 新增的被动+天赋，零代码直接工作？
extends Node3D
func _ready() -> void:
	var arena = load("res://scenes/battle/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout
	var bus = BattleEventBus.get_bus(get_tree())
	var talent = get_node("/root/TalentSystem")
	var trigger = arena.spirit_system.get("skill_trigger")
	var all_ok := true

	# ===== A. 纯数据新被动：skill_草木_passive_test 受击→全队防+6 =====
	var defender = arena.team_b_players[0]
	var sid_list: Array[String] = ["skill_草木_passive_test"]
	trigger.set_player_skills(defender.get_instance_id(), sid_list)
	defender.spirit_energy = 50
	bus.emit_event(BattleEventBus.GameEvent.HIT_TAKEN, {"defender": defender, "damage": 10})
	await get_tree().create_timer(0.3).timeout
	var buffed := 0
	for p in arena.team_a_players + arena.team_b_players:
		if p._buffs != null and p._buffs.size() > 0:
			buffed += 1
	# 语义：被动=个人元灵→作用于施法者自己（全队效果走天赋 event 型）
	var self_ok: bool = defender._buffs != null and defender._buffs.size() > 0
	_report("A. 新被动（纯JSON）受击→自身防buff", self_ok, "受击者 buffs=%d" % (defender._buffs.size() if defender._buffs else 0))
	all_ok = all_ok and self_ok

	# ===== B. 纯数据新天赋：buf_3 克制专家 COUNTER_HIT→全队攻+8 =====
	talent.unlocked.clear()
	talent.unlocked.assign(["buf_1", "buf_3"])
	talent.setup_battle()
	# 清掉 A 的 buff 干扰（等到期太久，直接看攻 buff 数量）
	bus.emit_event(BattleEventBus.GameEvent.HIT_COUNTER, {"attacker": arena.team_a_players[0], "defender": defender, "multiplier": 1.3})
	await get_tree().create_timer(0.3).timeout
	var atk_buffed := 0
	for p in arena.team_a_players + arena.team_b_players:
		if p._buffs != null:
			for bid in p._buffs:
				if "attack" in str(p._buffs[bid].get("stat", "")):
					atk_buffed += 1
	_report("B. 新天赋（纯JSON）克制命中→全队攻buff", atk_buffed >= 6, "atk_buffed=%d/6" % atk_buffed)
	all_ok = all_ok and atk_buffed >= 6

	print("[Pipe] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)

func _report(item: String, ok: bool, detail: String) -> void:
	print("[Pipe][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
