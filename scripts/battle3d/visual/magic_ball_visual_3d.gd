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
# 24号B3·内容物符号（主人定案修正 2026-10-11：贴纸效果——符号几何紧贴球面，非浮牌）
# 深色系直接印白球（无底片）；五方向贴标（四水平+顶）=俯视/平视/绕看任一角度至少一个符号正对
const MARK_PAN_FG := Color(0.22, 0.25, 0.32)       # 锅符号=深灰
const MARK_POTION_FG := Color(0.85, 0.15, 0.2)     # 药符号=红
const MARK_FW_FG := Color(0.95, 0.55, 0.1)         # 烟花符号=橙金
const SYMBOL_COLORS := {"fenny_pan": MARK_PAN_FG, "fenny_potion": MARK_POTION_FG, "fenny_firework": MARK_FW_FG}
const BALL_R := 14.0                               # 球半径（符号贴面基准）
# 贴标方向：四正赤道+顶——赤道是斜俯视（从上）与 FP 平视（从下）唯一共通可读纬度
const MARK_DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP]
const HOVER_Y := 150.0           # 悬浮高度（33号b 主人报"贴地"：原作=外场上空悬浮，高于球员头顶）
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
var _content_mark: Node3D = null    # 24号B3：内容物符号（贴球面五方向）
var _owner_team: String = ""


func setup(host: Node) -> void:
	_host = host
	_build_ball()
	var oref = host.get("owner_ref") if host.get("owner_ref") != null else null
	if oref != null and is_instance_valid(oref) and oref.get("team") != null:
		_owner_team = str(oref.get("team"))
	# 内容物数据源=判定域"生成即定装"字段（35号S2a 已落地）：属性优先，**空串也走 meta 兜底**
	# （属性默认 "" 时允许测试/过渡期 meta 注入）；两者皆无→不建标 fail-closed
	var content_val = host.get("_content_item")
	if content_val == null or str(content_val).is_empty():
		content_val = host.get_meta("_content_item") if host.has_meta("_content_item") else null
	_build_content_mark(str(content_val) if content_val != null else "")
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
	# 悬浮浮动+环旋转（纯显示层动画，不进判定）；符号组随球心同步（贴纸贴在球面上）
	var hover_y := HOVER_Y + sin(_t * HOVER_SPEED) * HOVER_AMPLITUDE
	if _sphere != null:
		_sphere.position.y = hover_y
	if _ring != null:
		_ring.position.y = hover_y
		_ring.rotation.y += SPIN_SPEED * delta
	if _content_mark != null:
		_content_mark.position.y = hover_y
		if _content_model_mode:
			_content_mark.rotation.y += 1.2 * delta  # 36号：真道具识别模型慢自转（3D 全向可读）
	# 29号R3 注：选中高亮已随手搓选中链下线（selected 变量已删）——选中反馈由操1 子态确认流承接


## 34号S7 要点③：三级高亮（hover=环加亮放大 / selected=持续选中态 / none）——bridge 轮询置位
func set_highlight(mode: String) -> void:
	if _highlight == mode:
		return
	_highlight = mode
	_apply_highlight()

func _apply_highlight() -> void:
	if _ring == null or _ring_mat == null:
		return
	match _highlight:
		"hover":
			_ring.scale = Vector3(1.25, 1.25, 1.25)
			_ring_mat.albedo_color = Color(1.0, 1.0, 0.6, 1.0)  # 加亮白黄
		"selected":
			_ring.scale = Vector3(1.4, 1.4, 1.4)
			_ring_mat.albedo_color = Color(1.0, 0.9, 0.2, 1.0)  # 选中金亮
		_:
			_ring.scale = Vector3.ONE
			_ring_mat.albedo_color = _ring_color()

var _highlight: String = ""

func _refresh() -> void:
	if _ring_mat == null:
		return
	if _highlight == "":
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


## ===== 24号B3·内容物符号（贴纸式：几何紧贴球面，五方向贴标）=====
## 数据源=判定域"生成即定装"字段 _content_item（F1 域）：属性优先，meta 兜底（测试/过渡期通道）；
## 两处皆无→不建标 fail-closed，判定域落地自动点亮

## 36号（主人 2026-10-15 新模型）：守球内容物识别升级=真实手持道具模型挂球顶自转
## （替代贴纸符号为主显示；模型加载失败回落五方向贴纸=两案并存）。敌我分流 set_content_reveal 不变。
const ITEM_MODEL_DIR := "res://assets/game_models/items_handheld/"
const ITEM_MODEL_PATHS := {
	"fenny_pan": ["frying_pan.glb"],
	"fenny_potion": ["potion_red.fbx"],
	"fenny_firework": ["firework/rocket_baseA.glb", "firework/rocket_finsA.glb", "firework/rocket_fuelA.glb", "firework/rocket_sidesA.glb", "firework/rocket_topA.glb"],
}
const FW_MARK_CENTER := Vector3(2.0, 0.8, 1.5)
const MARK_MODEL_SIZE := 16.0   # 识别用小模型最长边（球径 28 的 0.57，远观可辨不遮球）
var _content_model_mode := false

