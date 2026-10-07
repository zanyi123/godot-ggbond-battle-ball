## 24号验收套件：两队基础UI桥接检验（水鲨鱼/魔术白球 3D 代理通道；headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_summon_visual_bridge.gd
## 覆盖：桥接自动挂出（SUMMON_SPAWNED 事件）/kind 分型/鲨鱼三态（遁地/融合）/魔术球轮廓色/
##       despawn 清理/撒点确定性——技能本体落地前后都可用（stub 实体驱动，UI 链路独立验收）
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

func _make_entity(stub_script: GDScript, stype: String, kind: String, pos: Vector2) -> Node2D:
	var ent: Node2D = stub_script.new()
	ent.summon_type = stype
	ent._tdef = {"kind": kind}
	ent.position = pos
	root.add_child(ent)
	return ent

func _run() -> void:
	print("\n========== 24号：两队基础UI桥接检验 ==========\n")
	for i in range(3):
		await process_frame  # 等 autoload 就位
	var StubScript: GDScript = load("res://scripts/test3d/regression/test_stub_summon_entity.gd")
	var SharkScript: GDScript = load("res://scripts/battle3d/visual/shark_visual_3d.gd")
	var BallScript: GDScript = load("res://scripts/battle3d/visual/magic_ball_visual_3d.gd")
	var BridgeScript: GDScript = load("res://scripts/battle3d/battle_arena_3d_bridge.gd")
	var BusScript: GDScript = load("res://scripts/systems/event_bus/event_bus.gd")
	_assert(SharkScript != null and BallScript != null and BridgeScript != null, "美术两件+bridge 可加载（含语法编译）")

	# 最小桥接环境：真事件总线入组 + bridge 手动供 _world（不跑完整 setup，只验召唤通道）
	var bus: Node = BusScript.new()
	bus.add_to_group("battle_event_bus")
	root.add_child(bus)
	var bridge: Node = Node.new()
	bridge.set_script(BridgeScript)
	var world: Node3D = Node3D.new()
	bridge._world = world
	root.add_child(world)
	root.add_child(bridge)
	await process_frame

	# --- 水鲨鱼（快牙猎杀 att 型）spawn 事件→桥接自动挂出 ---
	bridge._sync_summons()  # 手动触发一次懒订阅（完整 _process 需 battle_mgr，套件最小环境不供）
	var shark: Node2D = _make_entity(StubScript, "shuimu_shark_att", "shark", Vector2(100.0, 200.0))
	bus.emit_event(bus.GameEvent.SUMMON_SPAWNED, {"type_id": "shuimu_shark_att", "owner_id": 1, "node": shark})
	await process_frame
	_assert(bridge._summon_proxies.size() == 1, "桥接: SUMMON_SPAWNED→鲨鱼代理自动挂出")
	var shark_proxy: Node3D = bridge._summon_proxies.values()[0] if bridge._summon_proxies.size() == 1 else null
	_assert(shark_proxy != null and shark_proxy.get_script() == SharkScript, "桥接: kind=shark 分型正确（SharkVisual3D）")
	bridge._sync_summons()  # 手动触发贴位姿段（同上，最小环境无 _process 门控）
	_assert(shark_proxy.global_position.is_equal_approx(Vector3(100.0, 0.0, 200.0)), "桥接: 位姿 (x,0,y) 1:1")
	# D12 方向断言：2D 角→3D rotation.y 取负（同向映射），防镜像回潮
	shark.rotation = 0.7
	bridge._sync_summons()
	_assert(absf(shark_proxy.rotation.y + 0.7) < 0.001, "桥接: 旋转取负同向（2D 0.7 → 3D -0.7，D12）")

	# --- 遁地态：半透明+下沉 ---
	shark.state = "burrowed"
	await process_frame
	var body: Node3D = shark_proxy.get_node_or_null("SharkBody")
	var bmat: StandardMaterial3D = (shark_proxy.get("trunk_mat") if shark_proxy.get("trunk_mat") != null else null)
	# 美术件材质为私有——以位置与 alpha 行为断言（读 _body_mat 兜底）
	var mat = shark_proxy.get("_body_mat")
	_assert(body != null and absf(body.position.y + 12.0) < 0.5, "鲨鱼: 遁地下沉 50%（-12）")
	_assert(mat != null and absf(mat.albedo_color.a - 0.5) < 0.01, "鲨鱼: 遁地半透明 alpha=0.5")
	shark.state = "active"
	await process_frame
	_assert(mat != null and mat.albedo_color.a > 0.99, "鲨鱼: 回到游走态不透明")

	# --- 融合态（组合鲨鱼炸弹 bomb 型）：金红+放大 1.6 ---
	var bomb: Node2D = _make_entity(StubScript, "shuimu_shark_bomb", "shark", Vector2(-50.0, 0.0))
	bomb._tdef = {"kind": "shark"}
	# 美术件按 summon_type 含 bomb 判融合
	bus.emit_event(bus.GameEvent.SUMMON_SPAWNED, {"type_id": "shuimu_shark_bomb", "owner_id": 1, "node": bomb})
	await process_frame
	_assert(bridge._summon_proxies.size() == 2, "桥接: 融合鲨鱼第二代理挂出")
	var bomb_proxy: Node3D = bridge._summon_proxies[bomb]
	var bomb_body: Node3D = bomb_proxy.get_node_or_null("SharkBody")
	_assert(bomb_body != null and absf(bomb_body.scale.x - 1.6) < 0.01, "鲨鱼: 融合态放大 ×1.6")
	var bmat2 = bomb_proxy.get("_body_mat")
	_assert(bmat2 != null and bmat2.albedo_color.r > 0.9 and bmat2.albedo_color.g > 0.4, "鲨鱼: 融合态金红变色")

	# --- 魔术白球：攻=红环 / 守=蓝环 ---
	var ball_att: Node2D = _make_entity(StubScript, "fenny_magic_ball_att", "magic_ball", Vector2(0.0, 100.0))
	bus.emit_event(bus.GameEvent.GameEvent if false else bus.GameEvent.SUMMON_SPAWNED, {"type_id": "fenny_magic_ball_att", "owner_id": 2, "node": ball_att})
	var ball_def: Node2D = _make_entity(StubScript, "fenny_magic_ball_def", "magic_ball", Vector2(0.0, -100.0))
	bus.emit_event(bus.GameEvent.SUMMON_SPAWNED, {"type_id": "fenny_magic_ball_def", "owner_id": 3, "node": ball_def})
	await process_frame
	_assert(bridge._summon_proxies.size() == 4, "桥接: 攻/守魔术球两代理挂出")
	var att_proxy: Node3D = bridge._summon_proxies[ball_att]
	var def_proxy: Node3D = bridge._summon_proxies[ball_def]
	_assert(att_proxy.get_script() == BallScript and def_proxy.get_script() == BallScript, "桥接: kind=magic_ball 分型正确")
	var att_ring = att_proxy.get("_ring_mat")
	var def_ring = def_proxy.get("_ring_mat")
	_assert(att_ring != null and att_ring.albedo_color.r > 0.8 and att_ring.albedo_color.g < 0.4, "魔术球: 攻=红环")
	_assert(def_ring != null and def_ring.albedo_color.b > 0.8, "魔术球: 守=蓝环")

	# --- despawn 清理 ---
	bus.emit_event(bus.GameEvent.SUMMON_DESPAWNED, {"type_id": "shuimu_shark_bomb", "owner_id": 1, "node": bomb, "reason": "consumed"})
	await process_frame
	_assert(not bridge._summon_proxies.has(bomb) and bridge._summon_proxies.size() == 3, "桥接: despawn→代理清理")

	# --- 撒点确定性（美术件助手）---
	var a: Array = BallScript.scatter_positions(5, 20261001)
	var b: Array = BallScript.scatter_positions(5, 20261001)
	var c: Array = BallScript.scatter_positions(5, 777)
	_assert(a.size() == 5 and str(a) == str(b), "撒点: 同种子逐点可复现")
	_assert(str(a) != str(c), "撒点: 异种子分布不同")
	var in_bounds := true
	for p in a:
		if absf(p.x) > 510.0 or absf(p.y) > 325.0:
			in_bounds = false
	_assert(in_bounds, "撒点: 全落外场边界 ±510/±325 内")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
