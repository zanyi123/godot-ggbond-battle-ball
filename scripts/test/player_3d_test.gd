## 3D 球员测试平台
## 独立测试场景,验证 2.5D 3D 球员 + 大相机三种视角
## 功能:
##   WASD      = 8方向移动(自动切 idle↔run 动画)
##   Tab       = 切换控制球员
##   F1/F2/F3  = 手动切 throw/catch/idle 动画
##   F4        = 切相机模式(俯视/斜视45°/平视跟随)
##               同步切大相机(Camera3D)和小相机(SubViewport Camera3D)
##   F5        = 重置球员位置
##   F6        = 切换大相机视图显示(3D大相机覆盖层 ON/OFF)
##
## 坐标映射(大相机3D世界):
##   2D游戏 X  →  3D X   (不变, 球门方向1300)
##   2D游戏 Y  →  3D Z   (边线方向780, 游戏Y正→3D Z正)
##   场地"上方" →  3D Y   (高度轴, Y=0为场地平面)
##
## 大相机三模式(Camera3D):
##   俯视: 正交相机从3D+Y上方朝-Y看      → 等价球场+Z上方
##   斜视45°: 透视相机从YZ平面45°位置看  → ZOY平面逆时针45°
##   平视: 透视相机从3D+X侧朝-X看        → 球场+X对着-X

extends Node2D

## ==================== 场地常量 ====================
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const FIELD_COLOR: Color = Color(0.12, 0.18, 0.12)

## ==================== 小相机模式 (映射到 set_view_mode) ====================
var _camera_mode: int = 1
const CAMERA_MODE_TOP_DOWN: int = 0   # 俯视  → 小相机 +Y朝-Y
const CAMERA_MODE_ANGLED: int = 1     # 斜视45° → 小相机 -45°
const CAMERA_MODE_FOLLOW: int = 2     # 平视  → 小相机 +Z正脸
const CAMERA_MODE_NAMES: Array = ["俯视全场", "斜视45°(ZOY平面)", "平视+X跟随"]

## ==================== 节点引用 ====================
var player_a: CharacterBody2D
var player_b: CharacterBody2D
var controlled_player: CharacterBody2D
var debug_label: Label
var hint_label: Label
var camera_2d: Camera2D
var _field_bg: ColorRect       # 2D场地背景引用(切大相机时隐藏)
var _field_lines: Array = []   # 2D场地线条引用
var ball_2d: Area2D = null     # 2D ball.gd 节点（直接搬用 battle 系统）
var _ball_proxy_3d: Node3D = null  # 3D 球代理

## 球员快捷面板（体力+元灵能量条）
var _panel_a: Panel = null
var _panel_b: Panel = null
var _stam_a: ProgressBar = null
var _stam_b: ProgressBar = null
var _energy_a: ProgressBar = null
var _energy_b: ProgressBar = null
var _name_label_a: Label = null
var _name_label_b: Label = null
var _ball_indicator_a: ColorRect = null  # 持球状态指示
var _ball_indicator_b: ColorRect = null

## ==================== 大相机 Camera3D 系统 ====================
# 阶段2验证: 在测试场中用 SubViewport+Camera3D 展示三种大相机视角
# 生产版本将直接在 battle_arena 里用 Camera3D 看 3D 场地(阶段1+2实现)

var _big_cam_vp: SubViewport = null       # 大相机渲染 SubViewport
var _big_camera: Camera3D = null          # 大相机 Camera3D
var _big_cam_layer: CanvasLayer = null    # 显示覆盖层
var _big_cam_rect: TextureRect = null     # 全屏显示 SubViewport 纹理
var _big_cam_active: bool = true          # 是否显示大相机覆盖

# 球员位置代理体(在大相机 SubViewport 内可见) — 2026-06-26 替换为 player1 实际 3D 模型
## ==================== 球员位置代理体 ====================
## _proxy_a/_proxy_b 是大相机 SubViewport 内的 Node3D 代理（带 GLB+FBX+HandProxy）
## _proxy_a.position = 球员 3D 世界位置
## _proxy_a.rotation.y = 球员朝向
var _proxy_a: Node3D = null
var _proxy_b: Node3D = null


func _set_proxy_pos(proxy: Node3D, pos2d: Vector2) -> void:
	"""设置 proxy 位置 = 2D 球员位置（proxy 是大相机内 Node3D）"""
	if proxy == null or not is_instance_valid(proxy):
		return
	proxy.position = _game2d_to_3d(pos2d)


func _set_proxy_rotation_y(proxy: Node3D, angle: float) -> void:
	"""设置 proxy 朝向（绕 Y 轴）"""
	if proxy == null or not is_instance_valid(proxy):
		return
	proxy.rotation.y = angle


func _get_proxy_anim_player(proxy: Node) -> AnimationPlayer:
	"""获取 proxy 的 AnimationPlayer"""
	if proxy == null or not is_instance_valid(proxy):
		return null
	return proxy.get_meta("anim_player", null) as AnimationPlayer


func _get_proxy_current_anim(proxy: Node) -> String:
	"""获取 proxy 当前动画名"""
	if proxy == null or not is_instance_valid(proxy):
		return ""
	return proxy.get_meta("current_anim", "idle") as String


func _set_proxy_current_anim(proxy: Node, name: String) -> void:
	"""设置 proxy 当前动画名"""
	if proxy == null or not is_instance_valid(proxy):
		return
	proxy.set_meta("current_anim", name)

## player1 模型路径(大相机内展示用)
## 与 battle/player.gd CHAR_3D_MODEL_PATHS["char_001"] 完全一致
const PLAYER1_BODY_PATH := "res://建模素材库/3D模型素材/player1_base.glb"
const PLAYER1_IDLE_PATH := "res://建模素材库/3D模型素材/player1动作/Idle.fbx"
const PLAYER1_RUN_PATH := "res://建模素材库/3D模型素材/player1动作/Jog Forward.fbx"
const PLAYER1_THROW_PATH := "res://建模素材库/3D模型素材/player1动作/Goalie Throw.fbx"
const PLAYER1_CATCH_PATH := "res://建模素材库/3D模型素材/player1动作/Goalkeeper Catch.fbx"

## 3D 球员代理缩放（用户期望值 70，对应模型高度约 50 单位）
## 根本修复：只有 idle FBX mesh 可见，其他 3 个 FBX 隐藏 mesh 只贡献动画
## 之前"溢出"原因是 4 个 FBX mesh 同时渲染叠加
const PROXY_SCALE: float = 70.0
## 球员模型实际高度（FBX AABB Y 0.01096 × 缩放 65 × ModelSlot 70 = 49.86）
const PROXY_MODEL_HEIGHT: float = 49.86
## 球飞行/持球 3D Y 高度（持球高度略高于模型顶）
const BALL_CARRIED_3D_Y: float = 55.0
const BALL_FLIGHT_3D_Y: float = 30.0
const BALL_SCALE_3D: float = 30.0

# 大相机参数(3D世界单位 = 游戏像素 1:1)
const BIG_CAM_TOP_Y: float = 1000.0          # 俯视高度
const BIG_CAM_TOP_ORTHO_SIZE: float = 870.0  # 俯视正交尺寸(高=870, 16:9宽≈1547 > 1300)
const BIG_CAM_ANGLED_DIST: float = 1200.0    # 斜视相机到原点距离
const BIG_CAM_SIDE_X: float = 1100.0         # 平视相机X偏移
const BIG_CAM_SIDE_Y: float = 100.0          # 平视相机高度(轻微俯角)
const BIG_CAM_FOV: float = 62.0              # 透视模式视野角

## 球员切换
var _current_control_index: int = 0

## 按键边缘检测：上一帧状态（用独立变量，避免 Dictionary key 类型问题）
var _prev_tab := false
var _prev_f1 := false
var _prev_f2 := false
var _prev_f3 := false
var _prev_f4 := false
var _prev_f5 := false
var _prev_f6 := false

## 手动动画锁：F键按下时置 true，防止 _physics_process 同帧覆盖
## throw/catch 播完后自动清零（在 _physics_process 里检测 is_playing()）
var _manual_anim_locked: bool = false


## ==================== 初始化 ====================

func _ready() -> void:
	camera_2d = get_node_or_null("Camera2D")
	_create_field()
	_create_players()
	_create_ball()
	_create_debug_ui()
	_create_player_panels()
	_setup_big_camera_system()
	# 默认斜视45°
	_camera_mode = CAMERA_MODE_ANGLED
	_apply_camera_mode_to_players()
	_apply_big_camera_mode(_camera_mode)
	# 球默认给 A 队（开局 A 持球）
	_give_ball_to(player_a)
	print("[Player3DTest] 加载完成 | WASD移动 Tab切换 F1=throw F2=catch F3=idle F4=切相机 F5=重置 F6=切大相机显示")


## ==================== 创建 2D 决竞球 (直接搬用 battle/ball.gd) ====================

func _create_ball() -> void:
	"""直接搬用 battle 系统的 ball.gd，参数对齐"""
	var ball_script := load("res://scripts/battle/ball.gd")
	if ball_script == null:
		push_error("[Player3DTest] 无法加载 ball.gd 脚本")
		return
	ball_2d = Area2D.new()
	ball_2d.set_script(ball_script)
	ball_2d.name = "BattleBall2D"
	ball_2d.position = Vector2(-300.0, 0.0)
	ball_2d.global_position = Vector2(-300.0, 0.0)
	add_child(ball_2d)
	print("[Player3DTest] ✅ ball.gd 加载完成（battle 系统直接搬用）")


func _give_ball_to(player: CharacterBody2D) -> void:
	"""让指定球员持球（开局/接球后用）
	同时重置 3D 代理朝向（投球后 rotation 可能偏离，接球后回正）
	"""
	if ball_2d == null or not is_instance_valid(ball_2d):
		return
	ball_2d.is_active = false
	ball_2d.owner_player = player
	ball_2d.attacker_player = player
	if player:
		player.set_carrying_ball(true)
		ball_2d.global_position = player.global_position + Vector2(0, -40)
	# 重置 3D 代理朝向（让 HandProxy 回到头顶正上方）
	var px: Node = _proxy_a if player == player_a else _proxy_b
	if px and is_instance_valid(px):
		_set_proxy_rotation_y(px, 0.0)


## ==================== 创建 2D 场地 ====================

