extends SceneTree

const SCENE_PATH := "res://scenes/test/player_3d_test.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 加载场景并报告默认相机状态 ===")
	var scene: PackedScene = load(SCENE_PATH)
	var root: Node = scene.instantiate()
	get_root().add_child(root)
	# 等场景完全加载
	await process_frame
	await process_frame
	await process_frame
	await create_timer(1.0).timeout
	await process_frame
	# 报告相机
	if root.get("_big_camera"):
		var cam: Camera3D = root.get("_big_camera")
		print("=== Camera3D (默认 ANGLED 模式) ===")
		print("  position: %s" % str(cam.position))
		print("  global_position: %s" % str(cam.global_position))
		print("  fov: %s" % str(cam.fov))
		print("  size: %s (ortho)" % str(cam.size))
		print("  projection: %s (0=perspective, 1=ortho)" % str(cam.projection))
		print("  transform.origin: %s" % str(cam.transform.origin))
		# 打印 forward 方向
		var forward: Vector3 = -cam.global_transform.basis.z
		print("  forward direction: %s" % str(forward.normalized()))
		# 算到模型 A 的实际可视角度
		var pa_pos: Vector3 = root.get("_proxy_a").global_position
		var pa_to_cam: Vector3 = cam.global_position - pa_pos
		print("  pa_to_cam: %s (length %.1f)" % [str(pa_to_cam), pa_to_cam.length()])
		# 模型 world AABB
		var pa: Node3D = root.get("_proxy_a")
		var slot: Node3D = pa.get_node_or_null("ModelSlot") as Node3D
		if slot:
			var combined_aabb: AABB = AABB()
			var first: bool = true
			for c in slot.get_children():
				if c is Node3D:
					for m in c.find_children("*", "MeshInstance3D", true, false):
						if m is MeshInstance3D and m.visible:
							var mi: MeshInstance3D = m
							if mi.mesh:
								var wb: AABB = mi.get_global_aabb()
								if first:
									combined_aabb = wb
									first = false
								else:
									combined_aabb = combined_aabb.merge(wb)
			if not first:
				print("  ModelSlot combined AABB:")
				print("    min: %s" % str(combined_aabb.position))
				print("    max: %s" % str(combined_aabb.end))
				print("    size: %s" % str(combined_aabb.size))
	# 报告 proxy
	for prop in ["_proxy_a", "_proxy_b", "_ball_proxy_3d"]:
		var v = root.get(prop)
		if v and v is Node3D:
			var n3: Node3D = v
			print("  %s: pos=%s global_pos=%s scale=%s" % [prop, str(n3.position), str(n3.global_position), str(n3.scale)])
	# 计算模型在屏幕上的投影
	if root.get("_big_camera") and root.get("_proxy_a"):
		var cam3: Camera3D = root.get("_big_camera")
		var pa3: Node3D = root.get("_proxy_a")
		var slot3: Node3D = pa3.get_node_or_null("ModelSlot") as Node3D
		if slot3:
			# 找最大的 mesh
			for c in slot3.get_children():
				if c is Node3D:
					for m in c.find_children("*", "MeshInstance3D", true, false):
						if m is MeshInstance3D and m.visible:
							var mi: MeshInstance3D = m
							if mi.mesh:
								var w_aabb: AABB = mi.get_global_aabb()
								# 投影中心到屏幕
								var center_3d: Vector3 = w_aabb.get_center()
								var center_2d: Vector2 = cam3.unproject_position(center_3d)
								# 8 个角点投影
								var corners: Array[Vector3] = [
									Vector3(w_aabb.position.x, w_aabb.position.y, w_aabb.position.z),
									Vector3(w_aabb.end.x, w_aabb.position.y, w_aabb.position.z),
									Vector3(w_aabb.position.x, w_aabb.end.y, w_aabb.position.z),
									Vector3(w_aabb.position.x, w_aabb.position.y, w_aabb.end.z),
									Vector3(w_aabb.end.x, w_aabb.end.y, w_aabb.position.z),
									Vector3(w_aabb.end.x, w_aabb.position.y, w_aabb.end.z),
									Vector3(w_aabb.position.x, w_aabb.end.y, w_aabb.end.z),
									Vector3(w_aabb.end.x, w_aabb.end.y, w_aabb.end.z),
								]
								var projected: Array[Vector2] = []
								for c2 in corners:
									projected.append(cam3.unproject_position(c2))
								var min_s: Vector2 = projected[0]
								var max_s: Vector2 = projected[0]
								for p in projected:
									min_s.x = min(min_s.x, p.x)
									min_s.y = min(min_s.y, p.y)
									max_s.x = max(max_s.x, p.x)
									max_s.y = max(max_s.y, p.y)
								print("  %s: world center %s → screen center %s" % [mi.name, str(center_3d), str(center_2d)])
								print("    world AABB size: %s" % str(w_aabb.size))
								print("    screen 投影 X: %.1f-%.1f (宽 %.1f px) Y: %.1f-%.1f (高 %.1f px)" % [min_s.x, max_s.x, max_s.x - min_s.x, min_s.y, max_s.y, max_s.y - min_s.y])
	# 报告 BigCamActive
	if root.get("_big_cam_active") != null:
		print("  _big_cam_active: %s" % str(root.get("_big_cam_active")))
	quit(0)
