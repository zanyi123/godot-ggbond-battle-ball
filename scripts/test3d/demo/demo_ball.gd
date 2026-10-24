extends Node3D
## 工单37 演示球（修复节修2）：原决竞球模型（battleball.glb，与 BallProxy3DV2 同源口径）
## + 可正常发出：hold_at 瞄准吸附→throw_toward 发球（复用操1 左键段口径：按住瞄准→松开发球）。
## 状态机：IDLE 场中静置 / HELD 瞄准吸附测试者手位 / FLYING 飞行（轻重力+自旋12rad/s 口径）→出界/落定回中场。
## 红线：纯演示件零判定；不自造交互语义（口径=键位占用表「操控球员时」左键段）。

const CFG := preload("res://scripts/battle3d/battle3d_const.gd")

enum BState { IDLE, HELD, FLYING }

var state: int = BState.IDLE
var _ball_mesh: Node3D = null
var _mesh_ok := false
var _vel := Vector3.ZERO
var _fly_t := 0.0
var _hold_target: Node3D = null
var _home := Vector3(0, 0, 0)


func _ready() -> void:
	_home = position   # 主控摆放位=回中场位（场边，避合体/出生路径 R6）
	var scene: PackedScene = load(CFG.BALL_GLB_PATH)
	if scene != null:
		var inst = scene.instantiate()
		if inst is Node3D:
			_ball_mesh = inst as Node3D
			add_child(_ball_mesh)
			_ball_mesh.scale = Vector3(CFG.BALL_SCALE, CFG.BALL_SCALE, CFG.BALL_SCALE)
			_fix_ball_pbr(_ball_mesh)
			_hide_mixamo_helpers(_ball_mesh)
			_mesh_ok = true
			print("[DemoBall] ✅ 决竞球模型加载 scale=%.2f" % CFG.BALL_SCALE)
			return
	push_warning("[DemoBall] 球模型加载失败，用兜底球体（橙红 SphereMesh）")
	var fallback := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 14.0
	sphere.height = 28.0
	fallback.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	fallback.material_override = mat
	add_child(fallback)
	_ball_mesh = fallback


func is_model_ok() -> bool:
	return _mesh_ok


## 操1 口径：左键按住=瞄准（球吸附测试者手位，每帧跟随）
func hold_at(target: Node3D) -> void:
	_hold_target = target
	state = BState.HELD


## 操1 口径：左键松开=发球（方向+力度）。只在手持态有效（发球时手持——不从地上直接发）
func throw_toward(dir: Vector3, power: float) -> void:
	if state != BState.HELD:
		return
	state = BState.FLYING
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.01:
		d = Vector3(0, 0, -1)
	_vel = d.normalized() * clampf(power, 300.0, 700.0)
	_fly_t = 0.0
	_hold_target = null


## 右键取消瞄准（键位表：瞄准中右键=取消投球）→球回中场
func cancel_hold() -> void:
	if state == BState.HELD:
		_hold_target = null
		reset_ball()


func reset_ball() -> void:
	state = BState.IDLE
	_vel = Vector3.ZERO
	_hold_target = null
	position = _home


func _process(delta: float) -> void:
	match state:
		BState.HELD:
			if _hold_target != null and is_instance_valid(_hold_target):
				# 手持观感：贴身右手位（前 14+右 10、高 38≈胸口手部），随面向旋转
				var fwd := Vector3(-sin(_hold_target.rotation.y), 0, -cos(_hold_target.rotation.y))
				var right := Vector3(-fwd.z, 0, fwd.x)
				position = _hold_target.global_position + fwd * 14.0 + right * 10.0 + Vector3(0, 38, 0)
		BState.FLYING:
			_vel.y -= 420.0 * delta   # 轻重力（演示弧线）
			position += _vel * delta
			_fly_t += delta
			if position.y <= 6.0 and _vel.y < 0.0:
				position.y = 6.0
				_vel.y = -_vel.y * 0.35   # 落地一次衰减反弹
				_vel.x *= 0.6
				_vel.z *= 0.6
			var out := absf(position.x) > 540.0 or absf(position.z) > 340.0
			if out or _fly_t > 4.0:
				reset_ball()
		_:
			rotate_y(0.6 * delta)
			if position.distance_to(_home) > 1.0:
				position = position.lerp(_home, minf(2.0 * delta, 1.0))
	# 飞行自旋（BALL_SPIN_SPEED=12 rad/s 口径）
	if state == BState.FLYING and _ball_mesh != null:
		_ball_mesh.rotate(Vector3.UP, CFG.BALL_SPIN_SPEED * delta)


## 混元 GLB PBR 修复（与 BallProxy3DV2._fix_ball_pbr 同口径：metallic 全黑→0 等）
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


func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false
