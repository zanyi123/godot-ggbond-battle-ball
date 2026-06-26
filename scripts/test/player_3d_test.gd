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

## ==================== 大相机 Camera3D 系统 ====================
# 阶段2验证: 在测试场中用 SubViewport+Camera3D 展示三种大相机视角
# 生产版本将直接在 battle_arena 里用 Camera3D 看 3D 场地(阶段1+2实现)

var _big_cam_vp: SubViewport = null       # 大相机渲染 SubViewport
var _big_camera: Camera3D = null          # 大相机 Camera3D
var _big_cam_layer: CanvasLayer = null    # 显示覆盖层
var _big_cam_rect: TextureRect = null     # 全屏显示 SubViewport 纹理
var _big_cam_active: bool = true          # 是否显示大相机覆盖

# 球员位置代理体(在大相机 SubViewport 内可见) — 2026-06-26 替换为 player1 实际 3D 模型
var _proxy_a: Node3D = null
var _proxy_b: Node3D = null

## player1 模型路径(大相机内展示用)
## 与 battle/player.gd CHAR_3D_MODEL_PATHS["char_001"] 完全一致
const PLAYER1_BODY_PATH := "res://建模素材库/3D模型素材/2cff3ad734686d14c0118d195a809dbc.glb"
const PLAYER1_IDLE_PATH := "res://建模素材库/3D模型素材/player1动作/Idle.fbx"
const PLAYER1_RUN_PATH := "res://建模素材库/3D模型素材/player1动作/Jog Forward.fbx"
const PLAYER1_THROW_PATH := "res://建模素材库/3D模型素材/player1动作/Goalie Throw.fbx"
const PLAYER1_CATCH_PATH := "res://建模素材库/3D模型素材/player1动作/Goalkeeper Catch.fbx"

# 大相机参数(3D世界单位 = 游戏像素 1:1)
const BIG_CAM_TOP_Y: float = 1000.0          # 俯视高度
const BIG_CAM_TOP_ORTHO_SIZE: float = 870.0  # 俯视正交尺寸(高=870, 16:9宽≈1547 > 1300)
const BIG_CAM_ANGLED_DIST: float = 1200.0    # 斜视相机到原点距离
const BIG_CAM_SIDE_X: float = 1100.0         # 平视相机X偏移
const BIG_CAM_SIDE_Y: float = 100.0          # 平视相机高度(轻微俯角)
const BIG_CAM_FOV: float = 62.0              # 透视模式视野角

## 球员切换
var _current_control_index: int = 0


## ==================== 初始化 ====================

func _ready() -> void:
	camera_2d = get_node_or_null("Camera2D")
	_create_field()
	_create_players()
	_create_debug_ui()
	_setup_big_camera_system()
	# 默认斜视45°
	_camera_mode = CAMERA_MODE_ANGLED
	_apply_camera_mode_to_players()
	_apply_big_camera_mode(_camera_mode)
	print("[Player3DTest] 加载完成 | WASD移动 Tab切换 F1=throw F2=catch F3=idle F4=切相机 F5=重置 F6=切大相机显示")


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
	player_a = _create_player_node(data_a, "a", Vector2(-300.0, 0.0))
	player_b = _create_player_node(data_b, "b", Vector2(300.0, 0.0))
	add_child(player_a)
	add_child(player_b)
	controlled_player = player_a


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
	env.ambient_light_color = Color(0.6, 0.65, 0.6)
	env.ambient_light_energy = 0.9
	_big_cam_vp.world_3d.environment = env
	add_child(_big_cam_vp)

	# 2. Camera3D
	_big_camera = Camera3D.new()
	_big_camera.near = 1.0
	_big_camera.far = 10000.0
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
	# 初始位置同步
	if player_a:
		_proxy_a.position = _game2d_to_3d(player_a.global_position)
	if player_b:
		_proxy_b.position = _game2d_to_3d(player_b.global_position)


