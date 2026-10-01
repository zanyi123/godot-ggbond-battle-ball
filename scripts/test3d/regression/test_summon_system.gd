## 23-F1 召唤物系统验收套件（工单23 时期1，headless）
## 覆盖：生灭+信号 / 上限与 set_active_limit / 自动生成计时（固定步长确定性）/ 潜地状态机+耗能 tick
## / 融合判定（F4 缺席 fail-closed+在场时放行）/ 拦截分发（停球+限度）/ 类型表 fail-closed
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_system.gd
extends SceneTree

const EventBusScript = preload("res://scripts/systems/event_bus/event_bus.gd")
const ManagerScript = preload("res://scripts/systems/summon/summon_manager.gd")

var _pass: int = 0
var _fail: int = 0


class StubOwner extends CharacterBody2D:
	var character_id: String = "t_owner"
	var team: String = "a"
	var is_defeated: bool = false
	var is_penalized: bool = false
	var is_carrying_ball: bool = false
	var spirit_energy: float = 100.0
	var max_spirit_energy: float = 100.0
	var stamina: float = 100.0
	var max_stamina: float = 100.0


class StubBall extends Area2D:
	var is_active: bool = true
	var owner_player: CharacterBody2D = null
	var ball_direction: Vector2 = Vector2.RIGHT
	var ball_speed: float = 400.0


class StubPathManager extends Node:
	var in_path: bool = true
	func is_in_energy_path(_pos: Vector2) -> bool:
		return in_path


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
	var mgr = ManagerScript.new()
	mgr.add_to_group("summon_managers")
	root.add_child(mgr)
	var owner_a = StubOwner.new()
	owner_a.character_id = "ow_a"
	owner_a.team = "a"
	root.add_child(owner_a)
	return {"bus": bus, "mgr": mgr, "owner": owner_a}