func _create_field() -> void:
	_field_bg = ColorRect.new()
	_field_bg.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	_field_bg.position = Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0)
	_field_bg.color = FIELD_COLOR
	add_child(_field_bg)

	var mid_line := Line2D.new()
	mid_line.add_point(Vector2(0, -FIELD_HEIGHT / 2.0))
	mid_line.add_point(Vector2(0, FIELD_HEIGHT / 2.0))
	mid_line.default_color = Color(0.3, 0.4, 0.3, 0.5)
	mid_line.width = 2.0
	add_child(mid_line)
	_field_lines.append(mid_line)

	var center_circle := Line2D.new()
	var center_radius: float = 60.0
	for i in range(33):
		var angle: float = (float(i) / 32.0) * TAU
		center_circle.add_point(Vector2(cos(angle), sin(angle)) * center_radius)
	center_circle.default_color = Color(0.3, 0.4, 0.3, 0.5)
	center_circle.width = 2.0
	add_child(center_circle)
	_field_lines.append(center_circle)

	var border := Line2D.new()
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(FIELD_WIDTH / 2.0, FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.default_color = Color(0.4, 0.5, 0.4)
	border.width = 4.0
	add_child(border)
	_field_lines.append(border)


## ==================== 创建球员 ====================

func _create_players() -> void:
	var data_a := _get_char_data(0)
	var data_b := _get_char_data(1)
	# 必须先 add_child 才能让 player.gd._ready() 执行（_setup_3d_model 需要在 _ready 中执行）
	player_a = _create_player_node(data_a, "a", Vector2(-300.0, 0.0))
	player_b = _create_player_node(data_b, "b", Vector2(300.0, 0.0))
	add_child(player_a)
	add_child(player_b)
	controlled_player = player_a
	# 等待 _ready 完成
	await get_tree().process_frame
	await get_tree().process_frame
	# 二次确认 model_3d_anchor
	if player_a and player_a.model_3d_anchor:
		print("[Player3DTest] ✅ player_a.model_3d_anchor 已创建: %s" % player_a.model_3d_anchor.name)
	else:
		push_warning("[Player3DTest] ❌ player_a.model_3d_anchor 未创建！USE_3D_MODEL 可能为 false")
	if player_b and player_b.model_3d_anchor:
		print("[Player3DTest] ✅ player_b.model_3d_anchor 已创建: %s" % player_b.model_3d_anchor.name)
	else:
		push_warning("[Player3DTest] ❌ player_b.model_3d_anchor 未创建！USE_3D_MODEL 可能为 false")


func _get_char_data(index: int) -> Dictionary:
	if DataManager and DataManager.characters.size() > index:
		return DataManager.characters[index]
	return {
		"id": "test_%d" % index, "name": "测试%d" % (index + 1),
		"stamina": 100.0, "attack": 38.0, "defense": 60.0,
		"speed": 70.0, "resilience": 50.0, "defense_factor": 0.15,
	}


func _create_player_node(data: Dictionary, team_name: String, start_pos: Vector2) -> CharacterBody2D:
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.set_script(player_script)
	player.character_id = str(data.get("id", ""))
	player.team = team_name
	player.is_player_controlled = false
	player.global_position = start_pos
	if DataManager:
		player.initialize(str(data.get("id", "")), team_name, false)
	player.max_stamina = float(data.get("stamina", 100.0))
	player.stamina = player.max_stamina
	player.attack_power = float(data.get("attack", 38.0))
	player.defense = float(data.get("defense", 60.0))
	player.speed = float(data.get("speed", 70.0)) * 3.25
	player.resilience = float(data.get("resilience", 50.0))
	player.defense_factor = float(data.get("defense_factor", 0.15))
	player.add_to_group("players")
	return player


## ==================== 大相机 Camera3D 系统 ====================

func _setup_big_camera_system() -> void:
	"""创建大相机 SubViewport + Camera3D + 3D场地 + 球员代理"""
	# 1. SubViewport
	_big_cam_vp = SubViewport.new()
	_big_cam_vp.size = Vector2i(2560, 1440)  # 提高分辨率防止贴图拉伸糊
	_big_cam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_big_cam_vp.transparent_bg = false
	_big_cam_vp.world_3d = World3D.new()
	# 环境
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.06, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.0
	_big_cam_vp.world_3d.environment = env
	add_child(_big_cam_vp)

	# 2. Camera3D
	_big_camera = Camera3D.new()
	_big_camera.near = 1.0
	_big_camera.far = 10000.0
	_big_camera.current = true
	_big_cam_vp.add_child(_big_camera)

	# 3. 方向光
	var light := DirectionalLight3D.new()
	light.light_energy = 1.2
	light.shadow_enabled = false
	# 从左上方45°打光
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	_big_cam_vp.add_child(light)

	# 4. 3D场地几何
	_create_3d_field_geo()
	
	# 4.5 诊断参考柱（确认模型大小用，高度分别为 10/50/100 单位）
	_add_debug_reference_pillars()

	# 5. 球员代理体
	_setup_player_proxies()

	# 6. 显示层 - CanvasLayer 覆盖全屏
	_big_cam_layer = CanvasLayer.new()
	_big_cam_layer.layer = 2   # 在球员Sprite2D(layer 0)之上，在UI(layer 10)之下
	add_child(_big_cam_layer)
	_big_cam_rect = TextureRect.new()
	_big_cam_rect.texture = _big_cam_vp.get_texture()
	_big_cam_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_big_cam_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_big_cam_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_cam_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_cam_layer.add_child(_big_cam_rect)

	# 初始状态: 大相机可见, 2D场地隐藏
	_set_big_cam_visibility(true)


func _add_debug_reference_pillars() -> void:
	"""添加诊断参考柱（红=10高, 绿=50高, 蓝=100高）用于对比模型大小"""
	var pillar_data: Array = [
		{"height": 10.0, "color": Color(1, 0.2, 0.2), "pos": Vector3(100.0, 0.0, -200.0), "label": "10u"},
		{"height": 50.0, "color": Color(0.2, 1, 0.2), "pos": Vector3(200.0, 0.0, -200.0), "label": "50u"},
		{"height": 100.0, "color": Color(0.2, 0.2, 1), "pos": Vector3(300.0, 0.0, -200.0), "label": "100u"},
	]
	for data in pillar_data:
		var h: float = data["height"]
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(20.0, h, 20.0)
		pillar.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data["color"]
		mat.emission_enabled = true
		mat.emission = data["color"]
		mat.emission_energy_multiplier = 0.5
		pillar.material_override = mat
		pillar.position = data["pos"] + Vector3(0.0, h / 2.0, 0.0)
		_big_cam_vp.add_child(pillar)
		print("[Player3DTest] 诊断参考柱 %s: 高度%.0f, 位置%s" % [
			data["label"], h, str(data["pos"])
		])


func _create_3d_field_geo() -> void:
	"""在 SubViewport 里创建 3D 场地几何
	坐标系: 游戏XY → 3D XZ (Y=0为场地平面, 3D Y轴=场地上方)
	"""
	# 场地主平面 (XZ plane, Y=0)
	var field_inst := MeshInstance3D.new()
	var field_plane := PlaneMesh.new()
	field_plane.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)  # PlaneMesh: X=宽, Z=深
	field_inst.mesh = field_plane
	var field_mat := StandardMaterial3D.new()
	field_mat.albedo_color = Color(0.12, 0.20, 0.12)
	field_mat.roughness = 0.9
	field_inst.material_override = field_mat
	field_inst.position = Vector3.ZERO
	_big_cam_vp.add_child(field_inst)

	# 边界线(4条)
	_add_3d_border_line(Vector3(-FIELD_WIDTH / 2.0, 1.0, 0.0), Vector3(4.0, 1.0, FIELD_HEIGHT))  # 左
	_add_3d_border_line(Vector3(FIELD_WIDTH / 2.0, 1.0, 0.0), Vector3(4.0, 1.0, FIELD_HEIGHT))   # 右
	_add_3d_border_line(Vector3(0.0, 1.0, -FIELD_HEIGHT / 2.0), Vector3(FIELD_WIDTH, 1.0, 4.0))  # 上(游戏-Y)
	_add_3d_border_line(Vector3(0.0, 1.0, FIELD_HEIGHT / 2.0), Vector3(FIELD_WIDTH, 1.0, 4.0))   # 下(游戏+Y)

	# 中线 (X=0, 沿Z轴延伸)
	_add_3d_border_line(Vector3(0.0, 1.5, 0.0), Vector3(3.0, 1.5, FIELD_HEIGHT), Color(0.4, 0.55, 0.4))

	# 中圈 (用多段BoxMesh近似圆形)
	var circle_r: float = 60.0
	var segs: int = 24
	for i in range(segs):
		var a0: float = (float(i) / float(segs)) * TAU
		var a1: float = (float(i + 1) / float(segs)) * TAU
		var p0 := Vector3(cos(a0) * circle_r, 1.5, sin(a0) * circle_r)
		var p1 := Vector3(cos(a1) * circle_r, 1.5, sin(a1) * circle_r)
		var mid := (p0 + p1) * 0.5
		var seg_len := p0.distance_to(p1)
		var angle := atan2(p1.z - p0.z, p1.x - p0.x)
		var seg_inst := MeshInstance3D.new()
		var seg_box := BoxMesh.new()
		seg_box.size = Vector3(seg_len, 1.0, 2.0)
		seg_inst.mesh = seg_box
		var seg_mat := StandardMaterial3D.new()
		seg_mat.albedo_color = Color(0.35, 0.5, 0.35)
		seg_inst.material_override = seg_mat
		seg_inst.position = mid
		seg_inst.rotation.y = -angle
		_big_cam_vp.add_child(seg_inst)


func _add_3d_border_line(pos: Vector3, size: Vector3, color: Color = Color(0.4, 0.55, 0.4)) -> void:
	"""添加一条3D边线(BoxMesh)"""
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	inst.position = pos
	_big_cam_vp.add_child(inst)


func _setup_player_proxies() -> void:
	"""创建球员 3D 模型代理(player1 猪猪侠真模型, 在大相机 3D 场中可见)"""
	_proxy_a = _make_3d_player(Color(0.25, 0.45, 0.95, 0.6))   # 队A 蓝底环
	_proxy_b = _make_3d_player(Color(0.95, 0.25, 0.25, 0.6))   # 队B 红底环
	_big_cam_vp.add_child(_proxy_a)
	_big_cam_vp.add_child(_proxy_b)

	# 设置 player_ref meta 供 ball_proxy_3d.gd 关联 2D player
	if _proxy_a and player_a:
		_proxy_a.set_meta("player_ref", player_a)
	if _proxy_b and player_b:
		_proxy_b.set_meta("player_ref", player_b)

	# ========== 3D 球代理（决竞球模型）==========
	_create_ball_proxy_3d()
	# 初始位置同步（立即设置 proxy 位置）
	if player_a and _proxy_a:
		_set_proxy_pos(_proxy_a, player_a.global_position)
	if player_b and _proxy_b:
		_set_proxy_pos(_proxy_b, player_b.global_position)
	print("[Player3DTest] proxy 初始位置: A=%s, B=%s" % [
		str(_proxy_a.position) if _proxy_a else "null",
		str(_proxy_b.position) if _proxy_b else "null"
	])


