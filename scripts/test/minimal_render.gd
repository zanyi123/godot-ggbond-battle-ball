extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 最小化模型测试 ===")
	# 创建 SubViewport
	var vp := SubViewport.new()
	vp.size = Vector2i(2560, 1440)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	await process_frame
	await process_frame
	await process_frame
	# 等待 world_3d 准备好
	var world: World3D = null
	for i in range(10):
		world = vp.world_3d
		if world:
			break
		await process_frame
	if world == null:
		push_error("world_3d 仍然 null")
		quit(1)
		return
	# 环境光
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	world.environment = env
	# 创建相机
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 1.0
	cam.far = 5000.0
	cam.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-45.0)), Vector3(0, 800, 800))
	cam.current = true
	vp.add_child(cam)
	print("相机位置: %s" % str(cam.global_position))
	# 创建地面（巨大平面）
	var ground := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(2000, 2000)
	ground.mesh = plane_mesh
	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.1, 0.6, 0.1)
	ground.material_override = g_mat
	ground.position = Vector3(0, 0, 0)
	vp.add_child(ground)
	# 创建测试盒 - 5 单位（参考）
	var test_box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(5, 5, 5)
	test_box.mesh = box_mesh
	var t_mat := StandardMaterial3D.new()
	t_mat.albedo_color = Color(1, 0, 0)  # 红
	test_box.material_override = t_mat
	test_box.position = Vector3(0, 2.5, 0)
	vp.add_child(test_box)
	# 创建参考柱 - 18 单位高（应等于 model height）
	var ref_column := MeshInstance3D.new()
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 1.0
	col_mesh.bottom_radius = 1.0
	col_mesh.height = 18.0
	ref_column.mesh = col_mesh
	var c_mat := StandardMaterial3D.new()
	c_mat.albedo_color = Color(0, 1, 0)  # 绿
	ref_column.material_override = c_mat
	ref_column.position = Vector3(-100, 9, 0)
	vp.add_child(ref_column)
	# 创建参考人物 - 用 CapsuleShape (高 18)
	var ref_capsule := MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 3.0
	cap_mesh.height = 18.0
	ref_capsule.mesh = cap_mesh
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0, 0, 1)  # 蓝
	ref_capsule.material_override = cap_mat
	ref_capsule.position = Vector3(100, 9, 0)
	vp.add_child(ref_capsule)
	await process_frame
	await process_frame
	# 报告所有模型的世界 AABB
	for c in vp.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var aabb: AABB = mi.get_global_aabb()
			print("  %s: AABB size=%s, pos=%s" % [c.name, str(aabb.size), str(c.position)])
	# 试图截图
	var tex: ViewportTexture = vp.get_texture()
	if tex:
		var img: Image = tex.get_image()
		if img:
			img.save_png("res://sim_results/minimal_test.png")
			print("✅ 截图保存: minimal_test.png (%dx%d)" % [img.get_width(), img.get_height()])
		else:
			print("❌ image null")
	else:
		print("❌ texture null")
	quit(0)
