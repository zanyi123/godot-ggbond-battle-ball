## D14 验收套件：快道放置预览与释放语义（headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_zone_path_preview.gd
## 覆盖（2026-10-04 主人裁定 D14）：释放点纯函数/预览 600×宽固定/单击释放=从施法者朝瞄准方向
## 铺开固定长道/释放后固定/3D 主轨预览镜像（位姿取负+尺寸镜像+非放置态隐藏）
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

class StubManager extends Node:
	var created: Array = []
	var zone_params_seen: Dictionary = {}
	func create_zone(params: Dictionary, pos: Vector2) -> Area2D:
		created.append(pos)
		zone_params_seen = params
		return null

class StubBattleMgr extends Node2D:
	var field_zone_manager: Node = null  # bridge._sync_zone_preview 经 get() 读取

func _run() -> void:
	print("\n========== D14：快道预览与释放语义验收 ==========\n")
	for i in range(3):
		await process_frame
	# placer 预览挂 current_scene（-s 环境需自设）
	var holder: Node = Node.new()
	root.add_child(holder)
	current_scene = holder
	var PlacerScript: GDScript = load("res://scripts/battle/field_zone_placer.gd")
	var BridgeScript: GDScript = load("res://scripts/battle3d/battle_arena_3d_bridge.gd")
	_assert(PlacerScript != null and BridgeScript != null, "placer/bridge 可加载（含语法编译）")

	# --- 释放点纯函数 ---
	var a: Dictionary = PlacerScript.path_release_points(Vector2(0, 0), Vector2(300, 0))
	_assert(a["from"].is_equal_approx(Vector2.ZERO) and a["to"].is_equal_approx(Vector2(600, 0)), "纯函数: 右向瞄准→600 固定长")
	var b: Dictionary = PlacerScript.path_release_points(Vector2(100, 100), Vector2(100, 100))
	_assert(b["to"].is_equal_approx(Vector2(700, 100)), "纯函数: 瞄准点与自身重合→退化朝正右（fail-closed）")
	var c: Dictionary = PlacerScript.path_release_points(Vector2.ZERO, Vector2(0, -50), 300.0)
	_assert(c["to"].is_equal_approx(Vector2(0, -300)), "纯函数: 上向瞄准→朝上铺开（方向归一）")

	# --- 预览 600×宽 固定 + 单击释放语义 ---
	var owner_node: Node2D = Node2D.new()
	owner_node.position = Vector2(1000, 1000)  # 场上任意施法者位
	holder.add_child(owner_node)
	var mgr: StubManager = StubManager.new()
	holder.add_child(mgr)
	var placer: Node = PlacerScript.new()
	mgr.add_child(placer)  # _get_manager 经 parent 直取
	placer.start_placing({"zone_type": 6, "path_width": 48.0, "mouse_ops": 1, "owner_node": owner_node}, 1)
	await process_frame
	var pv: Node2D = placer.get("preview_node")
	_assert(pv != null and is_instance_valid(pv), "预览: 放置模式预览节点已建")
	var fill: ColorRect = placer.get("_preview_fill")
	_assert(fill != null and absf(fill.size.x - 600.0) < 0.01 and absf(fill.size.y - 48.0) < 0.01, "预览: 固定 600×path_width（不随鼠标拉伸）")
	# 预览锚定施法者（_process 手动驱动；-s 环境鼠标在 (0,0) 中心口径）
	placer._process(0.016)
	var want_center: Vector2 = owner_node.global_position + (Vector2.ZERO - owner_node.global_position).normalized() * 300.0
	_assert(pv.global_position.distance_to(want_center) < 1.0, "预览: 锚定施法者+朝瞄准方向半长跟随")
	# 单击释放（显式瞄准点，绕开 viewport 鼠标）
	placer._place_zone(Vector2(1600, 1000))
	_assert(mgr.created.size() == 1, "释放: 单击即生成（不再两次点击）")
	_assert(mgr.zone_params_seen.get("path_from", Vector2()).is_equal_approx(Vector2(1000, 1000)), "释放: path_from=施法者位置")
	_assert(mgr.zone_params_seen.get("path_to", Vector2()).is_equal_approx(Vector2(1600, 1000)), "释放: path_to=瞄准方向 600 铺开")
	_assert(not placer.is_operating(), "释放: mouse_ops=1 用后操作收尾（位置固定不跟人）")
	_assert(placer.get("preview_node") == null, "释放: 预览消失")

	# --- 3D 主轨预览镜像 ---
	var bridge: Node = Node.new()
	bridge.set_script(BridgeScript)
	var world: Node3D = Node3D.new()
	bridge._world = world
	var bmgr: StubBattleMgr = StubBattleMgr.new()  # bridge.battle_mgr 声明为 Node2D
	var zm: Node = Node.new()
	bmgr.field_zone_manager = zm
	holder.add_child(zm)
	holder.add_child(bmgr)
	bridge.battle_mgr = bmgr
	holder.add_child(world)
	holder.add_child(bridge)
	await process_frame
	# 放置中→镜像可见（真实 placer 挂 zm 下命名 FieldZonePlacer=bridge 查找口径）
	var placer2: Node = PlacerScript.new()
	placer2.name = "FieldZonePlacer"
	zm.add_child(placer2)
	placer2.start_placing({"zone_type": 6, "path_width": 48.0, "mouse_ops": 1, "owner_node": owner_node}, 1)
	placer2._process(0.016)
	bridge._sync_zone_preview()
	var proxy: MeshInstance3D = bridge.get("_zone_preview_proxy")
	_assert(proxy != null and proxy.visible, "3D预览: 放置中可见")
	_assert(absf((proxy.mesh as BoxMesh).size.x - 600.0) < 0.01 and absf((proxy.mesh as BoxMesh).size.z - 48.0) < 0.01, "3D预览: 尺寸镜像 600×48")
	_assert(absf(proxy.rotation.y + (placer2.get("preview_node") as Node2D).rotation) < 0.001, "3D预览: 旋转取负同向（D12 口径）")
	var pv2: Node2D = placer2.get("preview_node")
	_assert(proxy.global_position.x == pv2.global_position.x and proxy.global_position.z == pv2.global_position.y and absf(proxy.global_position.y - 1.0) < 0.01, "3D预览: 位姿 (x,1,y) 镜像贴地")
	# 取消→隐藏
	placer2.cancel_operation()
	bridge._sync_zone_preview()
	_assert(not proxy.visible, "3D预览: 非放置态隐藏")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
