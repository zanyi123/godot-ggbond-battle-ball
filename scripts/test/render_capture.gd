extends SceneTree

const SCENE_PATH := "res://scenes/test/player_3d_test.tscn"
const OUT_PNG := "res://sim_results/3d_actual_render.png"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 加载 3D 场景 ===")
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("无法加载场景")
		quit(1)
		return
	var root: Node = scene.instantiate()
	root.add_child.call_deferred(self.root) if false else null
	# 直接添加到主循环
	get_root().add_child.call_deferred(root)
	# 等加载
	await create_timer(2.0).timeout
	# 找 SubViewport
	var vp: SubViewport = _find_subviewport(root)
	if vp == null:
		push_error("找不到 SubViewport")
		quit(1)
		return
	print("找到 SubViewport: %s size=%s" % [vp.name, str(vp.size)])
	# 等几帧让场景完全渲染
	await process_frame
	await process_frame
	await process_frame
	# 保存纹理
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("无法获取 viewport image")
		quit(1)
		return
	img.save_png(OUT_PNG)
	print("✅ 截图已保存: %s (%dx%d)" % [OUT_PNG, img.get_width(), img.get_height()])
	# 同时打印关键节点状态
	_report_state(root)
	quit(0)


func _find_subviewport(node: Node) -> SubViewport:
	if node is SubViewport:
		return node
	for c in node.get_children():
		var found := _find_subviewport(c)
		if found:
			return found
	return null


func _report_state(root: Node) -> void:
	print("=== 节点状态 ===")
	# 找 _proxy_a/_proxy_b
	for prop in ["_proxy_a", "_proxy_b", "_ball_proxy_3d"]:
		var v = root.get(prop)
		if v:
			print("  %s: %s" % [prop, str(v)])
			if v is Node3D:
				var n3: Node3D = v
				print("    pos=%s scale=%s" % [str(n3.position), str(n3.scale)])
	# 找 ModelSlot
	if root.get("_proxy_a"):
		var pa: Node3D = root.get("_proxy_a")
		var slot: Node3D = pa.get_node_or_null("ModelSlot") as Node3D
		if slot:
			print("  ModelSlot.scale=%s" % str(slot.scale))
			for c in slot.get_children():
				if c is Node3D:
					var c3: Node3D = c
					print("    slot child '%s' scale=%s" % [c3.name, str(c3.scale)])
					var meshes = c.find_children("*", "MeshInstance3D", true, false)
					for m in meshes:
						if m is MeshInstance3D:
							var mi: MeshInstance3D = m
							if mi.mesh:
								print("      mesh '%s' AABB=%s vis=%s" % [mi.name, str(mi.mesh.get_aabb().size), str(mi.visible)])
