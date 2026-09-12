## E2 验收测试：A/B/C 类发射点接线（headless 可跑）
## 真实投球命中接球姿态球员 → 事件流水应依次出现：
##   ATTACK_LAUNCHED → HIT_TAKEN → HIT_RESILIENCE_ROLLED → (DEFEND_CAUGHT | DEFEND_BOUNCED)
## 以及 CATCH_STANCE（进/出姿态）
extends Node3D

var _arrived: Array = []  # 到达顺序 [{event, payload}]
var _want := {
	BattleEventBus.GameEvent.ATTACK_LAUNCHED: false,
	BattleEventBus.GameEvent.HIT_TAKEN: false,
	BattleEventBus.GameEvent.HIT_RESILIENCE_ROLLED: false,
	BattleEventBus.GameEvent.DEFEND_CATCH_STANCE: false,
}

func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var bus = BattleEventBus.get_bus(get_tree())
	if bus == null:
		print("[E2][FAIL] 总线不存在")
		get_tree().quit(1)
		return
	for ev in _want:
		bus.subscribe(ev, _on_event.bind(ev))
	# 终态事件也订阅（统计用，不作必须项——knockback2 脱手时无终态属正常）
	bus.subscribe(BattleEventBus.GameEvent.DEFEND_CAUGHT, _on_event.bind(BattleEventBus.GameEvent.DEFEND_CAUGHT))
	bus.subscribe(BattleEventBus.GameEvent.DEFEND_BOUNCED, _on_event.bind(BattleEventBus.GameEvent.DEFEND_BOUNCED))

	# 防御方进入待接球姿态
	var atk = arena.team_a_players[0]
	var def = arena.team_b_players[0]
	def.enter_catch_state()
	await get_tree().create_timer(0.2).timeout

	# 投球 5 次（韧性 roll 随机：knockback2 脱手无终态事件属正常，5 次至少 1 次终态）
	var empty_skills: Array[Dictionary] = []
	for trial in range(5):
		def.global_position = Vector2(260, -130)  # 复位（击退会推走）
		arena.ball_node.launch(atk.global_position,
			(def.global_position - atk.global_position).normalized(),
			30.0, 500.0, atk, empty_skills)
		var waited := 0.0
		while waited < 4.0 and arena.ball_node.is_active:
			await get_tree().physics_frame
			waited += get_process_delta_time()
		await get_tree().create_timer(0.2).timeout
		def.is_ready_to_catch = true  # 命中处理可能使其状态变化，保持接球姿态
		def.stamina = 200

	# 断言
	var all_ok := true
	for ev in _want:
		var ok: bool = _want[ev]
		all_ok = all_ok and ok
		print("[E2][%s] %s" % ["PASS" if ok else "FAIL", BattleEventBus.GameEvent.keys()[ev]])
	# 终态：CAUGHT 或 BOUNCED 至少其一
	var caught_n := 0
	var bounced_n := 0
	for item in _arrived:
		if item["event"] == BattleEventBus.GameEvent.DEFEND_CAUGHT:
			caught_n += 1
		elif item["event"] == BattleEventBus.GameEvent.DEFEND_BOUNCED:
			bounced_n += 1
	var ok_terminal: bool = caught_n > 0 or bounced_n > 0
	all_ok = all_ok and ok_terminal
	print("[E2][%s] 终态事件（CAUGHT=%d / BOUNCED=%d）" % ["PASS" if ok_terminal else "FAIL", caught_n, bounced_n])
	# 顺序：每次投球的 LAUNCHED 早于对应 HIT_TAKEN（整体首尾校验）
	var idx_launched := _arrived.find_custom(func(i): return i["event"] == BattleEventBus.GameEvent.ATTACK_LAUNCHED)
	var idx_hit := _arrived.find_custom(func(i): return i["event"] == BattleEventBus.GameEvent.HIT_TAKEN)
	var order_ok: bool = idx_launched >= 0 and idx_hit >= 0 and idx_launched < idx_hit
	all_ok = all_ok and order_ok
	print("[E2][%s] 顺序 LAUNCHED 早于 HIT_TAKEN" % ["PASS" if order_ok else "FAIL"])
	print("[E2] 事件流水: %s" % str(_arrived.map(func(i): return BattleEventBus.GameEvent.keys()[i["event"]])))
	print("[E2] effect 分布:", _effects)
	print("[E2] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)

var _effects := {}
func _on_event(payload: Dictionary, ev: BattleEventBus.GameEvent) -> void:
	_arrived.append({"event": ev, "payload": payload})
	if _want.has(ev):
		_want[ev] = true
	if ev == BattleEventBus.GameEvent.HIT_TAKEN:
		var e = str(payload.get("effect", "?"))
		_effects[e] = int(_effects.get(e, 0)) + 1
		print("[E2]   HIT_TAKEN effect=", e, " was_catch_stance=", payload.get("was_ready_to_catch"))
