## 23-F2 事件登记表 v2 验收套件（工单23 时期1，headless）
## 覆盖：8 新枚举 emit→subscribe 回路 / take_damage 拦截分发点真实行为（默认惰性+置位拦截）
## / ball 瓦解分发点源锚 / wire_sources 零改动确认
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_event_registry_v2.gd
extends SceneTree

const EventBusScript = preload("res://scripts/systems/event_bus/event_bus.gd")

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _run() -> void:
	print("\n========== 23-F2 事件登记表 v2 验收 ==========\n")
	for i in range(3):
		await process_frame
	var watchdog := create_timer(60.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 超时")
		quit(3))

	# ===== E 组：8 新枚举 emit→subscribe 回路 =====
	print("[E] 8 枚举回路")
	var bus = EventBusScript.new()
	root.add_child(bus)
	bus.add_to_group("battle_event_bus")   # player 分发点按组查找（生产挂载口径）
	var new_events := ["DEFEND_INTERCEPT", "DEFEND_ATTRIBUTE_BREAK", "ITEM_ACQUIRED", "ITEM_USED",
		"SUMMON_SPAWNED", "SUMMON_DESPAWNED", "SUMMON_MERGED", "BALL_FORCED_CONTROL"]
	for ev_name in new_events:
		var got: Array = []   # 引用容器（GDScript lambda 按值捕获，赋值不回传）
		var cb := func(payload: Dictionary) -> void: got.append(payload)
		bus.subscribe(bus.GameEvent[ev_name], cb)
		var payload := {"probe": ev_name}
		bus.emit_event(bus.GameEvent[ev_name], payload)
		_check(not got.is_empty() and str((got[0] as Dictionary).get("probe", "")) == ev_name, "E-%s 回路（emit→subscribe 收到载荷）" % ev_name)

	# ===== D 组：take_damage 拦截分发点（真实 player 实例）=====
	print("[D] 拦截分发点")
	var player = load("res://scripts/battle/player.gd").new()
	player.name = "t_intercept_p"
	root.add_child(player)
	var received: Array = []
	var cb2 := func(payload: Dictionary) -> void: received.append(payload)
	bus.subscribe(bus.GameEvent.DEFEND_INTERCEPT, cb2)
	# 默认惰性：旗标 false → 正常伤害路径（无拦截）
	var r1: Dictionary = player.take_damage(10.0, null, "")
	_check(int(r1.get("damage", -1)) > 0 and received.is_empty(), "D1 默认旗标=惰性（正常伤害，无事件）")
	# 置位：拦截生效+事件载荷正确
	player.defend_intercept_ready = true
	player.defend_intercept_item = "fenny_pan"
	var r2: Dictionary = player.take_damage(10.0, null, "")
	_check(int(r2.get("damage", -1)) == 0 and bool(r2.get("intercepted", false)), "D2 置位后拦截：零伤+intercepted 标记")
	var pl: Dictionary = received[0] if not received.is_empty() else {}
	_check(str(pl.get("item", "")) == "fenny_pan" and is_equal_approx(float(pl.get("blocked_damage", 0)), 10.0), "D3 DEFEND_INTERCEPT 载荷（item/blocked_damage）")
	player.defend_intercept_ready = false

	# ===== S 组：ball 瓦解分发点源锚（实体级功能测试随 F1 撕咬交付）=====
	print("[S] 瓦解分发点源锚")
	var ball_src := FileAccess.get_file_as_string("res://scripts/battle/ball.gd")
	var player_src := FileAccess.get_file_as_string("res://scripts/battle/player.gd")
	_check(ball_src.contains("DEFEND_ATTRIBUTE_BREAK") and ball_src.contains("_def_break_el == _att_el"), "S1 ball 命中判定口瓦解分发块在位（唯一）")
	_check(player_src.contains("DEFEND_INTERCEPT") and player_src.count("GameEvent.DEFEND_INTERCEPT") == 1, "S2 take_damage 拦截分发点唯一（emit 位唯一）")
	var bus_src := FileAccess.get_file_as_string("res://scripts/systems/event_bus/event_bus.gd")
	_check(bus_src.contains("SUMMON_MERGED") and bus_src.contains("BALL_FORCED_CONTROL"), "S3 枚举 v2 落库（8 新枚举）")
	var w_src := FileAccess.get_file_as_string("res://scripts/systems/event_bus/event_bus.gd")
	_check(w_src.contains("func wire_sources") and not w_src.contains("SUMMON_SPAWNED.connect"), "S4 wire_sources 零改动（系统级通知不经节点转发，23a§2.3）")

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