func _make_3d_player(team_color: Color) -> Node3D:
	"""加载 player1 3D 模型, 扶正姿态, 合并4个动作, 带队伍色脚下环

	完全对齐 battle/player.gd 的动画加载流程:
	  1. 加载主 GLB (body) → 挂到 ModelSlot
	  2. 查找 AnimationPlayer → 存到 root meta
	  3. 重命名默认动画为 "idle"
	  4. 合并 run/throw/catch 三个动画 GLB → 主动画播放器
	  5. 设置 animation 为物理帧推进

	ModelSlot Basis: 先用单位矩阵(不旋转), 若模型仍躺着再调
	scale=70 让模型高约 80 单位(大相机 1000+ 距离可见)

	返回 root Node3D, 内含 ModelSlot(含 GLB 模型+动画) + 色环标记
	"""
	var root := Node3D.new()
	root.name = "PlayerProxy3D"

	# ========== ModelSlot 父容器 ==========
	# 单位矩阵: 不旋转, 假设 GLB 导出时已站立
	# 若模型仍躺着, 再尝试 Basis(Vector3.RIGHT, deg_to_rad(-90))
	var slot := Node3D.new()
	slot.name = "ModelSlot"
	slot.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	slot.scale = Vector3(70.0, 70.0, 70.0)
	root.add_child(slot)

	# ========== 1. 加载主 GLB (body) ==========
	var body_scene: PackedScene = load(PLAYER1_BODY_PATH)
	var anim_player: AnimationPlayer = null
	var body_loaded := false

	if body_scene != null:
		var body_inst := body_scene.instantiate()
		if body_inst and body_inst is Node:
			slot.add_child(body_inst)
			body_loaded = true
			# 隐藏 Mixamo 残留的 Icosphere 参考球
			_hide_mixamo_helpers(body_inst)
			# 找 AnimationPlayer
			anim_player = _find_animation_player(body_inst)
			print("[Player3DTest] body GLB loaded, ap=%s" % (anim_player.name if anim_player else "null"))
		else:
			push_warning("[Player3DTest] body GLB 实例化失败")
	else:
		push_warning("[Player3DTest] 无法加载 body GLB: %s" % PLAYER1_BODY_PATH)

	# ========== 兜底: body GLB 无 AnimationPlayer → 换 idle FBX ==========
	if body_loaded and anim_player == null:
		push_warning("[Player3DTest] 主GLB无AnimationPlayer, 换用 idle FBX")
		# 移除 body_inst
		if slot.get_child_count() > 0:
			var old_inst = slot.get_child(0)
			slot.remove_child(old_inst)
			old_inst.queue_free()
		var idle_scene: PackedScene = load(PLAYER1_IDLE_PATH)
		if idle_scene != null:
			var idle_inst := idle_scene.instantiate()
			if idle_inst and idle_inst is Node:
				slot.add_child(idle_inst)
				body_loaded = true
				_hide_mixamo_helpers(idle_inst)
				anim_player = _find_animation_player(idle_inst)
				print("[Player3DTest] 兜底 idle FBX loaded, ap=%s" % (anim_player.name if anim_player else "null"))

	# ========== 2. 重命名默认动画为 "idle" ==========
	if anim_player != null:
		anim_player.set("process_callback", AnimationPlayer.ANIMATION_PROCESS_PHYSICS)
		_rename_default_anim_to(anim_player, "idle")
		# idle 必须循环播放（FBX 原始动画可能默认 LOOP_NONE）
		if anim_player.has_animation("idle"):
			var idle_anim: Animation = anim_player.get_animation("idle")
			if idle_anim:
				idle_anim.loop_mode = Animation.LOOP_LINEAR
				print("[Player3DTest] idle loop_mode 设为 LOOP_LINEAR")

	# ========== 3. 合并 run/throw/catch 动画 ==========
	if anim_player != null:
		_merge_proxy_animations(anim_player, slot)

	# ========== 把 AnimationPlayer 存到 root meta ==========
	root.set_meta("anim_player", anim_player)
	root.set_meta("current_anim", "idle")

	# ========== 队伍色脚下环 ==========
	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 20.0
	cyl.bottom_radius = 20.0
	cyl.height = 2.0
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

	if not body_loaded:
		push_error("[Player3DTest] 玩家 3D 模型完全加载失败, 仅剩色环标记")
	else:
		# 诊断：打印 AnimationPlayer 和动画库状态
		if anim_player != null:
			print("[Player3DTest] ✅ anim_player 找到: %s, is_playing=%s" % [anim_player.get_path(), anim_player.is_playing()])
			if anim_player.has_animation_library(""):
				var lib = anim_player.get_animation_library("")
				var anim_list = lib.get_animation_list()
				print("[Player3DTest] 动画库内容: %s" % str(anim_list))
				for a_name in anim_list:
					var a: Animation = lib.get_animation(a_name)
					print("[Player3DTest]   动画 '%s': length=%.2f, loop=%d" % [a_name, a.length, a.loop_mode])
			else:
				push_warning("[Player3DTest] ❌ anim_player 没有默认动画库!")
		else:
			push_error("[Player3DTest] ❌❌❌ anim_player 为 null！模型不会有任何动画！")

		# 关键：显式播放 idle
		if anim_player != null and anim_player.has_animation("idle"):
			anim_player.play("idle")
			# 等一帧让 play 生效，再检查
			print("[Player3DTest] ✅ 调用 ap.play('idle'), current_animation=%s" % anim_player.current_animation)
		else:
			push_warning("[Player3DTest] ❌ 无法播 idle: ap=%s, has_idle=%s" % [
				anim_player, anim_player.has_animation("idle") if anim_player else "N/A"
			])

		# 修复白膜：实例化后材质贴图可能丢失，强制修复
		_fix_proxy_materials(slot)

	# 诊断：打印场景树结构（确认模型真的挂上去了）
	print("[Player3DTest] _make_3d_player 完成, root 子节点数: %d" % root.get_child_count())
	for c in root.get_children():
		print("[Player3DTest]   root 子节点: %s (%s)" % [c.name, c.get_class()])
	var slot_node = root.get_node_or_null("ModelSlot")
	if slot_node:
		print("[Player3DTest] ModelSlot 子节点数: %d" % slot_node.get_child_count())
		for sc in slot_node.get_children():
			print("[Player3DTest]   Slot 子节点: %s (%s)" % [sc.name, sc.get_class()])

	return root