func _build_content_mark(content: String) -> void:
	if not SYMBOL_COLORS.has(content):
		return   # 攻球/无定装字段/未知道具：不建标（fail-closed 不泄漏）
	_content_mark = Node3D.new()
	_content_mark.name = "ContentMark"
	_content_mark.position.y = HOVER_Y   # 符号组=球心高度（_process 随球浮动同步）
	add_child(_content_mark)
	# 36号：优先真道具模型（主人新做的手持三件——识别度高于几何符号）；失败回落贴纸符号
	if _build_real_item_model(content, _content_mark):
		_content_model_mode = true
		return
	_content_model_mode = false
	# 一份符号复制贴五个方向（符号件厚度 1.2 中心在球面外 1.0 → 内缘贴面外缘微凸=贴纸）
	for dir in MARK_DIRS:
		var holder: Node3D = _make_symbol(content)
		_content_mark.add_child(holder)
		holder.position = dir * (BALL_R + 1.0)
		var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.BACK
		# look_at_from_position 参数=全局坐标（传本地会重设全局位置→符号掉地面）
		var gpos: Vector3 = holder.global_position
		holder.look_at_from_position(gpos, gpos + dir, up)


## 36号：真道具模型构建（照 item_visual_3d._build_real_model 同源：加载/烟花归零上色/AABB 归一）
func _build_real_item_model(content: String, parent: Node3D) -> bool:
	var paths: Array = ITEM_MODEL_PATHS.get(content, [])
	if (paths as Array).is_empty():
		return false
	var holder := Node3D.new()
	holder.name = "ContentModel"
	parent.add_child(holder)
	var loaded: Array = []
	for rel in (paths as Array):
		var ps: PackedScene = load(ITEM_MODEL_DIR + str(rel))
		if ps == null:
			continue
		var inst: Node3D = ps.instantiate()
		holder.add_child(inst)
		loaded.append(inst)
	if (loaded as Array).is_empty():
		holder.queue_free()
		return false
	if content == "fenny_firework":
		for inst in loaded:
			var n3 := inst as Node3D
			n3.position -= FW_MARK_CENTER
			var nm := str(n3.name)
			var col := Color(0.85, 0.2, 0.2)
			if nm.contains("top"):
				col = Color(1.0, 0.8, 0.2)
			elif nm.contains("fins"):
				col = Color(0.3, 0.4, 0.85)
			_override_flat(n3, col)
	var ab := _merged_aabb_model(holder)
	var max_dim: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	if max_dim > 0.0001:
		holder.scale = Vector3.ONE * (MARK_MODEL_SIZE / max_dim)
	return true

func _merged_aabb_model(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var abx: AABB = mi.get_aabb()
			# Node3D 无 get_relative_transform（那是 Node2D 的）——手算：父逆全局 × 子全局
			var xform: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
			abx = xform * abx
			if first:
				out = abx
				first = false
			else:
				out = out.merge(abx)
	return out

func _override_flat(n: Node3D, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		mi.material_override = m
	for c in n.get_children():
		_override_flat(c, col)


## 单份符号（本地 +Z 朝外；锅体大柄短促=俯视平底锅形）
func _make_symbol(content: String) -> Node3D:
	var g := Node3D.new()
	g.name = "MarkFace"
	var col: Color = SYMBOL_COLORS[content]
	match content:
		"fenny_pan":
			_sym_disc(g, 6.5, col, Vector3(-1.8, 0.0, 0.0))                       # 锅体（大圆）
			_sym_box(g, Vector3(5.2, 2.2, 1.2), col, Vector3(5.8, 0.0, 0.0))      # 柄（短粗，≈锅体半径）
		"fenny_potion":
			_sym_box(g, Vector3(13.0, 4.0, 1.2), col, Vector3.ZERO)               # 十字横
			_sym_box(g, Vector3(4.0, 13.0, 1.2), col, Vector3.ZERO)               # 十字竖
		"fenny_firework":
			_sym_box(g, Vector3(13.0, 4.0, 1.2), col, Vector3.ZERO, 0.7854)       # 星芒 45°
			_sym_box(g, Vector3(13.0, 4.0, 1.2), col, Vector3.ZERO, -0.7854)      # 星芒 -45°
	return g


func _sym_disc(parent: Node3D, radius: float, col: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "SymDisc"
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.2
	mi.mesh = cm
	mi.rotation.x = 1.5708   # 圆片立起（面朝 +Z=球面法线向外）
	mi.position = pos
	mi.material_override = _flat_mat(col)
	parent.add_child(mi)


func _sym_box(parent: Node3D, size: Vector3, col: Color, pos: Vector3, rot_z: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "SymBar"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.rotation.z = rot_z
	mi.position = pos
	mi.material_override = _flat_mat(col)
	parent.add_child(mi)


func _flat_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m


## bridge 每帧喂观测方队伍（主人令"敌方视角里面白球不可区分"）：
## 己方=亮标；敌方=隐藏（素白球不可区分）；观测方空=无人类（fullai 双向观测，D6 先例）=全员亮；
## 球主队未知=不亮（fail-closed 不泄漏）
func set_content_reveal(observer_team: String) -> void:
	if _content_mark == null:
		return
	_content_mark.visible = (not _owner_team.is_empty()) and (observer_team.is_empty() or _owner_team == observer_team)


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