func _make_3d_player_proxy(player: CharacterBody2D, team_color: Color) -> Node3D:
	"""在 SubViewport 内创建一个球员 3D 代理（带 GLB+FBX+HandProxy+AnimPlayer+Ring）
	缩放 = slot.scale × (FBX补偿 = 65) = 25 × 65 = 1625 → 全局高度约 18 单位
	"""
	var root := Node3D.new()
	root.name = "Proxy_" + (player.team if player else "?")

	# ========== ModelSlot（缩放 25，模型高度约 18 单位）==========
	var slot := Node3D.new()
	slot.name = "ModelSlot"
	slot.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	slot.scale = Vector3(PROXY_SCALE, PROXY_SCALE, PROXY_SCALE)
	root.add_child(slot)

	# ========== 加载主 GLB（player1_base.glb，含贴图）==========
	var glb_path: String = "res://建模素材库/3D模型素材/player1_base.glb"
	var glb_scene: PackedScene = load(glb_path) as PackedScene
	if glb_scene == null:
		push_error("[Player3DTest] 无法加载 GLB: %s" % glb_path)
		return root
	var glb_instance: Node = glb_scene.instantiate()
	if glb_instance == null:
		push_error("[Player3DTest] GLB 实例化失败")
		return root
	# GLB 用于贴图/材质，隐藏其 mesh
	_hide_all_meshes(glb_instance)
	# GLB 内部如果带骨骼，不要给它 scale 补偿（GLB 已是正确大小）
	if glb_instance is Node3D:
		(glb_instance as Node3D).scale = Vector3(1.0, 1.0, 1.0)
	slot.add_child(glb_instance)

	# ========== 加载所有动作 FBX（idle/throw/catch/run）合并到一个 AnimationPlayer ==========
	# 球员所有动作都基于 player1 猪猪侠，4 个动作文件
	# 关键修复：只把第一个 FBX (idle) 作为可见网格，其他 3 个仅取其动画
	var action_paths: Dictionary = {
		"idle": "res://建模素材库/3D模型素材/player1动作/Idle.fbx",
		"run": "res://建模素材库/3D模型素材/player1动作/Jog Forward.fbx",
		"throw": "res://建模素材库/3D模型素材/player1动作/Goalie Throw.fbx",
		"catch": "res://建模素材库/3D模型素材/player1动作/Goalkeeper Catch.fbx",
	}
	var first_fbx_anim_player: AnimationPlayer = null
	var all_anim_players: Array[AnimationPlayer] = []
	var visible_action: String = "idle"  # 用 idle 作为可见网格（其他 3 个只贡献动画）
	for action_name in action_paths:
		var action_path: String = action_paths[action_name]
		var action_scene: PackedScene = load(action_path) as PackedScene
		if action_scene == null:
			push_warning("[Player3DTest] 无法加载动作: %s" % action_path)
			continue
		var action_instance: Node = action_scene.instantiate()
		if action_instance == null:
			continue
		# FBX mesh 比 GLB 小约 65 倍
		if action_instance is Node3D:
			(action_instance as Node3D).scale = Vector3(65.0, 65.0, 65.0)
		# 只对可见的那个 FBX 保留 mesh，其他的全部隐藏避免重叠渲染
		if action_name == visible_action:
			slot.add_child(action_instance)
		else:
			# 不可见的 FBX：加到 slot 外面（让 AnimationPlayer 仍能跑）
			_hide_all_meshes(action_instance)
			slot.add_child(action_instance)
		# 找 AnimationPlayer
		var ap: AnimationPlayer = _find_animation_player_in(action_instance)
		if ap:
			# 把这个 AnimationPlayer 的动画库重命名（避免冲突）
			var target_lib_name: String = action_name
			var src_lib: AnimationLibrary = ap.get_animation_library("")
			if src_lib:
				ap.remove_animation_library("")
				var new_lib: AnimationLibrary = AnimationLibrary.new()
				for anim_name in src_lib.get_animation_list():
					var anim: Animation = src_lib.get_animation(anim_name)
					if anim:
						new_lib.add_animation(anim_name, anim)
				ap.add_animation_library(target_lib_name, new_lib)
				print("[Player3DTest] ✅ 加载动作 %s (库名: %s)" % [action_name, target_lib_name])
			if first_fbx_anim_player == null:
				first_fbx_anim_player = ap
			all_anim_players.append(ap)
		else:
			push_warning("[Player3DTest] 动作 %s 无 AnimationPlayer" % action_name)
	
	# ========== 修复白膜：把 GLB 的贴图材质复制到可见 FBX 的 mesh ==========
	var visible_fbx: Node = null
	for child in slot.get_children():
		if child != glb_instance and child is Node3D:
			var has_visible_mesh: bool = false
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				if mi is MeshInstance3D and mi.visible:
					has_visible_mesh = true
					break
			if has_visible_mesh:
				visible_fbx = child
				break
	if visible_fbx != null and glb_instance != null:
		_copy_textures_from_glb_to_fbx(glb_instance, visible_fbx)
		print("[Player3DTest] ✅ GLB 材质已复制到可见 FBX")
	else:
		push_warning("[Player3DTest] ⚠️ 无法复制材质：visible_fbx=%s, glb=%s" % [
			visible_fbx.name if visible_fbx else "null",
			glb_instance.name if glb_instance else "null"
		])
	
	# ========== 诊断：打印 GLB 和 FBX 的 AABB 大小 ==========
	_print_model_aabb("GLB", glb_instance)
	if visible_fbx:
		_print_model_aabb("可见FBX", visible_fbx)
	print("[Player3DTest] ModelSlot.scale = %s, FBX.scale = 65, 总缩放 = %.0f" % [
		str(slot.scale), PROXY_SCALE * 65.0
	])
	
	# 合并多个 AnimationPlayer 的所有动画到第一个 AnimationPlayer 的默认库
	# 关键修复：之前只看 first_fbx_anim_player 的库，漏掉其他 3 个 AnimationPlayer
	if first_fbx_anim_player:
		# 获取或创建默认库（first_fbx_anim_player 可能已经没有默认库）
		var default_lib: AnimationLibrary = null
		if first_fbx_anim_player.has_animation_library(""):
			default_lib = first_fbx_anim_player.get_animation_library("")
		if default_lib == null:
			default_lib = AnimationLibrary.new()
			first_fbx_anim_player.add_animation_library("", default_lib)
		# 遍历所有 AnimationPlayer（不只是第一个），把它们的动画深拷贝到默认库
		for src_ap in all_anim_players:
			for lib_name in src_ap.get_animation_library_list():
				var lib: AnimationLibrary = src_ap.get_animation_library(lib_name)
				if lib == null:
					continue
				for anim_name in lib.get_animation_list():
					var src_anim: Animation = lib.get_animation(anim_name)
					if src_anim:
						# 深拷贝 animation（防止共享引用冲突）
						var cloned: Animation = src_anim.duplicate(true)
						# 用 lib_name 作为最终动画名（lib_name 就是 idle/run/throw/catch）
						default_lib.add_animation(lib_name, cloned)
						print("[Player3DTest] ✅ 合并动画 %s -> %s" % [anim_name, lib_name])
				# 删除源库
				if lib_name != "":
					src_ap.remove_animation_library(lib_name)
	# 挂载第一个 AnimationPlayer 到 root.meta
	if first_fbx_anim_player:
		root.set_meta("anim_player", first_fbx_anim_player)
		root.set_meta("current_anim", "idle")
		# 列出实际动画名
		var final_list: PackedStringArray = first_fbx_anim_player.get_animation_list()
		print("[Player3DTest] 合并后动画列表: %s (共 %d 个)" % [str(final_list), final_list.size()])
		# 让 idle 循环，其它不循环
		for anim_name in final_list:
			var anim: Animation = first_fbx_anim_player.get_animation(anim_name)
			if anim:
				if anim_name == "idle":
					anim.loop_mode = Animation.LOOP_LINEAR
				else:
					anim.loop_mode = Animation.LOOP_NONE
		# 默认播放 idle
		if first_fbx_anim_player.has_animation("idle"):
			first_fbx_anim_player.play("idle")
			print("[Player3DTest] ▶️ 默认播放 idle")
		else:
			push_warning("[Player3DTest] ❌ 没有 idle 动画可以播放")

	# ========== 队伍色脚下环（用合理尺寸匹配 scale=70 球员）==========
	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 25.0
	cyl.bottom_radius = 25.0
	cyl.height = 3.0
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = team_color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = team_color
	ring_mat.emission_energy_multiplier = 0.3
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(ring)

	# ========== HandProxy 节点（投球手挂接点，世界坐标）==========
	# 球员在 ground (y=0)，模型高度 50 单位 → 头顶约 y=50
	# 投球手位置在右肩上方（world 坐标系下）
	# 球飞行/持球跟随此点
	var hand_proxy := Node3D.new()
	hand_proxy.name = "HandProxy"
	# 世界坐标：球员右肩上方 (8, 42, 0)
	hand_proxy.position = Vector3(8.0, 42.0, 0.0)
	root.add_child(hand_proxy)

	return root


func _print_model_aabb(label: String, node: Node) -> void:
	"""打印模型的 AABB 大小（诊断用）"""
	if node == null:
		print("[Player3DTest] %s: null" % label)
		return
	var total_aabb: AABB = AABB()
	var found_any: bool = false
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D and mi.mesh:
			var aabb: AABB = mi.mesh.get_aabb()
			print("[Player3DTest] %s mesh='%s' AABB size=%s" % [label, mi.name, str(aabb.size)])
			if not found_any:
				total_aabb = aabb
				found_any = true
			else:
				total_aabb = total_aabb.merge(aabb)
	if found_any:
		print("[Player3DTest] %s 总 AABB size=%s" % [label, str(total_aabb.size)])
	else:
		print("[Player3DTest] %s: 未找到 MeshInstance3D" % label)


func _hide_all_meshes(node: Node) -> void:
	"""递归隐藏节点下所有 MeshInstance3D（GLB 加载时调用，仅保留材质）"""
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = false
		# 但保留 StandardMaterial3D
		return
	for child in node.get_children():
		_hide_all_meshes(child)


func _find_animation_player_in(node: Node) -> AnimationPlayer:
	"""递归查找 AnimationPlayer"""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player_in(child)
		if found:
			return found
	return null


## ==================== 创建 2D 球员 (走 player.gd 2D 模式) ====================


func _create_ball_proxy_3d() -> void:
	"""在 SubViewport 内创建决竞球 3D 代理"""
	if ball_2d == null:
		push_warning("[Player3DTest] ball_2d 未创建，跳过 BallProxy3D")
		return
	var BallProxy3DScript := load("res://scripts/test/ball_proxy_3d.gd")
	if BallProxy3DScript == null:
		push_error("[Player3DTest] 无法加载 ball_proxy_3d.gd")
		return
	_ball_proxy_3d = Node3D.new()
	_ball_proxy_3d.set_script(BallProxy3DScript)
	_ball_proxy_3d.name = "BallProxy3D"
	# 必须在 add_child 后再设置 NodePath
	_big_cam_vp.add_child(_ball_proxy_3d)
	# 设置节点引用
	if _ball_proxy_3d is BallProxy3D:
		(_ball_proxy_3d as BallProxy3D).ball_2d = ball_2d
		(_ball_proxy_3d as BallProxy3D).proxy_a = _proxy_a
		(_ball_proxy_3d as BallProxy3D).proxy_b = _proxy_b
	# 兜底用 set 也设置
	_ball_proxy_3d.set("ball_2d", ball_2d)
	_ball_proxy_3d.set("proxy_a", _proxy_a)
	_ball_proxy_3d.set("proxy_b", _proxy_b)
	# 初始球在 A 球员头顶
	_ball_proxy_3d.global_position = Vector3(-300.0, 55.0, 0.0)
	print("[Player3DTest] ✅ BallProxy3D 创建完成，初始位置(-300, 80, 0)")