## ==================== 3D 模型辅助函数(对齐 battle/player.gd) ====================

## 隐藏 Mixamo 残留的 Icosphere 参考球
static func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false


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
	default_lib.add_animation(new_name, anim)
	if default_lib.has_animation(old_name):
		default_lib.remove_animation(old_name)


## 把 run/throw/catch 三个 GLB 的动画合并到主动画播放器的默认库
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
		var glb_scene := load(paths[semantic_name]) as PackedScene
		if glb_scene == null:
			push_warning("[Player3DTest] 无法加载动画GLB: %s" % paths[semantic_name])
			continue
		# 直接 instantiate, 不需要 duplicate (PackedScene.instantiate() 本身就返回新实例)
		var glb_inst: Node = glb_scene.instantiate()
		if glb_inst == null:
			continue
		# 临时挂到 slot 下才能访问 AnimationPlayer
		slot.add_child(glb_inst)
		var tmp_ap := _find_animation_player_static(glb_inst)
		if tmp_ap != null:
			for lib_key in tmp_ap.get_animation_library_list():
				var src_lib := tmp_ap.get_animation_library(lib_key)
				for src_anim_name in src_lib.get_animation_list():
					var anim: Animation = src_lib.get_animation(src_anim_name)
					var anim_copy: Animation = anim.duplicate(true) if anim else null
					if anim_copy == null:
						anim_copy = anim
					default_lib.add_animation(semantic_name, anim_copy)
					# 设置正确的循环模式
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
		glb_inst.queue_free()


