extends Node3D
class_name SharkVisual3D
## 24号工单 A1：水鲨鱼 3D 简易模型代理（M1 简约功能性档；随行测试平台美术资源窗口首批件）
## 形态=紫色鱼形盒体组合（照 player_proxy 盒体拼形先例：躯干/头/尾三盒+背鳍/尾鳍色块），零外部美术依赖
## 三态显示（只读消费宿主召唤实体公开字段，UI 零判定红线）：
##   游走=常态微浮；遁地=alpha 半透明+贴地下沉 50%；融合态（summon_type 含 bomb）=scale×1.6+金红变色
## 位置由 bridge 每帧同步 2D 实体（单位制铁律：(x, y) → (x, 高度, y) 1:1 零换算）

const BODY_COLOR := Color(0.55, 0.3, 0.9)      # 紫色鱼身（水木联盟水系紫）
const FIN_COLOR := Color(0.35, 0.18, 0.65)     # 深紫鱼鳍色块
const FUSION_BODY_COLOR := Color(1.0, 0.55, 0.1)   # 融合态金红（24号 A3 材质参数区分）
const FUSION_FIN_COLOR := Color(0.7, 0.25, 0.05)
const FUSION_SCALE := 1.6                       # 融合态放大倍率（24号 A3）
const BURROW_ALPHA := 0.5                       # 遁地半透明（24号 B4）
const BODY_HEIGHT := 24.0                       # 鱼身盒高（遁地下沉 50% 依据）
const SWIM_Y := 14.0                            # 常态鱼身中心离地高（底沿离地 2）
const BURROW_SINK := 12.0                       # 遁地下沉量=体高×50%

var _host: Node = null
var _body: Node3D = null                        # 形体容器（三态变换作用点；根=地面点）
var _body_mat: StandardMaterial3D = null
var _fin_mat: StandardMaterial3D = null
var _is_fusion: bool = false
var _t: float = 0.0                             # 游走微浮相位（纯显示层，不进判定）


func setup(host: Node) -> void:
	_host = host
	var stype := str(host.get("summon_type") if host.get("summon_type") != null else "")
	_is_fusion = stype.contains("bomb")   # 融合产物=组合鲨鱼炸弹（类型表驱动，非状态机态）
	_build_body()
	_refresh()


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "SharkBody"
	add_child(_body)
	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_mat.albedo_color = BODY_COLOR
	_fin_mat = StandardMaterial3D.new()
	_fin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fin_mat.albedo_color = FIN_COLOR
	# 躯干长盒（hitbox circle:22 → 视觉宽约 44）
	_add_box(Vector3(34.0, BODY_HEIGHT, 20.0), Vector3(-2.0, SWIM_Y, 0.0), _body_mat, "Trunk")
	# 头盒（+x 为前进向，随 2D 旋转）
	_add_box(Vector3(14.0, 16.0, 16.0), Vector3(21.0, SWIM_Y, 0.0), _body_mat, "Head")
	# 尾盒
	_add_box(Vector3(12.0, 13.0, 12.0), Vector3(-24.0, SWIM_Y, 0.0), _body_mat, "Tail")
	# 背鳍色块
	_add_box(Vector3(16.0, 9.0, 4.0), Vector3(-2.0, SWIM_Y + BODY_HEIGHT * 0.5 + 4.0, 0.0), _fin_mat, "DorsalFin")
	# 尾鳍竖片
	_add_box(Vector3(4.0, 17.0, 16.0), Vector3(-31.0, SWIM_Y + 1.0, 0.0), _fin_mat, "TailFin")


func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, box_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	_body.add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	_refresh()


func _refresh() -> void:
	if _body == null or _host == null or not is_instance_valid(_host):
		return
	var state := str(_host.get("state") if _host.get("state") != null else "active")
	var burrowed := state == "burrowed"
	# 游走微浮 ±2（遁地时停浮沉底）
	var bob := sin(_t * 3.0) * 2.0 if not burrowed else 0.0
	_body.position.y = (-BURROW_SINK if burrowed else 0.0) + bob
	# 融合态放大（融合产物生成即融合态，直接置值保确定性）
	_body.scale = Vector3.ONE * (FUSION_SCALE if _is_fusion else 1.0)
	# 配色：常态紫 / 融合金红；遁地整体半透明
	var body_col := FUSION_BODY_COLOR if _is_fusion else BODY_COLOR
	var fin_col := FUSION_FIN_COLOR if _is_fusion else FIN_COLOR
	_body_mat.albedo_color = Color(body_col.r, body_col.g, body_col.b, BURROW_ALPHA if burrowed else 1.0)
	_fin_mat.albedo_color = Color(fin_col.r, fin_col.g, fin_col.b, BURROW_ALPHA if burrowed else 1.0)


## bridge 每帧调用：贴 2D 召唤实体位姿（单位制铁律 (x, 0, y)；根=地面点，形体自带高度）
## D12（2026-10-04 主人批"可以"）：rotation.y 取负（2D 角→3D 同向），否则鲨鱼游动方向镜像
func sync_from_2d(pos: Vector2, rot_y: float) -> void:
	global_position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = -rot_y
