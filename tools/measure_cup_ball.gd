## 步骤④诊断：headless 实测杯型GLB变换链 + 球模型原生尺寸
## 用法: godot --headless --path . -s res://tools/measure_cup_ball.gd
extends SceneTree

const CUP_LOCAL := Vector3(-0.463, 0.654, 0.038)  ## Blender实测杯心球位（局部）

func _init() -> void:
	# ---- 1. 杯型GLB 变换链 ----
	var pscene: PackedScene = load("res://assets/game_models/player2_base_cup.glb")
	if pscene == null:
		print("MEASURE_ERR cup glb load fail")
		quit(1)
		return
	var root: Node3D = pscene.instantiate()
	_print_chain(root, Transform3D.IDENTITY, 0)

	# 杯心局部 → 经GLB内部变换链 → slot空间(×70)
	var chain: Transform3D = _get_chain_transform(root)
	var cup_in_slot: Vector3 = (chain * CUP_LOCAL) * 70.0
	print("CUP_IN_SLOT=", cup_in_slot, " (当前 HAND_PROXY_OFFSET 应为此值)")

	# 模型整体AABB（slot空间）
	var aabbs: Array[AABB] = []
	_collect_aabbs(root, Transform3D.IDENTITY, aabbs)
	if aabbs.size() > 0:
		var total: AABB = aabbs[0]
		for i in range(1, aabbs.size()):
			total = total.merge(aabbs[i])
		print("MODEL_AABB_IN_SLOT size=", total.size * 70.0, " center=", total.get_center() * 70.0)

	# ---- 2. 球模型原生尺寸 ----
	var bscene: PackedScene = load("res://assets/game_models/battleball.glb")
	if bscene == null:
		print("MEASURE_ERR ball glb load fail")
		quit(1)
		return
	var broot: Node3D = bscene.instantiate()
	var baabbs: Array[AABB] = []
	_collect_aabbs(broot, Transform3D.IDENTITY, baabbs)
	if baabbs.size() > 0:
		var btotal: AABB = baabbs[0]
		for i in range(1, baabbs.size()):
			btotal = btotal.merge(baabbs[i])
		var native: Vector3 = btotal.size
		print("BALL_NATIVE_AABB=", native, " center_offset=", btotal.get_center())
		var dia: float = max(max(native.x, native.y), native.z)
		print("BALL_NATIVE_DIAMETER=", dia)
		print("BALL_CURRENT_SIZE(scale30)=", native * 30.0)
		print("BALL_SCALE_FOR_DIA14=", 14.0 / dia)
		print("BALL_SCALE_FOR_DIA16=", 16.0 / dia)
		print("BALL_SCALE_FOR_DIA18=", 18.0 / dia)
	quit(0)

func _print_chain(node: Node3D, xf: Transform3D, depth: int) -> void:
	var cur: Transform3D = xf * node.transform
	var pad: String = "  ".repeat(depth)
	print(pad, node.name, " [", node.get_class(), "] origin=", cur.origin,
		" basis_row0=", cur.basis.x, " scale≈", cur.basis.get_scale())
	for c in node.get_children():
		if c is Node3D:
			_print_chain(c, cur, depth + 1)

func _get_chain_transform(root: Node3D) -> Transform3D:
	## 场景根→最深Node3D路径的累积transform（player_proxy_3d 加载后 glb_inst 挂在slot下）
	var xf: Transform3D = Transform3D.IDENTITY
	var cur: Node3D = root
	var guard: int = 0
	while guard < 10:
		guard += 1
		xf = xf * cur.transform
		var next_n3d: Node3D = null
		for c in cur.get_children():
			if c is Node3D:
				next_n3d = c
				break
		if next_n3d == null:
			break
		cur = next_n3d
	return xf

func _collect_aabbs(node: Node3D, xf: Transform3D, out: Array[AABB]) -> void:
	var cur: Transform3D = xf * node.transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(cur * mi.get_aabb())
	for c in node.get_children():
		if c is Node3D:
			_collect_aabbs(c, cur, out)
