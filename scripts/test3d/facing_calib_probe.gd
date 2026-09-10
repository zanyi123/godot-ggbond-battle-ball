## 朝向校准自动探针：复用 parity 场景构建，facing=+X，截图即退
extends Node3D
const P1Scene := preload("res://scenes/test3d/unity_scene_parity_test.tscn")
func _ready() -> void:
	var scene = P1Scene.instantiate()
	add_child(scene)
	await get_tree().create_timer(4.0).timeout
	# 直接驱动校准态（绕过按键）
	scene._demo_active = false
	scene._control_mode = false
	for i in range(scene.players.size()):
		scene.players[i].sync_from_2d(Vector2(scene.LAYOUT[i].x, scene.LAYOUT[i].z), Vector2.ZERO, Vector2(1, 0))
	scene.camera_ctrl.set_mode(2)
	# 特写：相机放球员 +X 侧 150 处看球员——见正脸=面向+X(公式对)，见后脑勺=面向-X(公式反)
	var p0: Node3D = scene.players[0]
	scene.camera_ctrl.global_position = p0.global_position + Vector3(-150.0, 90.0, 0.0)
	scene.camera_ctrl.look_at(p0.global_position + Vector3(0, 30, 0), Vector3.UP)
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p1")
		img.save_png("res://docs/img/3d_p1/p1_facing_calib.png")
		print("[Calib] 📷 已存 facing_calib")
	get_tree().quit()
