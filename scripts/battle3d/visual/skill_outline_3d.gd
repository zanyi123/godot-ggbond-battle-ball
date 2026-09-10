## 3D 技能轮廓视觉（battle3d/visual · Phase 4 类一）
## 镜像 scripts/systems/spirit_system/skill_outline_node.gd 的三类 2D 自绘：
##   ball 外膜环 / player 脚下环 / field 朝向条带 → 3D TorusMesh/BoxMesh unshaded 透明
## 用法：setup 后 add_child 到目标 3D 代理（环自动贴地/球膜自动跟随目标）
class_name SkillOutline3D
extends Node3D

## 环参数（GD 2D 口径：player r28+5、ball r20+6，α0.55）
const RING_TUBE_RATIO := 0.22

## 类型：RING=水平圆环（脚下/球膜） STRIP=朝向条带（field 类）
static func make_ring(radius: float, color: Color, height_y: float) -> SkillOutline3D:
	var node := SkillOutline3D.new()
	node.name = "SkillOutline3D"
	var torus := MeshInstance3D.new()
	torus.name = "Ring"
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * (1.0 - RING_TUBE_RATIO)
	mesh.outer_radius = radius * (1.0 + RING_TUBE_RATIO)
	mesh.rings = 48
	mesh.ring_segments = 12
	torus.mesh = mesh
	torus.position = Vector3(0.0, height_y, 0.0)
	torus.material_override = _make_material(color)
	node.add_child(torus)
	return node

static func make_strip(radius: float, color: Color) -> SkillOutline3D:
	var node := SkillOutline3D.new()
	node.name = "SkillOutline3DStrip"
	# 朝向条带：沿 -Z（模型正面方向）放置，随代理 rotation.y 旋转
	var strip := MeshInstance3D.new()
	strip.name = "Strip"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(radius * 0.5, 2.0, radius)
	strip.mesh = mesh
	strip.position = Vector3(0.0, 1.0, -radius * 0.5)
	strip.material_override = _make_material(color)
	node.add_child(strip)
	return node

static func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.render_priority = 5
	return mat

## 接球脉冲（0.2s 缩放正弦 ×1.5，镜像 2D _CatchPulse 语义）
func pulse() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_SINE)
