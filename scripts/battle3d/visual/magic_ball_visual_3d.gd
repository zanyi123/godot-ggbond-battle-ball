extends Node3D
class_name MagicBallVisual3D
## 24号工单 A2：魔术白球 3D 简易模型代理（M1 简约功能性档；随行测试平台美术资源窗口首批件）
## 形态=白色球体 SphereMesh+轮廓色环：攻=红环/守=蓝环（原作轮廓语义），悬浮旋转
## 撒点助手 scatter_positions：均匀随机撒点（确定性种子，测试/预览用显示层助手）；
##   技能实体的真实生成归属=召唤系统 F1 工单域（元灵技能AI规划/23工单），本助手不写任何游戏状态
## 位置由 bridge 每帧同步 2D 实体（单位制铁律：(x, y) → (x, 高度, y) 1:1 零换算）

const ATTACK_RING_COLOR := Color(0.9, 0.2, 0.15, 0.95)   # 攻=红环
const DEFEND_RING_COLOR := Color(0.2, 0.45, 0.95, 0.95)  # 守=蓝环
const BALL_COLOR := Color(0.96, 0.96, 0.98)              # 白色球体
const HOVER_Y := 30.0            # 悬浮高度（照球飞行口径 30）
const HOVER_AMPLITUDE := 4.0     # 悬浮浮动幅度
const HOVER_SPEED := 2.2         # 悬浮频率
const SPIN_SPEED := 2.0          # 环旋转速度 rad/s
# 撒点默认边界=外场（唯一权威=field_zone.gd 像素常量 ±510/±325，此处只读引用）
const OUTER_FIELD_HALF := Vector2(510.0, 325.0)

var _host: Node = null
var _sphere: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _t: float = 0.0


func setup(host: Node) -> void:
	_host = host
	_build_ball()
	_refresh()


func _build_ball() -> void:
	# 白色球体（hitbox circle:18 → 视觉半径 14）
	_sphere = MeshInstance3D.new()
	_sphere.name = "BallBody"
	var sm := SphereMesh.new()
	sm.radius = 14.0
	sm.height = 28.0
	sm.radial_segments = 16
	sm.rings = 8
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.albedo_color = BALL_COLOR
	_sphere.mesh = sm
	_sphere.material_override = sphere_mat
	_sphere.position.y = HOVER_Y
	add_child(_sphere)
	# 轮廓色环（攻红/守蓝，水平环随球悬浮）
	_ring = MeshInstance3D.new()
	_ring.name = "OutlineRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 18.0
	torus.outer_radius = 21.0
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = HOVER_Y
	add_child(_ring)


func _process(delta: float) -> void:
	_t += delta
	# 悬浮浮动+环旋转（纯显示层动画，不进判定）
	var hover_y := HOVER_Y + sin(_t * HOVER_SPEED) * HOVER_AMPLITUDE
	if _sphere != null:
		_sphere.position.y = hover_y
	if _ring != null:
		_ring.position.y = hover_y
		_ring.rotation.y += SPIN_SPEED * delta
	# 选中高亮（1001 玩家操控链：选中球放大 1.35 倍提示）
	if _sphere != null:
		var sel: bool = _host != null and is_instance_valid(_host) and bool(_host.get("selected"))
		var sc := 1.35 if sel else 1.0
		_sphere.scale = Vector3(sc, sc, sc)


func _refresh() -> void:
	if _ring_mat == null:
		return
	_ring_mat.albedo_color = _ring_color()


func _ring_color() -> Color:
	var stype := str(_host.get("summon_type") if _host != null and is_instance_valid(_host) and _host.get("summon_type") != null else "")
	if stype.contains("_att"):
		return ATTACK_RING_COLOR
	if stype.contains("_def"):
		return DEFEND_RING_COLOR
	# 类型名无后缀时回退 on_ball 模式（carry_with_ball=攻 / grant_item=守）
	var tdef: Dictionary = _host.get("_tdef") if _host != null and is_instance_valid(_host) and _host.get("_tdef") != null else {}
	match str(tdef.get("on_ball", {}).get("mode", "")):
		"carry_with_ball":
			return ATTACK_RING_COLOR
		"grant_item":
			return DEFEND_RING_COLOR
		_:
			return DEFEND_RING_COLOR   # 未知类型按守色兜底（fail-closed 显示）


## bridge 每帧调用：贴 2D 召唤实体位姿（单位制铁律 (x, 0, y)；悬浮高度形体自带）
func sync_from_2d(pos: Vector2, rot_y: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = rot_y


## ===== 显示层撒点助手（主人令 2026-10-01：白球随机生成均匀分布在要求场地上）=====
## 均匀分布=矩形内均匀随机（[min,max) 区间），确定性种子保证可复现（确定性纪律）。
## 仅测试/预览取点用；技能实体真实生成位置归召唤系统 F1 工单域。
static func scatter_positions(count: int, seed_v: int = 20261001, half_extents: Vector2 = OUTER_FIELD_HALF) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array = []
	for i in range(count):
		var x := rng.randf_range(-half_extents.x, half_extents.x)
		var y := rng.randf_range(-half_extents.y, half_extents.y)
		out.append(Vector2(x, y))
	return out