func _run() -> void:
	print("\n========== 23-F1 召唤物系统验收 ==========\n")
	for i in range(3):
		await process_frame
	var watchdog := create_timer(90.0).timeout.connect(func() -> void:
		print("❌ WATCHDOG 超时")
		quit(3))
	var w := _make_world()
	var mgr: Node = w["mgr"]
	var owner_a: StubOwner = w["owner"]
	var events: Array = []
	var cb := func(payload: Dictionary) -> void: events.append(payload)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.SUMMON_SPAWNED, cb)
	(w["bus"] as Node).subscribe((w["bus"] as Node).GameEvent.SUMMON_DESPAWNED, cb)

	# ===== G1：生灭+信号 =====
	var e1: Node = mgr.spawn("fenny_magic_ball_att", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	_check(e1 != null and is_instance_valid(e1), "G1 spawn 返回实体")
	_check((events as Array).size() == 1 and str((events[0] as Dictionary).get("type_id", "")) == "fenny_magic_ball_att", "G2 SUMMON_SPAWNED 广播")
	mgr.despawn(e1, "manual")
	_check(not is_instance_valid(e1) or e1.is_queued_for_deletion(), "G3 despawn 注销")
	_check((events as Array).size() == 2 and str((events[1] as Dictionary).get("reason", "")) == "manual", "G4 SUMMON_DESPAWNED 广播（reason）")

	# ===== G2：上限与 set_active_limit =====
	var made: Array = []
	for i in range(8):
		var e: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2(i * 30, 0), {"owner_ref": owner_a})
		if e != null:
			made.append(e)
	_check((made as Array).size() == 2, "G5 默认上限=类型表 active_limit(2)（fail-closed 超限 null）")
	mgr.set_active_limit("shuimu_shark_att", 10)
	var e3: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	_check(e3 != null, "G6 set_active_limit(10) 放行第三条")
	mgr.set_active_limit("fenny_magic_ball_att", 10)
	var unknown: Node = mgr.spawn("no_such_type", owner_a.get_instance_id(), Vector2.ZERO)
	_check(unknown == null, "G7 未知类型 fail-closed（null）")

	# ===== G3：自动生成计时（固定步长确定性：5s=300 帧）=====
	var before: int = (mgr.get_summons_of(owner_a.get_instance_id()) as Array).size()
	mgr.register_auto_spawner(owner_a.get_instance_id(), "fenny_magic_ball_att", 5.0, {"owner_ref": owner_a})
	for i in range(299):
		mgr._physics_process(1.0 / 60.0)
	_check((mgr.get_summons_of(owner_a.get_instance_id()) as Array).size() == before, "G8 299 帧=未到 5s 不生成")
	mgr._physics_process(1.0 / 60.0)
	_check((mgr.get_summons_of(owner_a.get_instance_id()) as Array).size() == before + 1, "G9 第 300 帧=自动生成 1 个（无耗）")
	mgr.stop_auto_spawner(owner_a.get_instance_id())

	# ===== G4：潜地状态机+耗能 tick =====
	var shark: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	shark.enter_burrow()
	_check(str(shark.get("state")) == "burrowed", "G10 enter_burrow（攻鲨支持潜地）")
	var energy0: float = owner_a.spirit_energy
	for i in range(60):
		shark._physics_process(1.0 / 60.0)
	_check(owner_a.spirit_energy < energy0, "G11 潜地耗能 tick（1s 后能量下降）")
	shark.exit_burrow()
	_check(str(shark.get("state")) == "active", "G12 exit_burrow（能量未尽主动浮出）")
	var dshark: Node = mgr.spawn("shuimu_shark_def", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	dshark.enter_burrow()
	_check(str(dshark.get("state")) == "active", "G13 防御鲨不支持潜地（fail-closed）")

	# ===== G5：融合判定（F4 查询口）=====
	var fz = StubPathManager.new()
	fz.add_to_group("field_zone_managers")
	root.add_child(fz)
	var s1: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2(50, 0), {"owner_ref": owner_a})
	var s2: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2(70, 0), {"owner_ref": owner_a})
	var merged: Node = mgr.try_merge(s1, s2, "shuimu_shark_bomb")
	_check(merged != null and str(merged.get("summon_type")) == "shuimu_shark_bomb", "G14 快道内同族融合→产物型（MERGED 链）")
	fz.in_path = false
	var s3: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2(0, 0), {"owner_ref": owner_a})
	var s4: Node = mgr.spawn("shuimu_shark_att", owner_a.get_instance_id(), Vector2(20, 0), {"owner_ref": owner_a})
	var merged2: Node = mgr.try_merge(s3, s4, "shuimu_shark_bomb")
	_check(merged2 == null, "G15 F4 报不在路径=拒绝融合（fail-closed）")

	# ===== G6：拦截分发（快牙撕咬停球+限度）=====
	var ball: StubBall = StubBall.new()
	root.add_child(ball)
	ball.is_active = true
	var def1: Node = mgr.spawn("shuimu_shark_def", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	def1.on_ball_proximity(ball)
	_check(bool(ball.get("is_active")) == false, "G16 撕咬拦截：球停（is_active=false）")
	_check(str(def1.get("state")) == "active", "G17 限度内（第1次）撕咬留存")
	def1.on_ball_proximity(ball)
	_check(str(def1.get("state")) == "consumed", "G18 达 stop_limit(2)=撕咬消耗")

	# ===== G7：grant 分发（granter 组未接线=静默+消耗）=====
	var ball2: StubBall = StubBall.new()
	root.add_child(ball2)
	ball2.is_active = true
	ball2.owner_player = owner_a
	var defball: Node = mgr.spawn("fenny_magic_ball_def", owner_a.get_instance_id(), Vector2.ZERO, {"owner_ref": owner_a})
	defball.on_ball_proximity(ball2)
	_check(str(defball.get("state")) == "consumed", "G19 道具球触碰=兑换后消耗（granter 未接线静默不崩）")

	print("\n========== 结果：%d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
