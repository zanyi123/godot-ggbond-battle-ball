extends Node3D
class_name ShieldVisual3D
## 13-C 基础 UI：盾本体 3D 主件（简约弧面体，unshaded 盾色；耐久梯度变色）
## 只读消费宿主盾公开数据（obstacle_hp/uses_left/durability_mode），零判定逻辑
## 位置由 bridge 每帧同步 2D 盾体（GD 像素 1:1：(x, 0, y)）

var _host: Node = null
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _durability_mode: String = "hp"
var _max_hp: float = 1.0


func setup(host: Node) -> void:
	_host = host
	_durability_mode = str(host.get("durability_mode") if host.get("durability_mode") != null else "hp")
	_max_hp = maxf(float(host.get("obstacle_hp") if host.get("obstacle_hp") != null else 1.0), 1.0)

	_mesh = MeshInstance3D.new()
	_mesh.name = "ShieldBody"
	# 简约弧面体：扁盒近似（M2 换岩石墙网格族精修）
	var box := BoxMesh.new()
	box.size = Vector3(120.0, 60.0, 10.0)
	_mesh.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.84, 0.0)
	_mesh.material_override = _mat
	add_child(_mesh)

	if host.has_signal("shield_state_changed"):
		host.shield_state_changed.connect(_on_shield_state_changed)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _mat == null:
		return
	var ratio := 1.0
	if _durability_mode == "hp":
		var hp = _host.get("obstacle_hp") if _host != null and is_instance_valid(_host) else null
		if hp != null:
			ratio = clampf(float(hp) / _max_hp, 0.0, 1.0)
		# 耐久梯度：金→橙→红
		if ratio > 0.6:
			_mat.albedo_color = Color(1.0, 0.84, 0.0)
		elif ratio > 0.3:
			_mat.albedo_color = Color(1.0, 0.7, 0.1)
		else:
			_mat.albedo_color = Color(0.9, 0.25, 0.15)
	else:
		_mat.albedo_color = Color(1.0, 0.84, 0.0)


func _on_shield_state_changed(_hp: float, _reason: String) -> void:
	_refresh()


## bridge 每帧调用：贴 2D 盾体位姿（单位制铁律 (x, 0, y)）
func sync_from_2d(pos: Vector2, rot_y: float) -> void:
	global_position = Vector3(pos.x, 30.0, pos.y)
	rotation.y = rot_y
