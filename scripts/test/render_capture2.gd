extends SceneTree

const SCENE_PATH := "res://scenes/test/player_3d_test.tscn"
const OUT_PNG := "res://sim_results/3d_render_now.png"
const OUT_PNG_TOP := "res://sim_results/3d_render_top.png"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 加载 3D 场景 ===")
	var scene: PackedScene = load(SCENE_PATH)
	var root: Node = scene.instantiate()
	get_root().add_child(root)
	# 等几帧加载完成
	await process_frame
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	await process_frame
	var vp: SubViewport = _find_subviewport(root)
	if vp == null:
		push_error("找不到 SubViewport")
		quit(1)
		return
	print("SubViewport: %s size=%s" % [vp.name, str(vp.size)])
	# 强制渲染一次
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	await process_frame
	# 截 ANGLED 视角
	_save_vp(vp, OUT_PNG, "ANGLED")
	# 切到俯视
	root.set("_camera_mode", 0)  # TOP_DOWN
	root.call("_apply_big_camera_mode", 0)
	await process_frame
	await process_frame
	_save_vp(vp, OUT_PNG_TOP, "TOP_DOWN")
	# 报告节点状态
	_report(root)
	# 报告相机状态
	if root.get("_big_camera"):
		var cam: Camera3D = root.get("_big_camera")
		print("=== Camera3D 状态 ===")
		print("  position: %s" % str(cam.position))
		print("  global_position: %s" % str(cam.global_position))
		print("  fov: %s" % str(cam.fov))
		print("  size: %s (ortho)" % str(cam.size))
		print("  projection: %s" % str(cam.projection))
		print("  transform.basis: %s" % str(cam.transform.basis))
	# 计算 model 在 screen 上的预期大小
	var pa: Node3D = root.get("_proxy_a")
	if pa and root.get("_big_camera"):
		var cam2: Camera3D = root.get("_big_camera")
		var model_world_pos: Vector3 = pa.global_position
		var dist: float = cam2.global_position.distance_to(model_world_pos)
		print("=== 视觉估算 ===")
		print("  proxy_a global_pos: %s" % str(model_world_pos))
		print("  cam distance to model: %.1f" % dist)
		print("  model height (estimated): 17.8")
		print("  fov: %.1f" % cam2.fov)
		if cam2.projection == Camera3D.PROJECTION_PERSPECTIVE:
			var model_screen_pixels: float = 17.8 / (dist * tan(deg_to_rad(cam2.fov / 2.0))) * 1440.0
			print("  expected model height on 1440-tall viewport: %.1f px" % model_screen_pixels)
	quit(0)


func _save_vp(vp: SubViewport, path: String, label: String) -> void:
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		print("[%s] ❌ texture null" % label)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("[%s] ❌ image null" % label)
		return
	img.save_png(path)
	print("[%s] ✅ 保存: %s (%dx%d)" % [label, path, img.get_width(), img.get_height()])


func _find_subviewport(n: Node) -> SubViewport:
	if n is SubViewport:
		return n
	for c in n.get_children():
		var f := _find_subviewport(c)
		if f:
			return f
	return null


func _report(root: Node) -> void:
	print("=== 节点状态 ===")
	for prop in ["_proxy_a", "_proxy_b", "_ball_proxy_3d"]:
		var v = root.get(prop)
		if v and v is Node3D:
			var n3: Node3D = v
			print("  %s: pos=%s scale=%s" % [prop, str(n3.position), str(n3.scale)])
			var slot: Node3D = n3.get_node_or_null("ModelSlot") as Node3D
			if slot:
				print("    ModelSlot.scale=%s children=%d" % [str(slot.scale), slot.get_child_count()])
				for c in slot.get_children():
					if c is Node3D:
						var c3: Node3D = c
						print("      child '%s' scale=%s" % [c3.name, str(c3.scale)])
						var meshes = c.find_children("*", "MeshInstance3D", true, false)
						for m in meshes:
							if m is MeshInstance3D:
								var mi: MeshInstance3D = m
								if mi.mesh:
									var visible = mi.visible
									print("        mesh '%s' AABB=%s vis=%s" % [mi.name, str(mi.mesh.get_aabb().size), str(visible)])
			var hp: Node3D = n3.get_node_or_null("HandProxy") as Node3D
			if hp:
				print("    HandProxy global_pos=%s local_pos=%s" % [str(hp.global_position), str(hp.position)])
