## 3D 球代理：在 SubViewport 内显示 3D 决竞球模型
## 同步 2D ball.gd 的位置/状态到 3D 世界
## 功能：
##   1. 加载 battleball.glb
##   2. 同步 2D ball.global_position → 3D 位置
##   3. 飞行时绕飞行方向轴自旋
##   4. 持球时跟随球员 hand_proxy

extends Node3D
class_name BallProxy3D

## ==================== 常量 ====================
const BALL_BODY_PATH: String = "res://assets/game_models/battleball.glb"
## 球缩放 20 匹配球员 scale=70（模型高约 50），20更像手持大小
const BALL_SCALE: float = 20.0
const BALL_FLIGHT_HEIGHT: float = 30.0  # 飞行时 3D Y 高度（球员腰部）
const BALL_CARRIED_HEIGHT: float = 30.0  # 持球时 3D Y 高度（手部位置）
const BALL_SPIN_SPEED: float = 12.0  # 飞行自旋速度 (rad/s)
const BALL_CATCH_HOVER_HEIGHT: float = 25.0  # 接球过程球悬停高度

## ==================== 节点引用 ====================
@export var ball_2d_path: NodePath  # 2D ball.gd 节点路径
@export var proxy_a_path: NodePath  # 球员 A 3D 代理根
@export var proxy_b_path: NodePath  # 球员 B 3D 代理根

var ball_2d: Area2D = null
var proxy_a: Node3D = null
var proxy_b: Node3D = null
var ball_mesh_instance: Node3D = null  # 球的 GLB 实例
var ball_shadow: MeshInstance3D = null  # 球地面阴影
var is_flying: bool = false
var current_2d_direction: Vector2 = Vector2.RIGHT


## ==================== 初始化 ====================

func _ready() -> void:
	if ball_2d_path != NodePath(""):
		ball_2d = get_node_or_null(ball_2d_path) as Area2D
	if proxy_a_path != NodePath(""):
		proxy_a = get_node_or_null(proxy_a_path) as Node3D
	if proxy_b_path != NodePath(""):
		proxy_b = get_node_or_null(proxy_b_path) as Node3D
	_load_ball_model()
	print("[BallProxy3D] 初始化完成 | ball_2d=%s proxy_a=%s proxy_b=%s" % [
		ball_2d != null, proxy_a != null, proxy_b != null
	])


## ==================== 加载球模型 ====================

func _load_ball_model() -> void:
	var ball_scene: PackedScene = load(BALL_BODY_PATH)
	if ball_scene == null:
		push_error("[BallProxy3D] 无法加载: %s" % BALL_BODY_PATH)
		_create_fallback_ball()
		return
	var ball_inst := ball_scene.instantiate()
	if ball_inst and ball_inst is Node3D:
		ball_mesh_instance = ball_inst as Node3D
		add_child(ball_mesh_instance)
		ball_mesh_instance.scale = Vector3(BALL_SCALE, BALL_SCALE, BALL_SCALE)
		# 修复 PBR 参数（混元模型默认 metallic=1.0, roughness=1.0）
		_fix_ball_pbr(ball_mesh_instance)
		# 隐藏 Mixamo 残留的辅助几何
		_hide_mixamo_helpers(ball_mesh_instance)
		print("[BallProxy3D] 球模型加载完成: %s" % ball_inst.name)
	else:
		push_warning("[BallProxy3D] GLB 实例化失败，使用 fallback 球")
		_create_fallback_ball()

	# 创建地面阴影（简单圆盘）
	ball_shadow = MeshInstance3D.new()
	ball_shadow.name = "BallShadow"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 18.0
	cyl.bottom_radius = 18.0
	cyl.height = 1.0
	ball_shadow.mesh = cyl
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.4)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_shadow.material_override = shadow_mat
	# 阴影作为子节点（不跟着球转，只跟着球 XZ 移动）
	var shadow_parent := Node3D.new()
	shadow_parent.name = "ShadowAnchor"
	add_child(shadow_parent)
	shadow_parent.add_child(ball_shadow)
	ball_shadow.position = Vector3(0, 1.0, 0)


