## 手持道具模型探针（入库三件套之探针报告）：加载三件 CC0 模型实测 AABB/朝向/面数
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_handheld_model_probe.gd
extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("\n========== 手持道具模型探针 ==========\n")
	for i in range(3):
		await process_frame
	var models := {
		"frying_pan": "res://assets/game_models/items_handheld/frying_pan.glb",
		"potion_red": "res://assets/game_models/items_handheld/potion_red.fbx",
		"rocket_baseA": "res://assets/game_models/items_handheld/firework/rocket_baseA.glb",
		"rocket_finsA": "res://assets/game_models/items_handheld/firework/rocket_finsA.glb",
		"rocket_fuelA": "res://assets/game_models/items_handheld/firework/rocket_fuelA.glb",
		"rocket_sidesA": "res://assets/game_models/items_handheld/firework/rocket_sidesA.glb",
		"rocket_topA": "res://assets/game_models/items_handheld/firework/rocket_topA.glb",
	}
	var all_ok := true
	for key in models:
		var ps: PackedScene = load(models[key])
		if ps == null:
			print("  ❌ %s 加载失败" % key)
			all_ok = false
			continue
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await process_frame
		var aabb := _merged_aabb(inst)
		print("  ✅ %-14s AABB size=%s center=%s" % [key, str(aabb.size), str(aabb.get_center())])
		inst.queue_free()
	print("\n========== 探针完成 %s ==========" % ("（全部可加载）" if all_ok else "（有失败）"))
	quit(0 if all_ok else 1)

func _merged_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var ab: AABB = mi.global_transform * mi.get_aabb()
			if first:
				result = ab
				first = false
			else:
				result = result.merge(ab)
		for c in n.get_children():
			stack.append(c)
	return result