func _make_3d_player(team_color: Color) -> Node3D:
	"""加载 player1 3D 模型

	流程（关键：GLB贴图 + FBX骨骼动画）:
	  1. 加载 GLB 做基础模型（有正确 UV+PBR 贴图）
	  2. 加载 idle FBX 获取 Skeleton3D 和 AnimationPlayer
	  3. 将 FBX 的骨骼和动画移到 GLB 上
	  4. 配置 AnimationPlayer + 合并 run/throw/catch 动画
	  5. 确保 GLB scale = 1.0（由 ModelSlot 的 scale=70 控制大小）

	返回 root Node3D, 内含 ModelSlot(含模型+动画) + 色环标记
	"""
	var root := Node3D.new()
	root.name = "PlayerProxy3D"

	# ========== ModelSlot 父容器 ==========
	var slot := Node3D.new()
	slot.name = "ModelSlot"
	slot.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	slot.scale = Vector3(70.0, 70.0, 70.0)
	root.add_child(slot)

	# ========== 1. 加载 GLB 做基础模型（有正确贴图） ==========
	var anim_player: AnimationPlayer = null
	var body_loaded := false
	var body_inst: Node = null

	var glb_scene: PackedScene = load(PLAYER1_BODY_PATH)
	if glb_scene != null:
		body_inst = glb_scene.instantiate()
		if body_inst and body_inst is Node:
			slot.add_child(body_inst)
			# GLB 缩放强制为 1.0
			if body_inst is Node3D:
				(body_inst as Node3D).scale = Vector3(1.0, 1.0, 1.0)
			body_loaded = true
			_hide_mixamo_helpers(body_inst)
			
			# 诊断: 检查 GLB mesh 和材质
			print("[Player3DTest] ===== GLB 模型诊断 =====")
			for child in body_inst.find_children("*", "MeshInstance3D", true, false):
				if child is MeshInstance3D:
					var mi: MeshInstance3D = child
					if mi.mesh:
						var aabb: AABB = mi.mesh.get_aabb()
						var surf_count: int = mi.mesh.get_surface_count()
						var mat_info: String = ""
						for s in range(surf_count):
							var mat = mi.mesh.surface_get_material(s)
							if mat and mat is StandardMaterial3D:
								var sm: StandardMaterial3D = mat
								if sm.albedo_texture:
									mat_info += " surf%d=%s" % [s, sm.albedo_texture.resource_path.get_file()]
						print("[Player3DTest] GLB mesh '%s': AABB=%s, surfaces=%d%s" % [mi.name, str(aabb.size), surf_count, mat_info])
			
			# 检查 GLB 是否有 Skeleton3D
			var glb_skel = _find_node_of_type_static(body_inst, "Skeleton3D")
			print("[Player3DTest] GLB has Skeleton3D: %s" % (glb_skel != null))
		else:
			push_warning("[Player3DTest] GLB 实例化失败")
	else:
		push_warning("[Player3DTest] 无法加载 GLB: %s" % PLAYER1_BODY_PATH)
		return root

	# ========== 2. 从 idle FBX 获取 Skeleton3D 和 AnimationPlayer ==========
	var fbx_skel: Skeleton3D = null
	if body_loaded:
		var idle_scene: PackedScene = load(PLAYER1_IDLE_PATH)
		if idle_scene != null:
			var fbx_inst: Node = idle_scene.instantiate()
			if fbx_inst:
				# 获取 AnimationPlayer
				var fbx_ap = _find_animation_player_static(fbx_inst)
				if fbx_ap:
					# 把 AnimationPlayer 移到 GLB 上
					fbx_inst.remove_child(fbx_ap)
					body_inst.add_child(fbx_ap)
					anim_player = fbx_ap
					print("[Player3DTest] AnimationPlayer 从 FBX 移到 GLB")
				
				# 获取 Skeleton3D
				fbx_skel = _find_node_of_type_static(fbx_inst, "Skeleton3D")
				if fbx_skel:
					# 把 Skeleton3D 移到 GLB 上
					fbx_inst.remove_child(fbx_skel)
					body_inst.add_child(fbx_skel)
					print("[Player3DTest] Skeleton3D 从 FBX 移到 GLB: %s" % fbx_skel.name)
				
				fbx_inst.queue_free()
		else:
			push_warning("[Player3DTest] 无法加载 idle FBX: %s" % PLAYER1_IDLE_PATH)

	# ========== 3. 配置 AnimationPlayer ==========
	if anim_player != null:
		anim_player.set("process_callback", AnimationPlayer.ANIMATION_PROCESS_PHYSICS)
		_rename_default_anim_to(anim_player, "idle")
		if anim_player.has_animation("idle"):
			var idle_anim: Animation = anim_player.get_animation("idle")
			if idle_anim:
				idle_anim.loop_mode = Animation.LOOP_LINEAR
				print("[Player3DTest] idle loop_mode 设为 LOOP_LINEAR")

	# ========== 4. 合并 run/throw/catch 动画 ==========
	if anim_player != null:
		_merge_proxy_animations(anim_player, slot)

	# ========== 把 AnimationPlayer 存到 root meta ==========
	root.set_meta("anim_player", anim_player)
	root.set_meta("current_anim", "idle")

	# ========== 队伍色脚下环 ==========
	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 25.0
	cyl.bottom_radius = 25.0
	cyl.height = 3.0
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = team_color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = team_color
	ring_mat.emission_energy_multiplier = 0.3
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(ring)

	# ========== 投球手挂接点 HandProxy ==========
	var hand_proxy := Node3D.new()
	hand_proxy.name = "HandProxy"
	hand_proxy.position = Vector3(8.0, 50.0, 0.0)
	root.add_child(hand_proxy)

	var hand_marker := MeshInstance3D.new()
	hand_marker.name = "HandMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 4.0
	sphere.height = 8.0
	hand_marker.mesh = sphere
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(0.3, 1.0, 0.3)
	marker_mat.emission_energy_multiplier = 0.5
	hand_marker.material_override = marker_mat
	hand_proxy.add_child(hand_marker)

	# 诊断输出
	if not body_loaded:
		push_error("[Player3DTest] 玩家 3D 模型完全加载失败, 仅剩色环标记")
	elif anim_player != null:
		var lib = anim_player.get_animation_library("")
		if lib:
			var anim_list = lib.get_animation_list()
			print("[Player3DTest] ✅ 动画库内容: %s" % str(anim_list))
			for a_name in anim_list:
				var a: Animation = lib.get_animation(a_name)
				print("[Player3DTest]   动画 '%s': length=%.2f, loop=%d, tracks=%d" % [
					a_name, a.length, a.loop_mode, a.get_track_count()
				])
	else:
		push_error("[Player3DTest] ❌❌❌ anim_player 为 null！模型不会有任何动画！")

	# 延迟播放 idle（等节点加入场景树后）
	if anim_player != null and anim_player.has_animation("idle"):
		call_deferred("_play_idle_deferred", anim_player)

	return root


func _play_idle_deferred(ap: AnimationPlayer) -> void:
	if ap and is_instance_valid(ap):
		ap.play("idle")
		_manual_anim_locked = true
		call_deferred("_unlock_animation_after_init")
		print("[Player3DTest] ✅ 延迟播放 idle, current=%s" % ap.current_animation)


## ==================== 3D 模型辅助函数(对齐 battle/player.gd) ====================

## 隐藏 Mixamo 残留的 Icosphere 参考球
static func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false