func _create_fallback_ball() -> void:
	"""GLB 加载失败时的 fallback：彩色球体"""
	ball_mesh_instance = MeshInstance3D.new()
	ball_mesh_instance.name = "FallbackBall"
	var sphere := SphereMesh.new()
	sphere.radius = 15.0
	sphere.height = 30.0
	ball_mesh_instance.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1)
	mat.metallic = 0.0
	mat.roughness = 0.5
	ball_mesh_instance.material_override = mat
	add_child(ball_mesh_instance)


## ==================== 修复 PBR ====================

func _fix_ball_pbr(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var mi3d: MeshInstance3D = mi
		if mi3d.mesh == null:
			continue
		var surf_count: int = mi3d.mesh.get_surface_count()
		for i in range(surf_count):
			var mat = mi3d.mesh.surface_get_material(i)
			if mat == null:
				mat = mi3d.material_override
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				if sm.metallic > 0.5:
					sm.metallic = 0.0
				if sm.roughness > 0.8:
					sm.roughness = 0.6
				if sm.albedo_texture != null:
					sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## ==================== 隐藏 Mixamo 残留 ====================

static func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false


## ==================== 每帧更新 ====================

func _process(delta: float) -> void:
	if ball_2d == null or not is_instance_valid(ball_2d):
		return

	is_flying = ball_2d.is_active

	if is_flying:
		# 飞行时：同步 2D 位置 + 3D Y 高度 = 飞行高度 + 球自旋
		var pos2d: Vector2 = ball_2d.global_position
		global_position = Vector3(pos2d.x, BALL_FLIGHT_HEIGHT, pos2d.y)

		# 更新飞行方向（让自旋跟着方向变化）
		var dir2d: Vector2 = ball_2d.ball_direction
		if dir2d.length() > 0.01:
			current_2d_direction = dir2d

		# 自旋：绕 Y 轴（球的"上旋"，视觉效果：球飞行中转动）
		if ball_mesh_instance != null:
			ball_mesh_instance.rotate(Vector3.UP, BALL_SPIN_SPEED * delta)
	else:
		# 持球/静止：球跟随手部
		_attach_to_hand()


## ==================== 计算球 Y 高度 ====================

func _get_ball_y() -> float:
	if ball_2d == null or not is_instance_valid(ball_2d):
		return 0.0
	if ball_2d.is_active:
		return BALL_FLIGHT_HEIGHT
	# 持球时高度 = 跟随 hand_proxy（hand_proxy 在球员头顶）
	return BALL_CARRIED_HEIGHT


## ==================== 跟随手部 ====================

func _attach_to_hand() -> void:
	if ball_mesh_instance == null:
		return
	# 找持球球员的 hand_proxy
	var owner = ball_2d.owner_player
	if owner == null or not is_instance_valid(owner):
		# 没有 owner，球浮在场地中心
		global_position = Vector3(0, BALL_CARRIED_HEIGHT, 0)
		ball_mesh_instance.position = Vector3.ZERO
		return
	# 通过 meta 找到对应 3D 代理
	var proxy_root: Node3D = null
	if proxy_a != null and owner == proxy_a.get_meta("player_ref", null):
		proxy_root = proxy_a
	elif proxy_b != null and owner == proxy_b.get_meta("player_ref", null):
		proxy_root = proxy_b
	if proxy_root == null:
		# 找不到代理 → 浮在 2D 位置上方
		var p2: Vector2 = (owner as Node2D).global_position
		global_position = Vector3(p2.x, BALL_CARRIED_HEIGHT, p2.y)
		ball_mesh_instance.position = Vector3.ZERO
		return
	# 优先用 hand_proxy（投球手部挂接点）
	var hand_proxy: Node3D = proxy_root.get_node_or_null("HandProxy") as Node3D
	if hand_proxy != null:
		# BallProxy 是 SubViewport 子节点，global_position 直接等于 hand_proxy.global_position
		self.global_position = hand_proxy.global_position
		# 球本体保持原位（BallProxy 已经移动到 hand_proxy 位置）
		ball_mesh_instance.position = Vector3.ZERO
	else:
		# 没有 hand_proxy → 浮在球员头顶
		var p2d: Vector2 = owner.global_position
		self.global_position = Vector3(p2d.x, BALL_CARRIED_HEIGHT, p2d.y)
		ball_mesh_instance.position = Vector3.ZERO
