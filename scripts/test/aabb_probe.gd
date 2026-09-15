extends SceneTree

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== AABB 探针 ===")
	# 加载 GLB
	var glb := load("res://assets/game_models/player1_base.glb") as PackedScene
	if glb:
		var gi: Node = glb.instantiate()
		_dump("GLB", gi)
		gi.queue_free()
	# 加载每个 FBX
	for path in [
		"res://assets/game_models/player1动作/Idle.fbx",
		"res://assets/game_models/player1动作/Jog Forward.fbx",
		"res://assets/game_models/player1动作/Goalie Throw.fbx",
		"res://assets/game_models/player1动作/Goalkeeper Catch.fbx",
	]:
		var fbx := load(path) as PackedScene
		if fbx:
			var fi: Node = fbx.instantiate()
			_dump("FBX " + path.get_file(), fi)
			fi.queue_free()
	quit(0)


func _dump(label: String, root: Node) -> void:
	print("--- %s ---" % label)
	# 列出所有 mesh 和它们的 AABB
	_list_meshes(root, "")
	var ap := _find_ap(root)
	if ap:
		print("  AnimationPlayer: %s" % ap.name)
		for lib_name in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			if lib:
				print("    库 '%s': %s" % [lib_name, str(lib.get_animation_list())])


func _list_meshes(node: Node, indent: String) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			var aabb: AABB = mi.mesh.get_aabb()
			var npos: Vector3 = mi.position
			var nscale: Vector3 = mi.scale
			print("%s  Mesh '%s': AABB=%s local_pos=%s scale=%s" % [indent, mi.name, str(aabb.size), str(npos), str(nscale)])
		else:
			print("%s  MeshInstance3D '%s': (no mesh)" % [indent, mi.name])
	for c in node.get_children():
		_list_meshes(c, indent + "  ")


func _collect(node: Node, min_v: Vector3, max_v: Vector3) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			var aabb := mi.mesh.get_aabb()
			# 局部 AABB（节点未加入场景树时没有 global_transform）
			var xform := mi.transform
			var corners := [
				Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
				Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
				Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
				Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
				Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
				Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
				Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
				Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
			]
			for c in corners:
				var wc: Vector3 = xform * c
				min_v.x = min(min_v.x, wc.x)
				min_v.y = min(min_v.y, wc.y)
				min_v.z = min(min_v.z, wc.z)
				max_v.x = max(max_v.x, wc.x)
				max_v.y = max(max_v.y, wc.y)
				max_v.z = max(max_v.z, wc.z)
	for c in node.get_children():
		_collect(c, min_v, max_v)


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_ap(c)
		if found:
			return found
	return null
