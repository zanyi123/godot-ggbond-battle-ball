## 25号随行美术·平台集成核查：测试平台环境（真实 battle_arena）→ 召唤物模型自动点亮
## 模拟技能侧真实调用路径：summon_manager.spawn（同 F1 域调用口径）→ SUMMON 事件 → 桥接代理
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_visual_platform.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)


func _find_bridge(arena: Node) -> Node:
	for child in arena.get_children():
		if child.get_script() != null and str((child.get_script() as GDScript).resource_path).ends_with("battle_arena_3d_bridge.gd"):
			return child
	return null


func _run() -> void:
	print("\n========== 25号：测试平台召唤物模型链路核查 ==========\n")
	for i in range(3):
		await process_frame
	var ArenaScene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = ArenaScene.instantiate()
	root.add_child(arena)
	await create_timer(1.5).timeout

	# ===== 平台三件套在位 =====
	var bridge: Node = arena.get_node_or_null("BattleArena3DBridge")
	_assert(bridge != null, "平台环境: 3D 桥 BattleArena3DBridge 在位（USE_3D_SCENE 非 sim 常驻=--fullai/F6 同环境）")
	var sm: Node = get_first_node_in_group("summon_managers")
	_assert(sm != null, "平台环境: summon_manager 已挂 battle_manager（23-F1）")
	var bus: Node = get_first_node_in_group("battle_event_bus")
	_assert(bus != null, "平台环境: battle_event_bus 在组（桥的订阅源）")
	if bridge == null or sm == null or bus == null:
		print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
		quit(1)
		return

	# ===== 桥懒订阅已建立 =====
	await process_frame
	await process_frame
	_assert(bridge._summon_bus == bus, "桥订阅: 懒查找已锁定平台事件总线")
	var listeners: Array = bus._listeners.get(bus.GameEvent.SUMMON_SPAWNED, [])
	_assert(listeners.size() >= 1, "桥订阅: SUMMON_SPAWNED 至少 1 个监听者（桥回调在列）")

	# ===== 模拟技能侧真实调用：spawn 攻鲨（F1 域调用口径=summon_manager.spawn）=====
	var player: Node2D = arena.team_a_players[0]
	var owner_id: int = player.get_instance_id()
	var shark: Node = sm.spawn("shuimu_shark_att", owner_id, player.global_position, {"owner_ref": player, "skill_id": "shuimu_1"})
	_assert(shark != null, "spawn: shuimu_shark_att 生成成功（类型表加载正常）")
	var ball: Node = sm.spawn("fenny_magic_ball_att", owner_id, player.global_position + Vector2(120, 0), {"owner_ref": player, "skill_id": "fenny_2"})
	_assert(ball != null, "spawn: fenny_magic_ball_att 生成成功")
	await process_frame
	await process_frame

	# ===== 模型自动点亮（事件路径）=====
	var proxies: Dictionary = bridge._summon_proxies
	_assert(proxies.has(shark) and proxies.has(ball), "点亮: 两实体均被桥挂上 3D 代理（事件订阅生效）")
	var shark_proxy: Node3D = proxies.get(shark)
	var ball_proxy: Node3D = proxies.get(ball)
	if shark_proxy != null and ball_proxy != null:
		var shark_path := str((shark_proxy.get_script() as GDScript).resource_path)
		var ball_path := str((ball_proxy.get_script() as GDScript).resource_path)
		_assert(shark_path.ends_with("shark_visual_3d.gd"), "分型: 鲨鱼→shark_visual_3d.gd（kind=shark）")
		_assert(ball_path.ends_with("magic_ball_visual_3d.gd"), "分型: 白球→magic_ball_visual_3d.gd（kind=magic_ball）")
		await process_frame
		_assert(shark_proxy.global_position == Vector3(shark.global_position.x, 0.0, shark.global_position.y),
			"贴位: 鲨鱼代理=实体位 (x,0,y) 1:1")
		_assert(ball_proxy.global_position == Vector3(ball.global_position.x, 0.0, ball.global_position.y),
			"贴位: 白球代理=实体位 (x,0,y) 1:1")
		_assert(ball_proxy._ring_mat.albedo_color == ball_proxy.ATTACK_RING_COLOR, "显示: 平台内攻球=红环")

	# ===== 实体移动→代理跟帧（游走/操控显示）=====
	shark.global_position += Vector2(60, -40)
	await process_frame
	await process_frame
	var sp: Node3D = bridge._summon_proxies.get(shark)
	_assert(sp != null and sp.global_position == Vector3(shark.global_position.x, 0.0, shark.global_position.y), "跟帧: 实体位移后代理同步（1:1）")

	# ===== 注销→代理清理 =====
	sm.despawn(shark, "manual")
	await process_frame
	await process_frame
	_assert(not bridge._summon_proxies.has(shark), "清理: despawn 事件→鲨鱼代理已移除")
	_assert(not is_instance_valid(shark) or shark.is_queued_for_deletion(), "清理: 2D 实体由召唤系统注销（判定层既有职责）")

	# ===== 平台自动生成路径（魔术无上限技的定时生成器=register_auto_spawner）=====
	sm.register_auto_spawner(owner_id, "fenny_magic_ball_def", 0.05, {"owner_ref": player, "skill_id": "fenny_1"})
	for i in range(30):
		await process_frame
	sm.stop_auto_spawner(owner_id)
	var def_found := false
	var def_proxy_ok := false
	for ent in bridge._summon_proxies:
		if is_instance_valid(ent) and str(ent.get("summon_type")) == "fenny_magic_ball_def":
			def_found = true
			var dp: Node3D = bridge._summon_proxies[ent]
			if dp != null and is_instance_valid(dp) and dp._ring_mat.albedo_color == dp.DEFEND_RING_COLOR:
				def_proxy_ok = true
	_assert(def_found, "自动生成: 定时生成器产守白球→代理点亮（魔术无上限技路径）")
	_assert(def_proxy_ok, "显示: 守白球=蓝环")

	# ===== 平台环境零污染：spawn/despawn 全走公开 API，2D 层数据未越权 =====
	_assert(int(sm._live.size()) == bridge._summon_proxies.size(), "一致性: 在场实体数=代理数（无孤儿代理/无漏挂）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	root.remove_child(arena)   # 显式释放 arena（防退出泄漏：场景树残留资源）
	arena.free()
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
