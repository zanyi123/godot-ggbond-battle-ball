## E1 验收测试：EventBus 骨架（headless 可跑）
## ① 总线存在且入组 ② 手动 emit 分发收到 ③ ball_caught 信号转发收到
## ④ defeated 信号转发收到 ⑤ log 缓冲记录
extends Node3D

var _received: Dictionary = {}  # GameEvent -> payload（最近一次）

func _ready() -> void:
	var arena_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = arena_scene.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var bus = BattleEventBus.get_bus(get_tree())
	_report("总线存在且入组", bus != null, str(bus != null))
	if bus == null:
		print("[E1] RESULT: FAIL")
		get_tree().quit(1)
		return

	# ② 手动 emit 分发
	bus.subscribe(BattleEventBus.GameEvent.HIT_TAKEN, _on_hit_taken)
	bus.emit_event(BattleEventBus.GameEvent.HIT_TAKEN, {"attacker": "测试", "damage": 10})
	await get_tree().process_frame
	_report("手动 emit 分发", _received.has(BattleEventBus.GameEvent.HIT_TAKEN), str(_received.get(BattleEventBus.GameEvent.HIT_TAKEN, {})))

	# ③ ball_caught 信号 → DEFEND_CAUGHT 转发
	var ball = arena.ball_node
	var target = arena.team_a_players[0]
	bus.subscribe(BattleEventBus.GameEvent.DEFEND_CAUGHT, _on_caught)
	ball._catch_ball(target)
	await get_tree().process_frame
	_report("ball_caught 信号转发", _received.has(BattleEventBus.GameEvent.DEFEND_CAUGHT), str(_received.get(BattleEventBus.GameEvent.DEFEND_CAUGHT, {})))

	# ④ defeated 信号 → HIT_DEFEATED 转发
	var victim = arena.team_b_players[0]
	victim.stamina = 1
	bus.subscribe(BattleEventBus.GameEvent.HIT_DEFEATED, _on_defeated)
	victim.take_damage(99999, arena.team_a_players[0])
	await get_tree().process_frame
	_report("defeated 信号转发", _received.has(BattleEventBus.GameEvent.HIT_DEFEATED), str(_received.get(BattleEventBus.GameEvent.HIT_DEFEATED, {})))

	# ⑤ log 缓冲
	bus.log_enabled = true
	bus.emit_event(BattleEventBus.GameEvent.ATTACK_LAUNCHED, {"attacker": "测试"})
	_report("log 缓冲记录", bus._log.size() > 0, "log 条数=%d" % bus._log.size())

	var all_ok: bool = _received.has(BattleEventBus.GameEvent.HIT_TAKEN) \
		and _received.has(BattleEventBus.GameEvent.DEFEND_CAUGHT) \
		and _received.has(BattleEventBus.GameEvent.HIT_DEFEATED) \
		and bus._log.size() > 0
	print("[E1] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)

func _on_hit_taken(payload: Dictionary) -> void:
	_received[BattleEventBus.GameEvent.HIT_TAKEN] = payload

func _on_caught(payload: Dictionary) -> void:
	_received[BattleEventBus.GameEvent.DEFEND_CAUGHT] = payload

func _on_defeated(payload: Dictionary) -> void:
	_received[BattleEventBus.GameEvent.HIT_DEFEATED] = payload

func _report(item: String, ok: bool, detail: String) -> void:
	print("[E1][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
