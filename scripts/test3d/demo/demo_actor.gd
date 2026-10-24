extends Node3D
## 工单37 演示球员（测试者/陪衬）：胶囊+面向指示+名牌。WASD 可动，无 AI 无比赛机制。
## 37号修复节修3：体力 100+take_hit 扣血（归零自动回满=演示循环）；命中反馈给 HUD 状态栏。

const SPEED := 220.0
const BODY_HEIGHT := 50.0   # 球员高 ≈49.86 口径
const FP_EYE_LOCAL := Vector3(0, 62, -40)  # 修4：FP 相机锚=头顶上方+面向前外方（模型不包围相机）

var is_tester := true
var display_name := ""
var hp: int = 100
var max_hp: int = 100
var _nose: MeshInstance3D


func setup(p_is_tester: bool, p_name: String) -> void:
	is_tester = p_is_tester
	display_name = p_name
	var color := Color(0.3, 0.6, 1.0) if is_tester else Color(1.0, 0.45, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 14.0
	capsule.height = BODY_HEIGHT
	body.mesh = capsule
	body.material_override = mat
	body.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	add_child(body)

	# 面向指示：-Z 前向小方块（主人 10-20 裁保留）
	_nose = MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(8, 8, 10)
	_nose.mesh = nose_mesh
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(1.0, 0.95, 0.3)
	nose_mat.emission_enabled = true
	nose_mat.emission = Color(1.0, 0.95, 0.3) * 0.7
	_nose.material_override = nose_mat
	_nose.position = Vector3(0, BODY_HEIGHT * 0.55, -18)
	add_child(_nose)

	var label := Label3D.new()
	label.text = p_name
	label.font_size = 40
	label.pixel_size = 0.15
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, BODY_HEIGHT + 18, 0)
	add_child(label)


## WASD 移动一步（dir=平面方向，主控每帧传）
func move_step(dir2: Vector2, delta: float, half_x: float, half_z: float) -> void:
	if dir2.length_squared() < 0.01:
		return
	var d3 := Vector3(dir2.x, 0, dir2.y).normalized()
	position += d3 * SPEED * delta
	position.x = clampf(position.x, -half_x + 20.0, half_x - 20.0)
	position.z = clampf(position.z, -half_z + 20.0, half_z - 20.0)


## 面向地面点（-Z 前向对准）
func face_ground(point: Vector3) -> void:
	var dir := point - position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	rotation.y = atan2(-dir.x, -dir.z)


## 修3：命中扣血；归零自动回满（演示循环）。返回 true=本次触发了回满
func take_hit(dmg: int) -> bool:
	hp = maxi(hp - dmg, 0)
	if hp <= 0:
		hp = max_hp
		return true
	return false


## 修4：FP 相机世界位（头顶上方+面向前外方，随 yaw 旋转；模型在相机后方不包围）
func fp_eye_global() -> Vector3:
	return global_position + FP_EYE_LOCAL.rotated(Vector3.UP, rotation.y)
