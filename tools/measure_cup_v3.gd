## 步骤④终极定位：从网格顶点云直接算右手杯腔质心（slot空间真值）
## 用法: godot --headless --path . -s res://tools/measure_cup_v3.gd
extends SceneTree

func _init() -> void:
	var pscene: PackedScene = load("res://assets/game_models/player2_base_cup.glb")
	if pscene == null:
		print("ERR load cup")
		quit(1)
		return
	var root: Node3D = pscene.instantiate()
	var mi: MeshInstance3D = _find_mesh(root)
	if mi == null:
		print("ERR no mesh")
		quit(1)
		return
	# 顶点 → slot 空间的变换链（root→mesh 的累积 transform）
	var chain: Transform3D = _chain_to(root, mi)
	print("CHAIN=", chain)

	var am := mi.mesh as ArrayMesh
	var cup_sum := Vector3.ZERO
	var cup_n := 0
	# 右手杯腔判定（Blender局部语义）：x∈[-0.52,-0.40](右手), 高度 y∈[0.545,0.65](手指卷区), 排除拇指外缘
	# slot 空间反推：lx=slot.x, ly=slot.y, lz=-slot.z（由 chain 实测反变换语义）
	var right_min_x := 1e9
	var right_max_x := -1e9
	for s in range(am.get_surface_count()):
		var arrays := am.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in pv:
			var sp: Vector3 = chain * v
			# 用 slot.x=lx, slot.y=ly 高度, slot.z=-lz 语义筛选
			var lx: float = sp.x
			var ly: float = sp.y
			if lx >= -0.52 and lx <= -0.40 and ly >= 0.545 and ly <= 0.65:
				cup_sum += sp
				cup_n += 1
			if ly >= 0.52 and ly <= 0.60 and lx < 0:
				right_min_x = min(right_min_x, sp.x)
				right_max_x = max(right_max_x, sp.x)
	print("CUP_REGION_COUNT=", cup_n)
	if cup_n > 0:
		var cup_center: Vector3 = (cup_sum / float(cup_n)) * 70.0
		print("CUP_CENTER_SLOT(px)=", cup_center)
		# 球心 = 碗底接触面上方。杯腔顶面≈区域 y 上界。取球心=质心即可（质心已在碗腔内）
		print("SUGGEST_HAND_OFFSET=", cup_center)
	print("RIGHT_ARM_X_RANGE(slot, height0.52-0.60)=", right_min_x * 70.0, " ~ ", right_max_x * 70.0)
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
