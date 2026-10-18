## 24号 B3 增补验收套件：三道具手持真实模型（CC0 外部模型优先+几何兜底，headless 可跑）
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_item_visual_3d.gd
## 覆盖：真实模型加载/尺寸归一/字标/未知道具 fail-closed/手位常量/UI 零判定
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

func _tag_text(vis: Node3D) -> String:
	var tag: Label3D = vis.get_node_or_null("ItemTag")
	return tag.text if tag != null else ""

func _run() -> void:
	print("\n========== 24号 B3 增补：三道具手持真实模型验收 ==========\n")
	for i in range(3):
		await process_frame
	var ItemScript: GDScript = load("res://scripts/battle3d/visual/item_visual_3d.gd")
	var BridgeScript: GDScript = load("res://scripts/battle3d/battle_arena_3d_bridge.gd")
	_assert(ItemScript != null, "ItemVisual3D 可加载（含语法/继承编译）")
	_assert(BridgeScript != null, "桥接层可加载（含手持挂接增量编译）")
	_assert(str(BridgeScript.source_code).contains("held"), "桥接层手持分支在位（held 旗标）")
	_assert(str(BridgeScript.source_code).contains("HAND_LOCAL_POS"), "桥接层挂球员代理手位")

	# ===== 三件真实模型（CC0 外部模型，加载优先；几何仅兜底）=====
	var expects := [["fenny_pan", "锅", 1], ["fenny_potion", "药", 1], ["fenny_firework", "烟花", 5]]
	for pair in expects:
		var vis: Node3D = ItemScript.new()
		root.add_child(vis)
		vis.setup(pair[0])
		await process_frame
		_assert(not vis._used_fallback, "%s: 真实模型加载成功（非几何兜底）" % pair[1])
		var holder: Node3D = vis.get_node_or_null("HandItem")
		_assert(holder != null and holder.get_child_count() >= int(pair[2]),
			"%s: 模型件数≥%d（烟花=五部件叠加）" % [pair[1], pair[2]])
		_assert(_tag_text(vis) == pair[1], "%s: 字标「%s」" % [pair[1], pair[1]])
		# 尺寸归一（显示层实例缩放，模型文件不动）
		var ab: AABB = vis._merged_aabb(vis)
		var target: float = ItemScript.TARGET_MAX_SIZE[pair[0]]
		var max_dim: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		_assert(max_dim <= target * 1.35 and max_dim >= target * 0.65,
			"%s: 尺寸归一（实测 %.1f ∈ [%.0f×0.65, ×1.35]）" % [pair[1], max_dim, target])

	# ===== 未知道具 fail-closed + 手位常量 =====
	var bad: Node3D = ItemScript.new()
	root.add_child(bad)
	bad.setup("fenny_unknown")
	await process_frame
	_assert(bad.get_child_count() == 0, "未知道具: fail-closed 不建形")
	_assert(ItemScript.HAND_LOCAL_POS == Vector3(20, 32, -16), "手位常量=球员代理本地 (20,32,-16)（右手前侧，-Z=默认相机可视侧）")
	_assert(ItemScript.MODEL_PATHS["fenny_firework"].size() == 5, "烟花=五部件路径表（Kenney 模块化叠加）")

	# ===== UI 零判定 grep（组件源码无发放/使用/账本写操作）=====
	var src: String = ItemScript.source_code
	var bad_patterns: Array[String] = ["grant_battle_item", "use_battle_item", "_ledger", "defend_intercept_ready =",
		"emit_event(", "subscribe(", "stamina", "spirit_energy"]
	var clean := true
	for pat in bad_patterns:
		if src.contains(pat):
			clean = false
			print("    命中写操作模式: " + pat)
	_assert(clean, "零判定: 道具模型源码无发放/使用/账本写操作（生命周期全走 bridge 只读消费）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
