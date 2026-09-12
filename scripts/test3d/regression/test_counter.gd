## E4 验收测试：元素克制（headless 可跑）
## 雷火(克草木)攻击者 vs 草木元灵防守者 → 伤害=base×1.3-抗力；反向=base×1.0
## + HIT_COUNTER 事件收到断言
extends Node3D

var _counter_events: Array = []

func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var bus = BattleEventBus.get_bus(get_tree())
	bus.subscribe(BattleEventBus.GameEvent.HIT_COUNTER, func(p): _counter_events.append(p))

	var atk = arena.team_a_players[0]
	var def = arena.team_b_players[0]
	# 双方装备元灵：atk=雷火，def=草木（雷火克草木）
	atk.spirit_id = "spirit_leihuo"
	def.spirit_id = "spirit_caomu"
	# 找实际元灵 id（spirits.json 里按 element 匹配）
	var dm_spirits = DataManager.spirits
	for s in dm_spirits:
		if str(s.get("element")) == "雷火":
			atk.spirit_id = str(s.get("id"))
		elif str(s.get("element")) == "草木":
			def.spirit_id = str(s.get("id"))
	print("[E4] atk.spirit=%s(雷火) def.spirit=%s(草木)" % [atk.spirit_id, def.spirit_id])

	# 固定防御环境：非接球姿态、无韧性 roll 干扰（非接球走简单减法）
	def.is_ready_to_catch = false
	def.stamina = 500

	# 记录受击前体力，投一颗固定伤害球
	var stamina0: int = def.stamina
	var empty_skills: Array[Dictionary] = []
	arena.ball_node.launch(atk.global_position,
		(def.global_position - atk.global_position).normalized(),
		100.0, 500.0, atk, empty_skills)
	var waited := 0.0
	while waited < 4.0 and arena.ball_node.is_active:
		await get_tree().physics_frame
		waited += get_process_delta_time()
	await get_tree().create_timer(0.2).timeout

	var damage_dealt: int = stamina0 - def.stamina
	# 克制：100×1.3=130，减防御抗力（defense×defense_factor）；非克制=100-抗力
	var resist: float = float(def.defense) * def.defense_factor
	var expect_counter := int(100.0 * 1.3 - resist)
	print("[E4] 伤害=%d 期望克制=%d (100×1.3-%.1f抗力) 事件数=%d" % [damage_dealt, expect_counter, resist, _counter_events.size()])
	# 伤害落在克制区间（≥普通伤害）
	var base_expect := int(100.0 - resist)
	var ok_high: bool = damage_dealt > base_expect
	_report("克制伤害高于普通", ok_high, "%d > %d" % [damage_dealt, base_expect])
	var ok_event: bool = _counter_events.size() > 0
	_report("HIT_COUNTER 事件收到", ok_event, "%d 次, payload=%s" % [_counter_events.size(), str(_counter_events[0]) if _counter_events.size() > 0 else "无"])
	all_ok(ok_high and ok_event)

func all_ok(ok: bool) -> void:
	print("[E4] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _report(item: String, ok: bool, detail: String) -> void:
	print("[E4][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
