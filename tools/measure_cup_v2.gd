## 步骤④诊断v2：用真实顶点搜索定杯心，绕开变换歧义
## 用法: godot --headless --path . -s res://tools/measure_cup_v2.gd
extends SceneTree

## Blender局部系实测：碗底(球接触点)与球心（y=身高方向）
const CUP_BOTTOM_BLENDER := Vector3(-0.463, 0.579, 0.038)
const CUP_BALLC_BLENDER := Vector3(-0.463, 0.654, 0.038)
## 头顶参考：Blender局部 y 最大 1.125
const HEAD_TOP_BLENDER := Vector3(0.0, 1.12, 0.0)

func _init() -> void:
	var pscene: PackedScene = load("res://assets/game_models/player2_base_cup.glb")
	if pscene == null:
		print("ERR load")
		quit(1)
		return
	var root: Node3D = pscene.instantiate()
	var mi: MeshInstance3D = _find_mesh(root)
	if mi == null:
		print("ERR no mesh")
		quit(1)
		return
	print("NODE=", mi.name, " rotation_deg=", mi.rotation_degrees, " scale=", mi.scale, " pos=", mi.position)
	var chain: Transform3D = _chain_to(root, mi)
	print("CHAIN basis_x=", chain.basis.x, " basis_y=", chain.basis.y, " basis_z=", chain.basis.z, " origin=", chain.origin)

	# 原始顶点（vertex-local 空间）
	var verts := _mesh_verts(mi.mesh)
	print("VERT_COUNT=", verts.size())

	# 顶点空间判定：在原始顶点里找 Blender 杯心底（若顶点空间=Blender局部必命中）
	var hit_bottom := _nearest(verts, CUP_BOTTOM_BLENDER)
	print("NEAREST_TO_CUPBOTTOM(raw) dist=", hit_bottom[1], " vert=", hit_bottom[0])
	var hit_head := _nearest(verts, HEAD_TOP_BLENDER)
	print("NEAREST_TO_HEADTOP(raw) dist=", hit_head[1], " vert=", hit_head[0])

	# 决定性输出：命中顶点过变换链 → slot空间（×70）
	if hit_bottom[1] < 0.03:
		var cup_slot: Vector3 = (chain * (hit_bottom[0] as Vector3)) * 70.0
		print("CUP_BOTTOM_IN_SLOT=", cup_slot)
		# 球心 = 碗底 + 球半径×0.75（向上。球缩放后半径见球测量）
	if hit_head[1] < 0.05:
		var head_slot: Vector3 = (chain * (hit_head[0] as Vector3)) * 70.0
		print("HEAD_TOP_IN_SLOT=", head_slot, " ← 验证直立性(y应≈78)")

	# 原始顶点 bbox（判顶点空间朝向）
	var bb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		bb = bb.expand(v)
	print("RAW_VERT_BBOX size=", bb.size, " (Blender局部应=(1.078,1.125,0.556): y=身高)")
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
		cur = _first_n3d_child(cur)
	return xf

func _first_n3d_child(n: Node) -> Node:
	for c in n.get_children():
		if c is Node3D:
			return c
	return null

func _mesh_verts(mesh: Mesh) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var am := mesh as ArrayMesh
	if am == null:
		return out
	for s in range(am.get_surface_count()):
		var arrays := am.surface_get_arrays(s)
		if arrays.size() > Mesh.ARRAY_VERTEX:
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in pv:
				out.append(v)
	return out

func _nearest(verts: Array[Vector3], target: Vector3) -> Array:
	var best: Vector3 = Vector3.ZERO
	var best_d: float = 1e9
	for v in verts:
		var d: float = v.distance_to(target)
		if d < best_d:
			best_d = d
			best = v
	return [best, best_d]
