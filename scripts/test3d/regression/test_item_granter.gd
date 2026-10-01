## 23-F3 道具兑换口验收套件（工单23 时期1，headless）
## 覆盖：grant→ITEM_ACQUIRED / 锅拦截链（置态→拦截→耐久递减→摘除）/ 药水双恢复 / 烟花吸附
## / 未知道具 fail-closed / 比赛内临时账本（清场不污染）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_item_granter.gd
extends SceneTree

const EventBusScript = preload("res://scripts/systems/event_bus/event_bus.gd")
const GranterScript = preload("res://scripts/battle/battle_item_granter.gd")

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = "t_p"
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var spirit_energy: float = 40.0
	var max_spirit_energy: float = 100.0
	var stamina: float = 50.0
	var max_stamina: float = 100.0
	# 23-F2 拦截旗标（granter 置位目标）
	var defend_intercept_ready: bool = false
	var defend_intercept_item: String = ""
	var defend_break_element: String = ""


class StubBall extends Area2D:
	var is_active: bool = true
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2(1, 0)
	var ball_speed: float = 400.0


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _make_world() -> Dictionary:
	var bus = EventBusScript.new()
	bus.add_to_group("battle_event_bus")
	root.add_child(bus)
	var granter = GranterScript.new()
	granter.add_to_group("battle_item_granters")
	root.add_child(granter)
	return {"bus": bus, "granter": granter}


func _run() -> void:
	print("\n========== 23-F3 道具兑换口验收 ==========\n")
	for i in range(3):
		await process_frame
	var watchdog := create_timer(60.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 超时")
		quit(3))
	var w := _make_world()
	var granter: Node = w["granter"]
	var events: Array = []
	var cb := func(payload: Dictionary) -> void: events.append(payload)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.ITEM_ACQUIRED, cb)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.ITEM_USED, cb)

	var p: StubPlayer = StubPlayer.new()
	root.add_child(p)

	# ===== I1：grant→事件+账本 =====
	var ok: bool = granter.grant_battle_item(p, "fenny_potion", "magic_ball")
	_check(ok and (events as Array).size() == 1 and str((events[0] as Dictionary).get("item_id", "")) == "fenny_potion", "I1 grant→ITEM_ACQUIRED（source 链）")
	_check(not granter.grant_battle_item(p, "no_such_item"), "I2 未知道具 fail-closed（不入账不广播）")

	# ===== I3：药水双恢复 =====
	var used: bool = granter.use_battle_item(p, "fenny_potion")
	_check(used and p.stamina == 80.0 and p.spirit_energy == 65.0, "I3 药水：回血30+能量25（即时消耗）")
	_check((events as Array).size() == 2 and str((events[1] as Dictionary).get("item_id", "")) == "fenny_potion", "I4 ITEM_USED 广播")
	_check(not granter.use_battle_item(p, "fenny_potion"), "I5 账本扣减（耗尽再用=false）")

	# ===== I6：锅拦截链（置态→拦截→耐久3→摘除）=====
	_check(granter.grant_battle_item(p, "fenny_pan") and p.defend_intercept_ready, "I6 锅 grant→拦截态置位")
	var got: Array = []
	var cb2 := func(payload: Dictionary) -> void: got.append(payload)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.DEFEND_INTERCEPT, cb2)
	# 拦截事件直发（=real take_damage 分发点行为，真实链已在 F2 套件 D 组证过）
	for i in range(2):
		(w["bus"] as Node).emit_event((w["bus"] as Node).GameEvent.DEFEND_INTERCEPT, {"defender": p, "attacker": null, "blocked_damage": 10.0, "item": "fenny_pan"})
	_check((got as Array).size() == 2 and p.defend_intercept_ready, "I7 拦截×2：事件+耐久内留存")
	(w["bus"] as Node).emit_event((w["bus"] as Node).GameEvent.DEFEND_INTERCEPT, {"defender": p, "attacker": null, "blocked_damage": 10.0, "item": "fenny_pan"})
	_check(not p.defend_intercept_ready, "I8 耐久3尽→拦截态摘除")
	(w["bus"] as Node).emit_event((w["bus"] as Node).GameEvent.DEFEND_INTERCEPT, {"defender": p, "attacker": null, "blocked_damage": 10.0, "item": "fenny_pan"})
	_check((got as Array).size() == 4 and not p.defend_intercept_ready, "I9 耐久尽后事件仍广播（广播恒发）但拦截态已清")

	# ===== I10：烟花吸附（改向+BALL_FORCED_CONTROL）=====
	var ball: StubBall = StubBall.new()
	ball.global_position = Vector2(200, 0)
	root.add_child(ball)
	granter.grant_battle_item(p, "fenny_firework")
	var fc: Array = []
	var cb3 := func(payload: Dictionary) -> void: fc.append(payload)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.BALL_FORCED_CONTROL, cb3)
	var used2: bool = granter.use_battle_item(p, "fenny_firework", ball)
	var dir: Vector2 = ball.ball_direction
	_check(used2 and absf(dir.x + 1.0) < 0.01, "I10 烟花：球改向施法者（吸附）")
	_check((fc as Array).size() == 1 and str((fc[0] as Dictionary).get("mode", "")) == "adsorb", "I11 BALL_FORCED_CONTROL(adsorb) 广播")

	# ===== I12：临时账本清场（clear_all 后全空）=====
	granter.grant_battle_item(p, "fenny_pan")
	granter.clear_all()
	_check(not granter.use_battle_item(p, "fenny_pan") and not p.defend_intercept_ready, "I12 clear_all 清账（比赛内临时，不污染存档）")

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
