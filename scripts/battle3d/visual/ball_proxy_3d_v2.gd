## 决竞球 3D 视觉代理 v2（battle3d 模块 · Phase 1，像素制口径）
## 移植自 scripts/test/ball_proxy_3d.gd + player_3d_test 球规格：
##   BALL_SCALE=30 / 持球高 55 / 飞行高 30 / 自旋 12 rad/s
## 只读代理：跟随 2D 球数据，不回写。
class_name BallProxy3DV2
extends Node3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

var _ball_mesh: Node3D = null
var _spinning: bool = false
var _carried_hand: Node3D = null
var _mesh_ok: bool = false

func setup() -> void:
	name = "BallProxy3DV2"
	var scene: PackedScene = load(CFG.BALL_GLB_PATH)
	if scene != null:
		var inst := scene.instantiate()
		if inst is Node3D:
			_ball_mesh = inst as Node3D
			add_child(_ball_mesh)
			_ball_mesh.scale = Vector3(CFG.BALL_SCALE, CFG.BALL_SCALE, CFG.BALL_SCALE)
			_fix_ball_pbr(_ball_mesh)
			_hide_mixamo_helpers(_ball_mesh)
			_mesh_ok = true
			print("[BallProxy3DV2] ✅ 决竞球模型加载 scale=%d" % CFG.BALL_SCALE)
			return
	# 兜底：橙红球体
	push_warning("[BallProxy3DV2] 球模型加载失败，用兜底球体")
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackBall"
	var sphere := SphereMesh.new()
	sphere.radius = CFG.BALL_SCALE * 0.35
	sphere.height = CFG.BALL_SCALE * 0.7
	fallback.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	mat.metallic = 0.0
	mat.roughness = 0.5
	fallback.material_override = mat
	add_child(fallback)
	_ball_mesh = fallback

## ==================== 对外 API（Phase 2 bridge 复用） ====================

## 飞行态：2D 坐标 → 飞行高度 + 自旋
func set_flight(pos2d: Vector2) -> void:
	_carried_hand = null
	_spinning = true
	global_position = Vector3(pos2d.x, CFG.BALL_FLIGHT_Y, pos2d.y)

## 持球态：挂某球员代理手部（每帧跟随）
func set_carried(hand_proxy: Node3D) -> void:
	_carried_hand = hand_proxy
	_spinning = false
	if hand_proxy != null and is_instance_valid(hand_proxy):
		global_position = hand_proxy.global_position

## 闲置态（无主）
func set_idle(pos2d: Vector2) -> void:
	_carried_hand = null
	_spinning = false
	global_position = Vector3(pos2d.x, 12.0, pos2d.y)

func is_mesh_ok() -> bool:
	return _mesh_ok

## ==================== 内部 ====================

func _process(delta: float) -> void:
	# 持球跟随手部
	if _carried_hand != null and is_instance_valid(_carried_hand):
		global_position = _carried_hand.global_position
	# 飞行自旋（绕 Y 轴）
	if _spinning and _ball_mesh != null:
		_ball_mesh.rotate(Vector3.UP, CFG.BALL_SPIN_SPEED * delta)

## 混元 GLB PBR 修复（metallic=1 全黑 → 0；roughness>0.8 → 0.6）
func _fix_ball_pbr(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var mi3d := mi as MeshInstance3D
		if mi3d.mesh == null:
			continue
		for i in range(mi3d.mesh.get_surface_count()):
			var mat = mi3d.mesh.surface_get_material(i)
			if mat == null:
				mat = mi3d.material_override
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.metallic > 0.5:
					sm.metallic = 0.0
				if sm.roughness > 0.8:
					sm.roughness = 0.6
				if sm.albedo_texture != null:
					sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

static func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false
