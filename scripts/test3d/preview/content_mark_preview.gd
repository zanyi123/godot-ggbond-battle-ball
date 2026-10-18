extends Node3D
## 24号B3 内容物符号牌预览台（主人目验用）：三种牌白球一字排开，两机位自动截图后退出
## 运行：Godot_console.exe --path . res://scenes/test3d/test_content_mark_preview.tscn
## 产物：docs/img/content_mark_preview_angled.png（斜俯视≈默认测试视角）/_fp.png（低平视≈第一人称视角）
## 注：显示层读定装字段，此处用 meta 注入模拟（判定域 F1 落地后场上自动点亮，本台不受影响）

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 62
	add_child(cam)
	cam.make_current()
	# 假球主（team a）：让分流规则走"己方亮"路径
	var owner_a: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	owner_a.team = "a"
	add_child(owner_a)
	# 三种符号牌白球一字排开
	var ent_script: GDScript = load("res://scripts/systems/summon/summon_entity.gd")
	var vis_script: GDScript = load("res://scripts/battle3d/visual/magic_ball_visual_3d.gd")
	var items := [["fenny_pan", "锅牌"], ["fenny_potion", "药牌"], ["fenny_firework", "烟花牌"]]
	for i in range(items.size()):
		var ent = ent_script.new()
		ent.summon_type = "fenny_magic_ball_def"
		add_child(ent)
		ent.set_physics_process(false)   # 冻结自主行为（纯展示）
		ent.visible = false              # 藏 2D 占位视觉（3D 预览只需模型代理）
		ent.setup({"kind": "magic_ball", "hitbox": "circle:18", "lifespan": 999.0,
			"on_ball": {"mode": "grant_item", "item_pool": ["fenny_pan", "fenny_potion", "fenny_firework"]}},
			0, {"owner_ref": owner_a})
		ent.set_meta("_content_item", items[i][0])   # 模拟定装字段
		ent.global_position = Vector2((i - 1) * 90.0, 0)
		var vis: Node3D = vis_script.new()
		vis.name = "BallVis%d" % i
		add_child(vis)
		vis.setup(ent)
		vis.sync_from_2d(ent.global_position, 0.0)   # 预览无桥接层：手动贴一次位姿 (x,0,y)
		vis.set_content_reveal("")   # 预览=无人类观测口径，全员亮
	# 两机位截图（斜俯视=默认测试视角 / 低平视=模拟玩家第一人称看球）
	await _shot(cam, Vector3(0, 240, -290), Vector3(0, 140, 0), "angled")
	await _shot(cam, Vector3(0, 75, -140), Vector3(0, 150, 0), "fp")
	_export_glb()
	print("[Preview] ✅ 两机位截图+GLB 导出完成，退出")
	get_tree().quit(0)


## 导出标准 GLB（主人要看模型文件）：三球+符号牌导出为通用 3D 文件（Windows 3D 查看器/Blender 可开）
func _export_glb() -> void:
	var export_root := Node3D.new()
	export_root.name = "ContentMarkBalls"
	add_child(export_root)
	var idx := 0
	for child in get_children():
		if child is Node3D and str(child.name).begins_with("BallVis"):
			var clone: Node3D = (child as Node3D).duplicate()
			export_root.add_child(clone)
			clone.position = (child as Node3D).position
			idx += 1
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_scene(export_root, state) == OK:
		var bytes := gltf.generate_buffer(state)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/model_exports"))
		var out_path: String = ProjectSettings.globalize_path("res://docs/model_exports/content_mark_balls_preview.glb")
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		print("[Preview] 📦 GLB 已导出（%d 球）→ %s (%.1f KB)" % [idx, out_path, bytes.size() / 1024.0])
	else:
		print("[Preview] ❌ GLB 导出失败")
	export_root.queue_free()


func _shot(cam: Camera3D, cam_pos: Vector3, target: Vector3, tag: String) -> void:
	cam.global_position = cam_pos
	cam.look_at(target)
	await RenderingServer.frame_post_draw   # 等一帧渲染完成（含 billboard look_at 生效）
	var img := get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://docs/img/content_mark_preview_%s.png" % tag)
	img.save_png(path)
	print("[Preview] 📸 %s 机位已存 → %s" % [tag, path])
