## 诊断 Jog_Forward 动画轨道：找 Hips/root 位移轨道的首尾关键帧值
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/characters/avatars/Jog_Forward.fbx")
	if scene == null:
		print("[Diag] 无法加载 Jog_Forward.fbx")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	var ap := _find_ap(inst)
	if ap == null:
		print("[Diag] 无 AnimationPlayer")
		quit(1)
		return
	for lib_key in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_key)
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			print("[Diag] 动画 '%s' 长度=%.2f 轨道数=%d" % [anim_name, anim.length, anim.get_track_count()])
			for i in range(anim.get_track_count()):
				var t := anim.track_get_type(i)
				var path := str(anim.track_get_path(i))
				var keys := anim.track_get_key_count(i)
				var info := "[Diag]   [%d] type=%d keys=%d path=%s" % [i, t, keys, path]
				if t == Animation.TYPE_POSITION_3D and keys >= 2:
					var p0: Vector3 = anim.position_track_interpolate(i, 0.0)
					var p1: Vector3 = anim.position_track_interpolate(i, anim.length)
					info += " 首=%s 尾=%s 净位移=%.4f" % [p0, p1, p0.distance_to(p1)]
				elif t == Animation.TYPE_POSITION_3D and keys == 1:
					var p: Vector3 = anim.position_track_interpolate(i, 0.0)
					info += " 单帧=%s" % p
				print(info)
	quit(0)

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_ap(child)
		if found != null:
			return found
	return null
