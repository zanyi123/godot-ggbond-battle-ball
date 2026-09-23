extends Node3D
class_name OperatorFeedback3D

## 操1 大点5（操控规划/04）：操作交互反馈 · 世界空间 3D 载体（主轨）
## AIM 预览路径（分段虚线铺地）/ STEER 引导 / 目标圈（POINT/MARK）
## 2D 兜底 = skill_visual_manager/aim_line 既有；本节点不在时静默跳过（双轨降级）
## 加入 "operator_feedback_3d" 组供 input_manager 查找；表现基线（unshaded 贴地）视觉升级归美术

const SEG_COUNT: int = 6
const SEG_SIZE: Vector3 = Vector3(6.0, 0.5, 18.0)
const GROUND_Y: float = 2.0

var _aim_root: Node3D = null
var _aim_dir: Vector2 = Vector2.RIGHT
var _segments: Array[MeshInstance3D] = []
var _target_ring: Node3D = null


func _ready() -> void:
	add_to_group("operator_feedback_3d")


## AIM 预览：沿 dir 铺分段虚线（起点=from 世界坐标，y 贴地）
func show_aim_preview(from: Vector2, dir: Vector2, length: float = 300.0) -> void:
	_ensure_aim_root()
	_aim_dir = dir.normalized()
	if _aim_dir.length_squared() < 0.001:
		_aim_dir = Vector2.RIGHT
	var gap: float = length / float(SEG_COUNT)
	var side := Vector2(-_aim_dir.y, _aim_dir.x)
	for i in range(SEG_COUNT):
		var seg := _segments[i]
		seg.visible = true
		var center2: Vector2 = from + _aim_dir * (gap * (float(i) + 0.5))
		seg.global_position = Vector3(center2.x, GROUND_Y, center2.y)
		seg.rotation.y = atan2(-_aim_dir.x, -_aim_dir.y)


## 更新 AIM 预览方向（鼠移时调用；位置沿用上次起点）
func update_aim_preview_dir(dir: Vector2, length: float = 300.0) -> void:
	if _aim_root == null or not _aim_root.visible:
		return
	show_aim_preview(_aim_root.get_meta("from", Vector2.ZERO), dir, length)


func hide_aim_preview() -> void:
	if _aim_root:
		_aim_root.visible = false


## POINT/MARK 目标圈（世界坐标；挂目标头顶/脚下由表现层定，v1 贴地圈）
func show_target_ring(pos: Vector2, radius: float = 40.0) -> void:
	if _target_ring and is_instance_valid(_target_ring):
		_target_ring.queue_free()
	var outline := load("res://scripts/battle3d/visual/skill_outline_3d.gd")
	if outline == null:
		return
	_target_ring = outline.make_ring(radius, Color(1.0, 0.85, 0.3), GROUND_Y)
	_target_ring.name = "OperatorTargetRing"
	add_child(_target_ring)
	_target_ring.global_position = Vector3(pos.x, GROUND_Y, pos.y)


func clear_target_ring() -> void:
	if _target_ring and is_instance_valid(_target_ring):
		_target_ring.queue_free()
	_target_ring = null


func _ensure_aim_root() -> void:
	if _aim_root and is_instance_valid(_aim_root):
		_aim_root.visible = true
		return
	_aim_root = Node3D.new()
	_aim_root.name = "OperatorAimPreview"
	add_child(_aim_root)
	var seg_script: GDScript = load("res://scripts/battle3d/visual/skill_outline_3d.gd")
	for i in range(SEG_COUNT):
		var seg := MeshInstance3D.new()
		seg.name = "Seg_%d" % i
		var mesh := BoxMesh.new()
		mesh.size = SEG_SIZE
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.5, 0.9, 1.0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		seg.mesh = mesh
		seg.position.y = GROUND_Y
		_aim_root.add_child(seg)
		_segments.append(seg)
	_aim_root.set_meta("from", Vector2.ZERO)