## 递归隐藏节点下所有 MeshInstance3D 和其他可见几何体（用于隐藏 FBX 的显示，只保留骨骼动画）
static func _hide_all_visible_meshes(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		node.visible = false
		print("[Player3DTest] 隐藏 mesh: %s" % node.name)
	for node in root.find_children("*", "Skeleton3D", true, false):
		node.visible = false


## 从 GLB 复制带贴图的材质到 FBX 的 mesh
## 解决：GLB 有贴图没动画，FBX 有动画没贴图；迁移后 FBX mesh 既有贴图又能被骨骼驱动
## 策略：按索引匹配（GLB第N个mesh → FBX第N个mesh），每个surface单独设置材质
## 关键：正确设置 PBR 贴图的颜色空间（Albedo用sRGB，Normal/MR用Linear）
static func _copy_textures_from_glb_to_fbx(glb_root: Node, fbx_root: Node) -> void:
	if glb_root == null or fbx_root == null:
		return

	# 收集 GLB 所有 mesh 的所有 surface 材质
	var glb_surface_materials: Array = []  # [ [mat0, mat1, ...], ... ]
	
	for mi in glb_root.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var mesh_inst: MeshInstance3D = mi
		if mesh_inst.mesh == null:
			continue
		var surf_count: int = mesh_inst.mesh.get_surface_count()
		var surface_mats: Array = []
		for i in range(surf_count):
			var mat = mesh_inst.mesh.surface_get_material(i)
			if mat == null:
				mat = mesh_inst.material_override
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				surface_mats.append(sm)
			else:
				surface_mats.append(null)
		
		if surface_mats.size() > 0:
			glb_surface_materials.append(surface_mats)
			# 诊断输出
			var first_mat = surface_mats[0]
			var tex_info: String = "无贴图"
			if first_mat and first_mat.albedo_texture:
				tex_info = first_mat.albedo_texture.resource_path.get_file()
			print("[Player3DTest] GLB mesh '%s': %d surfaces, albedo=%s" % [mesh_inst.name, surf_count, tex_info])

	# 收集 FBX 所有 mesh
	var fbx_meshes: Array = []
	for mi in fbx_root.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D and mi.mesh != null:
			fbx_meshes.append(mi)

	print("[Player3DTest] GLB meshes=%d, FBX meshes=%d" % [glb_surface_materials.size(), fbx_meshes.size()])

	# 按索引匹配：GLB第N个mesh → FBX第N个mesh
	var match_count: int = min(glb_surface_materials.size(), fbx_meshes.size())
	for idx in range(match_count):
		var fbx_mi: MeshInstance3D = fbx_meshes[idx]
		var glb_mats: Array = glb_surface_materials[idx]
		var fbx_surf_count: int = fbx_mi.mesh.get_surface_count()
		
		for surf_idx in range(min(glb_mats.size(), fbx_surf_count)):
			var glb_mat = glb_mats[surf_idx]
			if glb_mat == null:
				continue
			# 复制材质（保留所有 PBR 贴图和参数）
			var mat_copy: StandardMaterial3D = glb_mat.duplicate()
			
			# ===== 修复颜色空间：Albedo用sRGB，Normal/MR用Linear =====
			_fix_texture_color_spaces(mat_copy)
			
			# 使用 surface override 应用材质
			fbx_mi.set_surface_override_material(surf_idx, mat_copy)
		
		print("[Player3DTest] ✅ FBX mesh[%d] '%s' 应用 GLB 材质 (%d surfaces, 颜色空间已修复)" % [idx, fbx_mi.name, min(glb_mats.size(), fbx_surf_count)])

	# 如果 GLB mesh 数量 > FBX，警告
	if glb_surface_materials.size() > fbx_meshes.size():
		print("[Player3DTest] ⚠️ GLB有%d个mesh但FBX只有%d个，多余材质未应用" % [glb_surface_materials.size(), fbx_meshes.size()])


## 修复 PBR 材质的纹理过滤，确保贴图清晰
## 保留 GLB 原有的 PBR 贴图和参数，不强制覆盖
static func _fix_texture_color_spaces(mat: StandardMaterial3D) -> void:
	if mat == null:
		return
	
	# ===== 纹理过滤设置 =====
	# 使用 LINEAR_WITH_MIPMAPS 在远近距离都清晰
	# 这是唯一需要修改的参数，其他保留 GLB 原值
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	
	# ===== 诊断：输出 GLB 材质的原始参数 =====
	var info: String = ""
	if mat.albedo_texture != null:
		info += "Albedo=%s, " % mat.albedo_texture.resource_path.get_file()
	# Godot 4: normal_map 是 Property, 访问使用 get()
	var normal_tex = mat.get("normal_map")
	if normal_tex != null:
		info += "Normal=%s, " % normal_tex.resource_path.get_file()
	if mat.metallic_texture != null:
		info += "Metallic=%s, " % mat.metallic_texture.resource_path.get_file()
	if mat.roughness_texture != null:
		info += "Roughness=%s, " % mat.roughness_texture.resource_path.get_file()
	info += "metallic=%.2f, roughness=%.2f" % [mat.metallic, mat.roughness]
	print("[Player3DTest]   材质参数: %s" % info)


## 把主动画播放器默认库("")里的第一个动画重命名为 new_name
static func _rename_default_anim_to(ap: AnimationPlayer, new_name: String) -> void:
	if ap == null:
		return
	if not ap.has_animation_library(""):
		return
	var default_lib := ap.get_animation_library("")
	var anim_list := default_lib.get_animation_list()
	if anim_list.is_empty():
		return
	var old_name: String = anim_list[0]
	if old_name == new_name:
		return
	var anim := default_lib.get_animation(old_name)
	# 用 duplicate(true) 断开与原始资源的引用
	var anim_copy: Animation = anim.duplicate(true)
	default_lib.add_animation(new_name, anim_copy)
	if default_lib.has_animation(old_name):
		default_lib.remove_animation(old_name)


## 深拷贝 AnimationPlayer 中所有动画库，断开与 PackedScene 缓存的共享引用
## Godot 的 AnimationLibrary/Animation 是 Resource，instantiate() 后仍共享同一份
## 必须深拷贝后才能安全修改（重命名/合并），否则第二次 instantiate 会继承第一次的修改
static func _deep_copy_anim_library(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	var lib_keys = ap.get_animation_library_list()
	for lib_key in lib_keys:
		var old_lib: AnimationLibrary = ap.get_animation_library(lib_key)
		var new_lib := AnimationLibrary.new()
		for anim_name in old_lib.get_animation_list():
			var old_anim: Animation = old_lib.get_animation(anim_name)
			var new_anim: Animation = old_anim.duplicate(true)
			new_lib.add_animation(anim_name, new_anim)
		# 用新库替换旧库（断开共享引用）
		ap.remove_animation_library(lib_key)
		ap.add_animation_library(lib_key, new_lib)


## 把 run/throw/catch 三个 FBX 的动画合并到主动画播放器的默认库
## 对齐 bd596c2 版本: 直接 instantiate, 临时挂到 slot 下, 提取动画后释放
static func _merge_proxy_animations(ap: AnimationPlayer, slot: Node3D) -> void:
	if ap == null or slot == null:
		return
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	var default_lib := ap.get_animation_library("")

	var paths := {
		"run": PLAYER1_RUN_PATH,
		"throw": PLAYER1_THROW_PATH,
		"catch": PLAYER1_CATCH_PATH,
	}

	for semantic_name in paths:
		if default_lib.has_animation(semantic_name):
			continue
		var fbx_scene := load(paths[semantic_name]) as PackedScene
		if fbx_scene == null:
			push_warning("[Player3DTest] 无法加载动画FBX: %s" % paths[semantic_name])
			continue
		var fbx_inst: Node = fbx_scene.instantiate()
		if fbx_inst == null:
			continue
		# 临时挂到 slot 下才能访问 AnimationPlayer
		slot.add_child(fbx_inst)
		var tmp_ap := _find_animation_player_static(fbx_inst)
		if tmp_ap != null:
			for lib_key in tmp_ap.get_animation_library_list():
				var src_lib := tmp_ap.get_animation_library(lib_key)
				for src_anim_name in src_lib.get_animation_list():
					var anim: Animation = src_lib.get_animation(src_anim_name)
					if anim == null:
						continue
					var anim_copy: Animation = anim.duplicate(true) if anim else null
					if anim_copy == null:
						anim_copy = anim
					default_lib.add_animation(semantic_name, anim_copy)
					var merged_anim: Animation = default_lib.get_animation(semantic_name)
					if merged_anim:
						if semantic_name in ["throw", "catch"]:
							merged_anim.loop_mode = Animation.LOOP_NONE
						else:
							merged_anim.loop_mode = Animation.LOOP_LINEAR
					print("[Player3DTest] 合并动画 '%s' (原名 '%s', loop=%s)" % [
						semantic_name, src_anim_name,
						"NONE" if semantic_name in ["throw","catch"] else "LINEAR"
					])
					break
				break
		fbx_inst.queue_free()


## 静态递归查找指定类型的节点
static func _find_node_of_type_static(node: Node, type_name: String) -> Node:
	if node == null:
		return null
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found = _find_node_of_type_static(child, type_name)
		if found:
			return found
	return null


## 诊断函数: 检查 FBX 缩放后的实际世界大小
func _diagnose_fbx_size(fbx_root: Node) -> void:
	if fbx_root == null:
		return
	await get_tree().process_frame
	var slot: Node3D = fbx_root.get_parent() as Node3D
	if slot == null:
		return
	print("[Player3DTest] === FBX 缩放诊断 ===")
	print("[Player3DTest] FBX scale: %s" % fbx_root.scale)
	print("[Player3DTest] ModelSlot scale: %s" % slot.scale)
	print("[Player3DTest] ModelSlot transform basis: %s" % slot.transform.basis)
	var total_scale: Vector3 = Vector3(fbx_root.scale.x * slot.scale.x, fbx_root.scale.y * slot.scale.y, fbx_root.scale.z * slot.scale.z)
	print("[Player3DTest] 总缩放: %s" % total_scale)
	for child in fbx_root.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh:
				var aabb: AABB = mi.mesh.get_aabb()
				var world_size: Vector3 = Vector3(aabb.size.x * total_scale.x, aabb.size.y * total_scale.y, aabb.size.z * total_scale.z)
				print("[Player3DTest] 世界尺寸: %s (AABB: %s)" % [world_size, aabb.size])


## 诊断函数: 检查相机视角
func _diagnose_camera_view() -> void:
	if _big_camera == null or not is_instance_valid(_big_camera):
		return
	await get_tree().process_frame
	var cam_pos: Vector3 = _big_camera.transform.origin
	print("[Player3DTest] === 相机视角诊断 ===")
	print("[Player3DTest] 相机位置: %s" % cam_pos)
	print("[Player3DTest] 相机朝向(相机-Z): %s" % _big_camera.get_camera_transform().basis.z)
	# 检查代理体位置
	if _proxy_a and is_instance_valid(_proxy_a):
		var proxy_pos: Vector3 = _proxy_a.position
		var dist: float = cam_pos.distance_to(proxy_pos)
		print("[Player3DTest] 代理A位置: %s, 距相机: %.1f" % [proxy_pos, dist])
		# 模型高度 50 单位在当前距离的张角
		var half_fov_rad: float = deg_to_rad(_big_camera.fov / 2.0)
		var visible_height: float = 2.0 * dist * tan(half_fov_rad)
		var model_angle_ratio: float = 50.0 / visible_height
		print("[Player3DTest] 可见高度: %.1f, 模型占比: %.1f%%" % [visible_height, model_angle_ratio * 100.0])
	if _proxy_b and is_instance_valid(_proxy_b):
		var proxy_pos: Vector3 = _proxy_b.position
		var dist: float = cam_pos.distance_to(proxy_pos)
		print("[Player3DTest] 代理B位置: %s, 距相机: %.1f" % [proxy_pos, dist])
		var half_fov_rad: float = deg_to_rad(_big_camera.fov / 2.0)
		var visible_height: float = 2.0 * dist * tan(half_fov_rad)
		var model_angle_ratio: float = 50.0 / visible_height
		print("[Player3DTest] 可见高度: %.1f, 模型占比: %.1f%%" % [visible_height, model_angle_ratio * 100.0])


## 静态递归查找 AnimationPlayer(被 _merge_proxy_animations 调用)
static func _find_animation_player_static(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player_static(child)
		if found:
			return found
	return null


## 从源 AnimationPlayer 复制 idle 动画到目标 AnimationPlayer 的空库
static func _copy_animation_library(source: AnimationPlayer, target: AnimationPlayer) -> void:
	if source == null or target == null:
		return
	# 确保目标有空库
	if not target.has_animation_library(""):
		target.add_animation_library("", AnimationLibrary.new())
	var target_lib := target.get_animation_library("")
	
	var libs = source.get_animation_library_list()
	for lib_name in libs:
		var src_lib := source.get_animation_library(lib_name)
		var anims = src_lib.get_animation_list()
		for anim_name in anims:
			var anim = src_lib.get_animation(anim_name)
			if anim:
				var anim_copy: Animation = anim.duplicate(true)
				target_lib.add_animation(anim_name, anim_copy)
				print("  复制动画: %s (from lib '%s'), length=%.2f, tracks=%d" % [anim_name, lib_name, anim.length, anim.get_track_count()])


## 修复 proxy 内所有 MeshInstance3D 的白膜问题 + PBR 完整贴图支持
## 加载完整的 PBR 贴图套装：Albedo + Metallic/Roughness + Normal
func _fix_proxy_materials(slot: Node3D) -> void:
	if slot == null:
		return

	# body GLB 目录（主贴图在这里）
	var body_dir: String = PLAYER1_BODY_PATH.get_base_dir()
	var body_base: String = PLAYER1_BODY_PATH.get_file().get_basename()

	print("[Player3DTest] _fix_proxy_materials: body_dir=%s" % body_dir)

	# PBR 贴图路径
	var albedo_path: String = body_dir + "/" + body_base + "_texture_pbr_20250901.png"
	var normal_path: String = body_dir + "/" + body_base + "_texture_pbr_20250901_normal.png"

	# 加载 Albedo 贴图
	var albedo_tex: Texture2D = load(albedo_path)
	var normal_tex: Texture2D = load(normal_path)

	if albedo_tex == null:
		push_warning("[Player3DTest] ⚠️ Albedo 贴图加载失败: %s" % albedo_path)
		return

	# 设置 Albedo 贴图为 sRGB 颜色空间（颜色贴图必须用 sRGB）
	albedo_tex.resource_local_to_scene = true

	# 设置 Normal 贴图为线性颜色空间
	if normal_tex != null:
		normal_tex.resource_local_to_scene = true

	var meshes := slot.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_warning("[Player3DTest] _fix_proxy_materials: slot 内没有 MeshInstance3D！")
		return

	for m in meshes:
		var mi: MeshInstance3D = m
		var mesh := mi.mesh
		if mesh == null:
			continue
		var surf_count: int = mesh.get_surface_count()
		for i in range(surf_count):
			# 优先取 surface 自带材质，再取 override
			var mat = mesh.surface_get_material(i)
			if mat == null:
				mat = mi.material_override

			# 创建新材质或使用现有材质
			var sm: StandardMaterial3D
			if mat == null or not (mat is StandardMaterial3D):
				sm = StandardMaterial3D.new()
				mi.set_surface_override_material(i, sm)
				print("[Player3DTest]   '%s' surf%d 新建材质" % [mi.name, i])
			else:
				sm = mat

			# ---- 应用完整 PBR 贴图 ----
			sm.albedo_texture = albedo_tex
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

			# Metallic/Roughness 使用固定值（不用合并的 MR 贴图避免通道混乱）
			sm.metallic = 0.0      # 非金属（布料/皮肤）
			sm.roughness = 0.7     # 适中粗糙度（亚光效果）

			if normal_tex != null:
				# Godot 4: normal_map 通过 set() 设置
				sm.set("normal_map", normal_tex)
				sm.set("normal_map_depth", 0.5)

			print("[Player3DTest]   ✅ '%s' surf%d PBR 完成: albedo=%s, normal=%s" % [
				mi.name, i,
				albedo_tex != null,
				normal_tex != null
			])


func _find_first_node_of_type(node: Node, type_name: String) -> Node:
	"""递归查找节点树中第一个指定类型的节点(诊断用)"""
	if node == null:
		return null
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find_first_node_of_type(child, type_name)
		if found:
			return found
	return null


func _find_first_node3d(node: Node) -> Node3D:
	"""递归查找节点树中第一个 Node3D"""
	if node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var found := _find_first_node3d(child)
		if found:
			return found
	return null


func _play_3d_proxy_anim(node: Node, anim_name: String) -> void:
	"""在代理模型的 AnimationPlayer 上播放指定动画(若存在)"""
	if node == null:
		return
	var ap: AnimationPlayer = _find_animation_player(node)
	if ap == null:
		return
	if ap.has_animation(anim_name):
		ap.play(anim_name)
		print("[Player3DTest] 代理模型动画: %s" % anim_name)
	else:
		# 播放第一个可用动画
		var libs := ap.get_animation_library_list()
		if libs.size() > 0:
			var lib := ap.get_animation_library(libs[0])
			if lib:
				for a_name in lib.get_animation_list():
					ap.play(a_name)
					print("[Player3DTest] 代理模型动画(首个): %s" % a_name)
					return
		print("[Player3DTest] 代理模型无 %s 动画" % anim_name)


func _find_animation_player(node: Node) -> AnimationPlayer:
	"""递归搜索节点树中的 AnimationPlayer"""
	if node == null:
		return null
	var ap := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		return ap
	for child in node.get_children():
		ap = _find_animation_player(child)
		if ap != null:
			return ap
	return null


func _game2d_to_3d(pos2d: Vector2) -> Vector3:
	"""2D游戏坐标 → 大相机3D坐标 (X不变, 游戏Y→3DZ, Y=地面=0)
	球员模型脚底在 y=0，模型高约 50 单位（scale=70）
	"""
	return Vector3(pos2d.x, 0.0, pos2d.y)


## ==================== 大相机模式切换 ====================

func _apply_big_camera_mode(mode: int) -> void:
	"""设置大相机 Camera3D 位置和朝向
	
	坐标系: 游戏X→3D X, 游戏Y→3D Z, 场地上方→3D Y
	
	采用与小相机(set_view_mode)相同的 Transform3D(Basis, origin) 方式,
	避免 look_at() 在俯视/斜视角度下 up 向量翻车导致朝向混乱。
	
	三种模式:
	  俯视  : 绕X轴-90°(镜头朝-Y), 位置 (0, 1000, 0), 正交投影
	  斜视45°: 绕X轴-45°(镜头朝场中心), 位置 (0, 800, 800), 透视
	  平视  : 绕Y轴+90°(镜头朝-X), 位置 (1100, 100, fz), 透视
	"""
	if _big_camera == null or not is_instance_valid(_big_camera):
		return
	match mode:
		CAMERA_MODE_TOP_DOWN:
			_big_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_big_camera.size = BIG_CAM_TOP_ORTHO_SIZE
			_big_camera.transform = Transform3D(
				Basis(Vector3.RIGHT, deg_to_rad(-90.0)),
				Vector3(0.0, BIG_CAM_TOP_Y, 0.0)
			)

		CAMERA_MODE_ANGLED:
			# 与小相机同角度: 绕X轴-45°, 等比放大 origin 到 (0, 800, 800)
			# Basis(rotX -45°) → 相机 -Z = (0, -0.707, -0.707) 世界方向
			# 在场地上方+后方 (0,800,800) 正好指向场中心 (0,0,0)
			_big_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_big_camera.fov = BIG_CAM_FOV
			_big_camera.transform = Transform3D(
				Basis(Vector3.RIGHT, deg_to_rad(-45.0)),
				Vector3(0.0, 800.0, 800.0)
			)
			print("[Player3DTest] 相机设置: fov=%.1f, projection=%d, origin=%s" % [BIG_CAM_FOV, _big_camera.projection, _big_camera.transform.origin])
			call_deferred("_diagnose_camera_view")

		CAMERA_MODE_FOLLOW:
			# 绕Y轴+90° → 相机 -Z = (-1, 0, 0) = 从+X侧朝-X看
			var follow_z: float = 0.0
			if controlled_player and is_instance_valid(controlled_player):
				follow_z = controlled_player.global_position.y
			_big_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_big_camera.fov = BIG_CAM_FOV
			_big_camera.transform = Transform3D(
				Basis(Vector3.UP, deg_to_rad(90.0)),
				Vector3(BIG_CAM_SIDE_X, BIG_CAM_SIDE_Y, follow_z)
			)
		_:
			pass


func _set_big_cam_visibility(visible_state: bool) -> void:
	"""切换大相机覆盖层显示状态, 同步隐藏/显示 2D 场地背景"""
	_big_cam_active = visible_state
	if _big_cam_rect:
		_big_cam_rect.visible = visible_state
	# 2D场地背景: 大相机开时隐藏(避免挡住3D视图)
	if _field_bg:
		_field_bg.visible = not visible_state


## ==================== 移动逻辑 ====================

func _apply_camera_mode_to_players() -> void:
	"""根据 _camera_mode 调整所有球员 SubViewport 内 Camera3D 角度"""
	var players: Array[CharacterBody2D] = [player_a, player_b]
	for player in players:
		if not player or not is_instance_valid(player):
			continue
		player.set_view_mode(_camera_mode)


func _physics_process(_delta: float) -> void:
	_poll_hotkeys()  # 快捷键轮询移到最前面，不依赖 controlled_player
	_process_catch_assist(_delta)  # 接球助手检查
	_check_auto_screenshot()  # 自动截图检查

	if not controlled_player or not is_instance_valid(controlled_player):
		return

	# WASD 移动
	var move_speed: float = controlled_player._get_effective_value("speed", controlled_player.speed)
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir != Vector2.ZERO:
		controlled_player.velocity = input_dir.normalized() * move_speed
	else:
		controlled_player.velocity = Vector2.ZERO

	# 边界 clamp
	var pos := controlled_player.global_position
	pos.x = clampf(pos.x, -FIELD_WIDTH / 2.0 + 30.0, FIELD_WIDTH / 2.0 - 30.0)
	pos.y = clampf(pos.y, -FIELD_HEIGHT / 2.0 + 30.0, FIELD_HEIGHT / 2.0 - 30.0)
	controlled_player.global_position = pos

	# 2D 平视跟随模式: Camera2D 跟随球员
	if _camera_mode == CAMERA_MODE_FOLLOW and camera_2d:
		camera_2d.global_position = controlled_player.global_position

	# 大相机: 同步球员代理位置（proxy = model_3d_anchor，Node2D，直接同步 global_position）
	if _big_cam_active:
		_set_proxy_pos(_proxy_a, player_a.global_position)
		_set_proxy_pos(_proxy_b, player_b.global_position)
		# 平视跟随模式: 大相机 Transform3D 跟随球员 Y 坐标(=3D Z)
		if _camera_mode == CAMERA_MODE_FOLLOW and _big_camera:
			var fz: float = controlled_player.global_position.y
			_big_camera.transform = Transform3D(
				Basis(Vector3.UP, deg_to_rad(90.0)),
				Vector3(BIG_CAM_SIDE_X, BIG_CAM_SIDE_Y, fz)
			)

	# ========== 3D 模型动画: 根据 velocity 自动切换 idle/run ==========
	var current_proxy: Node3D = null
	if controlled_player == player_a and _proxy_a:
		current_proxy = _proxy_a
	elif controlled_player == player_b and _proxy_b:
		current_proxy = _proxy_b
	if current_proxy and is_instance_valid(current_proxy):
		var ap: AnimationPlayer = current_proxy.get_meta("anim_player", null)
		var cur_anim: String = current_proxy.get_meta("current_anim", "idle")
		if ap != null and is_instance_valid(ap):
			# _manual_anim_locked=true 说明 F 键刚触发了 throw/catch，不要自动覆盖
			if _manual_anim_locked:
				# throw/catch 是单次动画，播完后自动解锁恢复自动切换
				var is_one_shot: bool = cur_anim in ["throw", "catch"]
				if is_one_shot and not ap.is_playing():
					_manual_anim_locked = false
					current_proxy.set_meta("current_anim", "idle")
				# 锁定中：不做任何自动切换
			else:
				# 自动 idle ↔ run 切换
				var moving: bool = controlled_player.velocity.length() > 10.0
				var target: String = "idle" if not moving else "run"
				if target != cur_anim and ap.has_animation(target):
					ap.play(target)
					current_proxy.set_meta("current_anim", target)
					var anim_res: Animation = ap.get_animation(target)
					if anim_res:
						anim_res.loop_mode = Animation.LOOP_LINEAR

	_update_debug_label()
	_update_player_panels()  # 同步快捷面板数据
	_poll_hotkeys()  # 轮询快捷键（替代 _input，更可靠）


## ==================== 自动截图测试 ====================

var _screenshot_frame_count: int = 0
var _screenshot_taken: bool = false
var _screenshot_path: String = "E:/项目储存/决竞球battle-ball/sim_results/auto_screenshot.png"


func _check_auto_screenshot() -> void:
	"""每帧检查，达到 180 帧（约3秒）后截图"""
	if _screenshot_taken:
		return
	_screenshot_frame_count += 1
	if _screenshot_frame_count >= 180:
		_take_auto_screenshot()


func _take_auto_screenshot() -> void:
	"""截图保存到 sim_results/ 目录"""
	_screenshot_taken = true
	# 1. 截取整个 2D 视口
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("[Player3DTest] 截图失败: img == null")
	else:
		var err: int = img.save_png(_screenshot_path)
		if err == OK:
			print("[Player3DTest] 📷 自动截图保存: %s" % _screenshot_path)
			print("[Player3DTest] 图片尺寸: %dx%d" % [img.get_width(), img.get_height()])
		else:
			push_error("[Player3DTest] 截图保存失败 err=%d" % err)
	# 2. 截取大相机 SubViewport（3D 渲染内容）
	if _big_cam_vp:
		var vp_img: Image = _big_cam_vp.get_texture().get_image()
		if vp_img:
			var vp_path: String = "E:/项目储存/决竞球battle-ball/sim_results/auto_screenshot_3d.png"
			var err2: int = vp_img.save_png(vp_path)
			if err2 == OK:
				print("[Player3DTest] 📷 3D SubViewport 截图保存: %s (%dx%d)" % [vp_path, vp_img.get_width(), vp_img.get_height()])
			else:
				push_error("[Player3DTest] 3D 截图保存失败 err=%d" % err2)
		else:
			print("[Player3DTest] ⚠️ 3D SubViewport texture image 为 null")


## ==================== 快捷键轮询（边缘检测） ====================

func _poll_hotkeys() -> void:
	var k: bool
	k = Input.is_key_pressed(KEY_TAB)
	if k and not _prev_tab:
		print("[Player3DTest] TAB 触发")
		_hk_tab()
	_prev_tab = k

	k = Input.is_key_pressed(KEY_F1)
	if k and not _prev_f1:
		print("[Player3DTest] F1 触发")
		_hk_throw()
	_prev_f1 = k

	k = Input.is_key_pressed(KEY_F2)
	if k and not _prev_f2:
		print("[Player3DTest] F2 触发")
		_hk_catch()
	_prev_f2 = k

	k = Input.is_key_pressed(KEY_F3)
	if k and not _prev_f3:
		print("[Player3DTest] F3 触发")
		_hk_idle()
	_prev_f3 = k

	k = Input.is_key_pressed(KEY_F4)
	if k and not _prev_f4:
		print("[Player3DTest] F4 触发")
		_hk_camera()
	_prev_f4 = k

	k = Input.is_key_pressed(KEY_F5)
	if k and not _prev_f5:
		print("[Player3DTest] F5 触发")
		_hk_reset()
	_prev_f5 = k

	k = Input.is_key_pressed(KEY_F6)
	if k and not _prev_f6:
		print("[Player3DTest] F6 触发")
		_hk_bigcam()
	_prev_f6 = k


func _hk_tab() -> void:
	_current_control_index = 1 - _current_control_index
	controlled_player = player_a if _current_control_index == 0 else player_b
	print("[Player3DTest] 切换到球员 %s" % ("A" if _current_control_index == 0 else "B"))


func _hk_throw() -> void:
	var px = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
	if px and is_instance_valid(px):
		var ap1: AnimationPlayer = _get_proxy_anim_player(px)
		if ap1 and ap1.has_animation("throw"):
			ap1.play("throw")
			_set_proxy_current_anim(px, "throw")
			_manual_anim_locked = true
			var a1 := ap1.get_animation("throw")
			if a1: a1.loop_mode = Animation.LOOP_NONE
			print("[Player3DTest] ✅ 切 throw 动作")
		else:
			push_warning("[Player3DTest] F1: ap=%s, has_throw=%s" % [ap1, ap1.has_animation("throw") if ap1 else "N/A"])
	else:
		push_warning("[Player3DTest] F1: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])

	# ========== 投球系统：让球从 controlled_player 出发朝对面球员飞 ==========
	_perform_throw()


func _perform_throw() -> void:
	"""执行投球：调用 ball.gd.launch() 触发球出手+飞行
	方向：自动计算 → 朝对面球员
	距离：根据 throw animation 长度 (1.2s) * ball_speed(400) = 480px
	"""
	if ball_2d == null or not is_instance_valid(ball_2d):
		return
	if controlled_player == null or not is_instance_valid(controlled_player):
		return
	# 球必须在 controlled_player 手上
	if ball_2d.owner_player != controlled_player:
		# 自动给球
		_give_ball_to(controlled_player)
	# 找目标（对面队最近的活球员）
	var target: CharacterBody2D = null
	var enemy_team: String = "b" if controlled_player.team == "a" else "a"
	var min_dist: float = INF
	for p in [player_a, player_b]:
		if not p or not is_instance_valid(p):
			continue
		if p.team != enemy_team or p.is_defeated:
			continue
		var d: float = controlled_player.global_position.distance_to(p.global_position)
		if d < min_dist:
			min_dist = d
			target = p
	if target == null:
		# 没有目标 → 朝场地中心 + 远端方向
		var fallback_dir := Vector2.RIGHT if controlled_player.team == "a" else Vector2.LEFT
		var skills_arg: Array[Dictionary] = []  # typed array, 避免 launch 类型错误
		ball_2d.launch(
			controlled_player.global_position + Vector2(0, -40),
			fallback_dir,
			30.0,  # damage
			500.0,  # max_dist
			controlled_player,
			skills_arg
		)
		# 投球手一侧 = 朝投球方向
		_face_throw_direction(controlled_player, fallback_dir)
		# controlled_player 不再持球
		controlled_player.set_carrying_ball(false)
		print("[Player3DTest] 投球(无目标): 方向=%s" % str(fallback_dir))
		return
	# 有目标 → 朝目标方向投
	var throw_dir: Vector2 = (target.global_position - controlled_player.global_position).normalized()
	var skills_arg2: Array[Dictionary] = []
	ball_2d.launch(
		controlled_player.global_position + Vector2(0, -40),
		throw_dir,
		30.0,
		500.0,
		controlled_player,
		skills_arg2
	)
	# 投球手一侧 = 朝投球方向
	_face_throw_direction(controlled_player, throw_dir)
	# controlled_player 不再持球
	controlled_player.set_carrying_ball(false)
	print("[Player3DTest] 投球 → %s 方向=%s 距离=%.0f" % [
		"对队球员" if target else "无目标", str(throw_dir), min_dist
	])


func _face_throw_direction(player: CharacterBody2D, dir: Vector2) -> void:
	"""让 3D 球员代理朝投球方向（旋转 ModelSlot）"""
	var px: Node = _proxy_a if player == player_a else _proxy_b
	if px == null or not is_instance_valid(px):
		return
	var target_angle: float = atan2(dir.x, dir.y)
	_set_proxy_rotation_y(px, target_angle)
	print("[Player3DTest] 投球手一侧: rotation.y=%.2f (dir=%s)" % [target_angle, str(dir)])


func _hk_catch() -> void:
	var px = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
	if px and is_instance_valid(px):
		var ap2: AnimationPlayer = _get_proxy_anim_player(px)
		if ap2 and ap2.has_animation("catch"):
			ap2.play("catch")
			_set_proxy_current_anim(px, "catch")
			_manual_anim_locked = true
			var a2 := ap2.get_animation("catch")
			if a2: a2.loop_mode = Animation.LOOP_NONE
			print("[Player3DTest] ✅ 切 catch 动作")
		else:
			push_warning("[Player3DTest] F2: ap=%s, has_catch=%s" % [ap2, ap2.has_animation("catch") if ap2 else "N/A"])
	else:
		push_warning("[Player3DTest] F2: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])

	# ========== 接球系统：让球飞向 controlled_player ==========
	_perform_catch()


func _perform_catch() -> void:
	"""执行接球：让球从当前位置飞向 controlled_player（强制命中）
	如果球没有 owner，赋予 controlled_player
	"""
	if ball_2d == null or not is_instance_valid(ball_2d):
		return
	if controlled_player == null or not is_instance_valid(controlled_player):
		return

	# 进入待接球状态
	controlled_player.enter_catch_state()

	if ball_2d.is_active:
		# 球正在飞：直接接管其方向，让它飞向 controlled_player
		var new_dir: Vector2 = (controlled_player.global_position - ball_2d.global_position).normalized()
		ball_2d.ball_direction = new_dir
		# 提高球速让接球更"爽快"
		ball_2d.ball_speed = 600.0
		# 让球接近 controlled_player 时进入 catch 状态
		# 通过监测：球到达 30px 内时强制 catch
		_setup_catch_assist(controlled_player)
		print("[Player3DTest] 接球指令: 球改向 controlled_player 飞")
	else:
		# 球没有在飞：直接给 controlled_player 持球
		_give_ball_to(controlled_player)
		print("[Player3DTest] 接球(无飞行): 直接给 controlled_player 持球")


var _catch_assist_target: CharacterBody2D = null

func _setup_catch_assist(target: CharacterBody2D) -> void:
	"""设置接球助手：球到达 target 30px 内时强制 catch"""
	_catch_assist_target = target


func _process_catch_assist(_delta: float) -> void:
	"""每帧检查球是否接近 _catch_assist_target，接近则强制接住"""
	if _catch_assist_target == null or not is_instance_valid(_catch_assist_target):
		return
	if ball_2d == null or not is_instance_valid(ball_2d) or not ball_2d.is_active:
		_catch_assist_target = null
		return
	var dist: float = ball_2d.global_position.distance_to(_catch_assist_target.global_position)
	if dist < 40.0:
		# 球到达 → 强制接住
		var caught_team: String = str(_catch_assist_target.team)
		ball_2d.is_active = false
		_give_ball_to(_catch_assist_target)
		_catch_assist_target.exit_catch_state()
		_catch_assist_target = null
		print("[Player3DTest] ✅ 接球成功！球已给 %s 队" % caught_team)


func _hk_idle() -> void:
	var px = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
	if px and is_instance_valid(px):
		var ap3: AnimationPlayer = _get_proxy_anim_player(px)
		if ap3 and ap3.has_animation("idle"):
			ap3.play("idle")
			_set_proxy_current_anim(px, "idle")
			_manual_anim_locked = false
			var a3 := ap3.get_animation("idle")
			if a3: a3.loop_mode = Animation.LOOP_LINEAR
			# 切 idle 时回正朝向
			_set_proxy_rotation_y(px, 0.0)
			print("[Player3DTest] ✅ 切 idle 动作 + 朝向回正")
		else:
			push_warning("[Player3DTest] F3: ap=%s, has_idle=%s" % [ap3, ap3.has_animation("idle") if ap3 else "N/A"])
	else:
		push_warning("[Player3DTest] F3: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])


func _hk_camera() -> void:
	_camera_mode = (_camera_mode + 1) % 3
	_apply_camera_mode_to_players()
	_apply_big_camera_mode(_camera_mode)
	if _camera_mode == CAMERA_MODE_FOLLOW and camera_2d and controlled_player:
		camera_2d.global_position = controlled_player.global_position
	print("[Player3DTest] 相机模式: %s" % CAMERA_MODE_NAMES[_camera_mode])


func _hk_reset() -> void:
	if player_a:
		player_a.global_position = Vector2(-300.0, 0.0)
	if player_b:
		player_b.global_position = Vector2(300.0, 0.0)
	print("[Player3DTest] 重置位置")


func _hk_bigcam() -> void:
	_set_big_cam_visibility(not _big_cam_active)
	print("[Player3DTest] 大相机视图: %s" % ("ON" if _big_cam_active else "OFF(2D模式)"))


func _unlock_animation_after_init() -> void:
	_manual_anim_locked = false
	print("[Player3DTest] 动画锁定已解锁")


## ==================== 调试 UI ====================

func _create_debug_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ctrl)

	debug_label = Label.new()
	debug_label.position = Vector2(20, 20)
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
	ctrl.add_child(debug_label)

	hint_label = Label.new()
	hint_label.position = Vector2(20, 730)
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hint_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	hint_label.text = "WASD=移动 | Tab=切球员 | F1=throw F2=catch F3=idle | F4=切相机(俯视/斜视45°/平视) | F5=重置 | F6=大相机ON/OFF"
	ctrl.add_child(hint_label)


## ==================== 球员快捷面板（体力+元灵能量条） ====================

func _create_player_panels() -> void:
	"""创建两个球员快捷面板，屏幕底部显示
	每个面板包含：名字 / 体力条(红) / 元灵能量条(蓝) / 持球状态指示
	"""
	# 面板A（队A，左下角）
	_panel_a = _build_one_panel(
		"PanelA", 1,
		Vector2(20, 660),  # 左下角
		Color(0.25, 0.45, 0.95),  # 蓝队
	)
	# 面板B（队B，右下角）
	_panel_b = _build_one_panel(
		"PanelB", 2,
		Vector2(1280 - 320, 660),  # 右下角(1280-320=960)
		Color(0.95, 0.25, 0.25),  # 红队
	)
	# 保存引用
	_name_label_a = _panel_a.get_node_or_null("NameLabel") as Label
	_stam_a = _panel_a.get_node_or_null("StaminaBar") as ProgressBar
	_energy_a = _panel_a.get_node_or_null("EnergyBar") as ProgressBar
	_ball_indicator_a = _panel_a.get_node_or_null("BallIndicator") as ColorRect
	_name_label_b = _panel_b.get_node_or_null("NameLabel") as Label
	_stam_b = _panel_b.get_node_or_null("StaminaBar") as ProgressBar
	_energy_b = _panel_b.get_node_or_null("EnergyBar") as ProgressBar
	_ball_indicator_b = _panel_b.get_node_or_null("BallIndicator") as ColorRect
	print("[Player3DTest] ✅ 球员快捷面板创建完成（队A + 队B）")


func _build_one_panel(panel_name: String, team_idx: int, pos: Vector2, team_color: Color) -> Panel:
	"""构建一个球员快捷面板（Panel + Label + 2 个 ProgressBar + 持球指示）"""
	# Panel 背景
	var panel := Panel.new()
	panel.name = panel_name
	panel.position = pos
	panel.size = Vector2(300, 100)
	# 不透明背景色（避免视觉混乱）
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	bg_style.set_corner_radius_all(6)
	bg_style.border_color = team_color
	bg_style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", bg_style)
	# 鼠标不拦截
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 名字 Label
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.position = Vector2(8, 4)
	name_label.size = Vector2(180, 18)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", team_color)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.text = "队%s" % ("A" if team_idx == 1 else "B")
	panel.add_child(name_label)

	# 持球状态指示（小绿点）
	var ball_ind := ColorRect.new()
	ball_ind.name = "BallIndicator"
	ball_ind.position = Vector2(270, 6)
	ball_ind.size = Vector2(14, 14)
	ball_ind.color = Color(0.2, 0.9, 0.3, 0.3)  # 默认半透明
	panel.add_child(ball_ind)

	# 体力条（红色 ProgressBar）
	var stam := ProgressBar.new()
	stam.name = "StaminaBar"
	stam.position = Vector2(8, 28)
	stam.size = Vector2(284, 18)
	stam.max_value = 100.0
	stam.value = 100.0
	stam.show_percentage = false
	# 红色条 StyleBox
	var stam_bg := StyleBoxFlat.new()
	stam_bg.bg_color = Color(0.15, 0.05, 0.05, 1)
	stam_bg.set_corner_radius_all(2)
	stam.add_theme_stylebox_override("background", stam_bg)
	var stam_fg := StyleBoxFlat.new()
	stam_fg.bg_color = Color(0.92, 0.30, 0.30)  # 红色
	stam_fg.set_corner_radius_all(2)
	stam.add_theme_stylebox_override("fill", stam_fg)
	panel.add_child(stam)

	# 体力 Label
	var stam_label := Label.new()
	stam_label.position = Vector2(10, 30)
	stam_label.size = Vector2(50, 14)
	stam_label.add_theme_font_size_override("font_size", 11)
	stam_label.add_theme_color_override("font_color", Color.WHITE)
	stam_label.text = "体力"
	panel.add_child(stam_label)

	# 元灵能量条（蓝色 ProgressBar）
	var energy := ProgressBar.new()
	energy.name = "EnergyBar"
	energy.position = Vector2(8, 54)
	energy.size = Vector2(284, 14)
	energy.max_value = 100.0
	energy.value = 0.0
	energy.show_percentage = false
	# 蓝色条 StyleBox
	var energy_bg := StyleBoxFlat.new()
	energy_bg.bg_color = Color(0.05, 0.08, 0.15, 1)
	energy_bg.set_corner_radius_all(2)
	energy.add_theme_stylebox_override("background", energy_bg)
	var energy_fg := StyleBoxFlat.new()
	energy_fg.bg_color = Color(0.30, 0.65, 0.95)  # 蓝色
	energy_fg.set_corner_radius_all(2)
	energy.add_theme_stylebox_override("fill", energy_fg)
	panel.add_child(energy)

	# 能量 Label
	var energy_label := Label.new()
	energy_label.position = Vector2(10, 55)
	energy_label.size = Vector2(50, 12)
	energy_label.add_theme_font_size_override("font_size", 10)
	energy_label.add_theme_color_override("font_color", Color.WHITE)
	energy_label.text = "元灵"
	panel.add_child(energy_label)

	# 状态提示文字（投/接/跑/静）
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.position = Vector2(8, 76)
	status_label.size = Vector2(284, 18)
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	status_label.text = "状态: idle"
	panel.add_child(status_label)

	add_child(panel)
	return panel


func _update_player_panels() -> void:
	"""每帧同步快捷面板数据"""
	if player_a and _panel_a:
		_update_one_panel(player_a, _stam_a, _energy_a, _name_label_a, _ball_indicator_a,
			_panel_a.get_node_or_null("StatusLabel") as Label)
	if player_b and _panel_b:
		_update_one_panel(player_b, _stam_b, _energy_b, _name_label_b, _ball_indicator_b,
			_panel_b.get_node_or_null("StatusLabel") as Label)


func _update_one_panel(player: CharacterBody2D, stam_bar: ProgressBar, energy_bar: ProgressBar,
		name_label: Label, ball_ind: ColorRect, status_label: Label) -> void:
	"""更新单个球员的面板数据"""
	if not player or not is_instance_valid(player):
		return
	# 名字
	if name_label and player.char_data and player.char_data.has("name"):
		name_label.text = "%s [%s队]" % [str(player.char_data.name), player.team.to_upper()]
	# 体力
	if stam_bar:
		stam_bar.max_value = player.max_stamina if player.max_stamina > 0 else 100.0
		stam_bar.value = player.stamina
	# 元灵能量
	if energy_bar:
		var max_e: float = player.max_spirit_energy if player.max_spirit_energy > 0 else 100.0
		energy_bar.max_value = max_e
		energy_bar.value = player.spirit_energy
	# 持球状态指示
	if ball_ind:
		if player.is_carrying_ball:
			ball_ind.color = Color(0.2, 1.0, 0.3, 1.0)  # 亮绿
		else:
			ball_ind.color = Color(0.2, 0.6, 0.3, 0.3)  # 暗绿半透明
	# 状态文字
	if status_label:
		var status_text: String = "状态: "
		if player.is_carrying_ball:
			status_text += "[持球] "
		if player.is_ready_to_catch:
			status_text += "[待接] "
		if player.is_charging_throw:
			status_text += "[充能] "
		if player.velocity.length() > 10.0:
			status_text += "[跑] "
		else:
			status_text += "[静] "
		status_label.text = status_text


func _update_debug_label() -> void:
	if not controlled_player or not is_instance_valid(controlled_player):
		return
	var name: String = "A" if controlled_player == player_a else "B"
	var vel := controlled_player.velocity
	var pos := controlled_player.global_position
	var anim_info: Dictionary = controlled_player.get_3d_debug_info()
	var cam_mode: String = CAMERA_MODE_NAMES[_camera_mode]
	var anim_line: String = "(无AnimationPlayer)"
	if anim_info.get("has_anim_player", false):
		var cur_anim: String = anim_info.get("current_anim", "")
		var is_playing: bool = anim_info.get("is_playing", false)
		var anim_pos: float = anim_info.get("anim_pos", 0.0)
		var in_tree: bool = anim_info.get("inside_tree", false)
		anim_line = "%s | playing=%s | pos=%.2f | in_tree=%s" % [
			cur_anim if cur_anim else "(空)", is_playing, anim_pos, in_tree
		]
	debug_label.text = (
		"球员 %s | 相机: %s | 大相机: %s\n"
		+ "位置: (%.0f, %.0f)\n"
		+ "速度len: %.0f\n"
		+ "动画: %s"
	) % [
		name, cam_mode, "ON" if _big_cam_active else "OFF",
		pos.x, pos.y, vel.length(), anim_line
	]