## 静态递归查找 AnimationPlayer(被 _merge_proxy_animations 调用)
static func _find_animation_player_static(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player_static(child)
		if found:
			return found
	return null


## 修复 proxy 内所有 MeshInstance3D 的白膜问题 + 材质质量优化
func _fix_proxy_materials(slot: Node3D) -> void:
	## GLB 实例化后，StandardMaterial3D.albedo_texture 常为 null（嵌入材质未正确解析）
	## 同时优化材质渲染质量（防模糊）
	if slot == null:
		return

	# 从 body GLB 路径推导可能的贴图目录
	var glb_path: String = PLAYER1_BODY_PATH
	var base_dir: String = glb_path.get_base_dir()    # res://建模素材库/3D模型素材
	var base_name: String = glb_path.get_file().get_basename()  # 2cff3ad734686d14c0118d195a809dbc

	print("[Player3DTest] _fix_proxy_materials: 尝试从 %s 修复材质" % base_dir)

	var meshes := slot.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi: MeshInstance3D = m
		var mesh := mi.mesh
		if mesh == null:
			continue
		var surf_count: int = mesh.get_surface_count()
		for i in range(surf_count):
			var mat = mesh.surface_get_material(i)
			if mat == null:
				mat = mi.material_override if mi.material_override else null
				if mat == null:
					continue
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				# ---- 贴图加载 ----
				if sm.albedo_texture == null:
					var tried_paths := [
						base_dir + "/" + base_name + "_texture_pbr_20250901.png",
						base_dir + "/body.png",
						base_dir + "/diffuse.png",
						base_dir + "/albedo.png",
						base_dir + "/" + base_name + ".png",
					]
					for p in tried_paths:
						var tex: Texture2D = load(p)
						if tex != null:
							sm.albedo_texture = tex
							print("[Player3DTest]   ✅ 修复 '%s' surface %d: 加载贴图 %s" % [mi.name, i, p])
							break
					if sm.albedo_texture == null:
						push_warning("[Player3DTest]   ❌ '%s' surface %d: 找不到贴图" % [mi.name, i])
				else:
					print("[Player3DTest]   ✅ '%s' surface %d: 已有贴图 %s" % [mi.name, i, sm.albedo_texture.resource_path])

				# ---- 材质质量 ----
				if sm.albedo_texture != null:
					sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


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
	"""2D游戏坐标 → 大相机3D坐标 (X不变, 游戏Y→3DZ, Y=高度中心)"""
	return Vector3(pos2d.x, 50.0, pos2d.y)  # Y=50 = 胶囊体中心高度(height/2)


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

	# 大相机: 同步球员代理位置
	if _big_cam_active:
		if _proxy_a and player_a and is_instance_valid(player_a):
			_proxy_a.position = _game2d_to_3d(player_a.global_position)
		if _proxy_b and player_b and is_instance_valid(player_b):
			_proxy_b.position = _game2d_to_3d(player_b.global_position)
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
			# throw/catch 是手动触发的单次动画，播放期间不自动切换
			# 等播完（is_playing()=false 或 current_anim 不是 throw/catch）再恢复自动切换
			var is_manual_anim: bool = cur_anim in ["throw", "catch"]
			if is_manual_anim and ap.is_playing() and ap.current_animation == cur_anim:
				pass  # 正在播手动动画，不干预
			else:
				var moving: bool = controlled_player.velocity.length() > 10.0
				var target: String = "idle" if not moving else "run"
				if target != cur_anim and ap.has_animation(target):
					ap.play(target)
					current_proxy.set_meta("current_anim", target)
					var anim_res: Animation = ap.get_animation(target)
					if anim_res:
						anim_res.loop_mode = Animation.LOOP_LINEAR

	_update_debug_label()


## ==================== 输入处理 ====================

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		16777217:  # KEY_TAB
			_current_control_index = 1 - _current_control_index
			controlled_player = player_a if _current_control_index == 0 else player_b
			print("[Player3DTest] 切换到球员 %s" % ("A" if _current_control_index == 0 else "B"))
			get_viewport().set_input_as_handled()

		16777248:  # KEY_F1
			# 找到当前 controlled_player 对应的 proxy, 直接操作 AnimationPlayer
			var px1 = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
			print("[Player3DTest] F1: controlled=%s, px=%s" % [controlled_player, px1])
			if px1 and is_instance_valid(px1):
				var ap1: AnimationPlayer = px1.get_meta("anim_player", null)
				print("[Player3DTest] F1: ap=%s, has_throw=%s" % [ap1, ap1.has_animation("throw") if ap1 else "N/A"])
				if ap1 and ap1.has_animation("throw"):
					ap1.play("throw")
					px1.set_meta("current_anim", "throw")
					var a1 := ap1.get_animation("throw")
					if a1: a1.loop_mode = Animation.LOOP_NONE
					print("[Player3DTest] ✅ 切 throw 动作")
			else:
				push_warning("[Player3DTest] F1: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])
			get_viewport().set_input_as_handled()

		16777249:  # KEY_F2
			var px2 = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
			print("[Player3DTest] F2: controlled=%s, px=%s" % [controlled_player, px2])
			if px2 and is_instance_valid(px2):
				var ap2: AnimationPlayer = px2.get_meta("anim_player", null)
				print("[Player3DTest] F2: ap=%s, has_catch=%s" % [ap2, ap2.has_animation("catch") if ap2 else "N/A"])
				if ap2 and ap2.has_animation("catch"):
					ap2.play("catch")
					px2.set_meta("current_anim", "catch")
					var a2 := ap2.get_animation("catch")
					if a2: a2.loop_mode = Animation.LOOP_NONE
					print("[Player3DTest] ✅ 切 catch 动作")
			else:
				push_warning("[Player3DTest] F2: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])
			get_viewport().set_input_as_handled()

		16777250:  # KEY_F3
			var px3 = _proxy_a if (controlled_player and controlled_player == player_a) else _proxy_b
			print("[Player3DTest] F3: controlled=%s, px=%s" % [controlled_player, px3])
			if px3 and is_instance_valid(px3):
				var ap3: AnimationPlayer = px3.get_meta("anim_player", null)
				print("[Player3DTest] F3: ap=%s, has_idle=%s" % [ap3, ap3.has_animation("idle") if ap3 else "N/A"])
				if ap3 and ap3.has_animation("idle"):
					ap3.play("idle")
					px3.set_meta("current_anim", "idle")
					var a3 := ap3.get_animation("idle")
					if a3: a3.loop_mode = Animation.LOOP_LINEAR
					print("[Player3DTest] ✅ 切 idle 动作")
			else:
				push_warning("[Player3DTest] F3: 找不到 proxy！_proxy_a=%s, _proxy_b=%s" % [_proxy_a, _proxy_b])
			get_viewport().set_input_as_handled()

		16777251:  # KEY_F4
			# 循环切换相机模式 → 同步更新大相机+小相机
			_camera_mode = (_camera_mode + 1) % 3
			_apply_camera_mode_to_players()         # 小相机
			_apply_big_camera_mode(_camera_mode)    # 大相机
			if _camera_mode == CAMERA_MODE_FOLLOW and camera_2d and controlled_player:
				camera_2d.global_position = controlled_player.global_position
			print("[Player3DTest] 相机模式: %s" % CAMERA_MODE_NAMES[_camera_mode])
			get_viewport().set_input_as_handled()

		16777252:  # KEY_F5
			if player_a:
				player_a.global_position = Vector2(-300.0, 0.0)
			if player_b:
				player_b.global_position = Vector2(300.0, 0.0)
			print("[Player3DTest] 重置位置")
			get_viewport().set_input_as_handled()

		16777253:  # KEY_F6
			# 切换大相机3D覆盖层
			_set_big_cam_visibility(not _big_cam_active)
			print("[Player3DTest] 大相机视图: %s" % ("ON" if _big_cam_active else "OFF(2D模式)"))
			get_viewport().set_input_as_handled()


## ==================== 调试 UI ====================

func _create_debug_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
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
