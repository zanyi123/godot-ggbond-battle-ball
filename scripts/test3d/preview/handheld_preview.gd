extends Node3D
## 24号B3 手持道具预览台（主人目验用）：三球员示意像各手持一件真实道具（CC0 模型），两机位截图后退出
## 运行：Godot_console.exe --path . res://scenes/test3d/test_handheld_preview.tscn
## 产物：docs/img/handheld_preview_angled.png / _fp.png + docs/model_exports/handheld_items_preview.glb

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 62
	add_child(cam)
	cam.make_current()
	var item_script: GDScript = load("res://scripts/battle3d/visual/item_visual_3d.gd")
	var items := [["fenny_pan", "锅"], ["fenny_potion", "药水"], ["fenny_firework", "烟花"]]
	# 球员示意像（盒体身+头，M1 示意；真实道具挂右手位=ItemVisual3D.HAND_LOCAL_POS）
	for i in range(items.size()):
		var stand := Node3D.new()
		stand.name = "PlayerStand%d" % i
		add_child(stand)
		stand.position = Vector3((i - 1) * 110.0, 0.0, 0.0)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(26.0, 42.0, 16.0)
		body.mesh = bm
		body.position.y = 21.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.85, 0.87, 0.9)
		body.material_override = mat
		stand.add_child(body)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(14.0, 12.0, 12.0)
		head.mesh = hm
		head.position.y = 48.0
		head.material_override = mat
		stand.add_child(head)
		# 手持道具（同 bridge 手持口径：挂代理子节点+手位本地坐标）
		var item: Node3D = item_script.new()
		item.name = "HandItem%d" % i
		stand.add_child(item)
		item.position = item.HAND_LOCAL_POS
		item.setup(items[i][0])
	await _shot(cam, Vector3(0, 110, -160), Vector3(0, 30, 0), "angled")
	await _shot(cam, Vector3(0, 38, -95), Vector3(0, 32, 0), "fp")
	_export_glb()
	print("[Preview] ✅ 手持道具两机位截图+GLB 导出完成，退出")
	get_tree().quit(0)


func _shot(cam: Camera3D, cam_pos: Vector3, target: Vector3, tag: String) -> void:
	cam.global_position = cam_pos
	cam.look_at(target)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://docs/img/handheld_preview_%s.png" % tag)
	img.save_png(path)
	print("[Preview] 📸 %s 机位已存 → %s" % [tag, path])


func _export_glb() -> void:
	var export_root := Node3D.new()
	add_child(export_root)
	for child in get_children():
		if child is Node3D and str(child.name).begins_with("PlayerStand"):
			var clone: Node3D = (child as Node3D).duplicate()
			export_root.add_child(clone)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_scene(export_root, state) == OK:
		var bytes := gltf.generate_buffer(state)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/model_exports"))
		var out_path: String = ProjectSettings.globalize_path("res://docs/model_exports/handheld_items_preview.glb")
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		print("[Preview] 📦 GLB 已导出 → %s (%.1f KB)" % [out_path, bytes.size() / 1024.0])
	export_root.queue_free()
