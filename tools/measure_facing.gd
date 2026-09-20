## 模型本征朝向测定：脚尖方向（脚尖=脸方向）+ 手侧验证
## 用法: godot --headless --path . -s res://tools/measure_facing.gd
extends SceneTree

func _init() -> void:
	var pscene: PackedScene = load("res://assets/game_models/player2_base_cup.glb")
	var root: Node3D = pscene.instantiate()
	var mi: MeshInstance3D = _find_mesh(root)
	var chain: Transform3D = _chain_to(root, mi)
	var am := mi.mesh as ArrayMesh

	# 脚部顶点（slot y<7px≈0.1局部）的 z 分布：脚尖凸出方向=身体面向
	var foot_min_z := 1e9
	var foot_max_z := -1e9
	var foot_n := 0
	# 脸区（局部y 0.8~1.0 → slot y 56~70）z 质心：鼻唇侧 z 更正
	var face_sum_z := 0.0
	var face_n := 0
	# 双手顶点云 x 范围（slot y 35~45 臂带）
	var x_min := 1e9
	var x_max := -1e9
	for s in range(am.get_surface_count()):
		var arrays := am.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in pv:
			var sp: Vector3 = chain * v
			if sp.y < 0.1 and absf(sp.x) < 0.25:
				foot_min_z = minf(foot_min_z, sp.z)
				foot_max_z = maxf(foot_max_z, sp.z)
				foot_n += 1
			if sp.y >= 0.80 and sp.y <= 1.00 and absf(sp.x) < 0.18:
				face_sum_z += sp.z
				face_n += 1
			if sp.y >= 0.50 and sp.y <= 0.64:
				x_min = minf(x_min, sp.x)
				x_max = maxf(x_max, sp.x)
	print("FOOT(脚部) n=%d z_range=[%.2f, %.2f] → 脚尖朝 %s" % [
		foot_n, foot_min_z, foot_max_z,
		"+Z" if absf(foot_max_z) > absf(foot_min_z) else "-Z"])
	if face_n > 0:
		print("FACE区 z质心=%.3f (n=%d) → 脸朝 %s" % [face_sum_z / face_n, face_n,
			"+Z" if face_sum_z > 0.0 else "-Z"])
	print("ARMBAND(臂带y35-45) x范围=[%.2f, %.2f] → 杯型手在 %s 侧" % [
		x_min, x_max, "-X(左)" if x_min < 0 else "+X"])
	quit(0)

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null

func _chain_to(root: Node3D, target: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cur: Node = root
	var guard := 0
	while guard < 10 and cur != null:
		guard += 1
		if cur is Node3D:
			xf = xf * (cur as Node3D).transform
		if cur == target:
			break
		var nxt: Node = null
		for c in cur.get_children():
			if c is Node3D:
				nxt = c
				break
		cur = nxt
	return xf
