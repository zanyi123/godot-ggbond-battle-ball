## 3D 球员测试平台
## 独立测试场景,验证 2.5D 3D 球员在 2D 球场上的显示 + 动画 + 移动
## 功能:
##   WASD = 8方向移动(自动切 idle↔run 动画)
##   F1/F2/F3 = 手动切 throw/catch 动画(验证动作接通)
##   F4 = 回到 idle
##   F5 = 重置位置
##
## 验收清单:
##   [ ] 看到 3D 猪猪侠(非白膜)
##   [ ] 默认播 idle 呼吸
##   [ ] 按 WASD 播 run
##   [ ] 8 方向朝向正确
##   [ ] F1/F2/F3 能手动切动作

extends Node2D

## ==================== 场地常量(与 battle_manager 一致) ====================
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const FIELD_COLOR: Color = Color(0.12, 0.18, 0.12)

## ==================== 节点引用 ====================
var player_a: CharacterBody2D  # 我方(蓝)
var player_b: CharacterBody2D  # 敌方(红)
var controlled_player: CharacterBody2D  # 当前控制的球员
var debug_label: Label  # 右上角调试文字
var hint_label: Label   # 左下角操作提示
var camera_2d: Camera2D  # 主相机(平视跟随模式用)

## 球员切换标志
var _current_control_index: int = 0  # 0=a, 1=b

## 相机模式: 0=俯视全场 1=斜俯视全场(2K默认) 2=平视跟随
var _camera_mode: int = 1
const CAMERA_MODE_TOP_DOWN: int = 0      # 纯俯视(看球员头顶)
const CAMERA_MODE_ANGLED: int = 1        # 斜俯视(2K默认,看全身+正脸)
const CAMERA_MODE_FOLLOW: int = 2        # 平视跟随(球员始终在画面中间)
const CAMERA_MODE_NAMES: Array = ["俯视全场", "斜俯视全场(2K)", "平视跟随"]


## ==================== 初始化 ====================

func _ready() -> void:
	# 获取场景里的 Camera2D 节点(用于平视跟随模式)
	camera_2d = get_node_or_null("Camera2D")
	_create_field()
	_create_players()
	_create_debug_ui()
	# 默认斜俯视全场模式(2K 风格转播视角,看全身站立)
	_camera_mode = CAMERA_MODE_ANGLED
	_apply_camera_mode_to_players()
	print("[Player3DTest] 测试平台已加载 | WASD=移动 | Tab=切换球员 | F1=throw F2=catch F3=idle | F4=切相机(3种) | F5=重置")


## ==================== 创建场地 ====================

func _create_field() -> void:
	"""创建 2D 球场背景(简化版,只画场地+中线+边界)"""
	var field_bg := ColorRect.new()
	field_bg.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	field_bg.position = Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0)
	field_bg.color = FIELD_COLOR
	add_child(field_bg)

	# 中线
	var mid_line := Line2D.new()
	mid_line.add_point(Vector2(0, -FIELD_HEIGHT / 2.0))
	mid_line.add_point(Vector2(0, FIELD_HEIGHT / 2.0))
	mid_line.default_color = Color(0.3, 0.4, 0.3, 0.5)
	mid_line.width = 2.0
	add_child(mid_line)

	# 中圈
	var center_circle := Line2D.new()
	var center_radius: float = 60.0
	var point_count: int = 32
	for i in range(point_count + 1):
		var angle: float = (float(i) / float(point_count)) * TAU
		center_circle.add_point(Vector2(cos(angle), sin(angle)) * center_radius)
	center_circle.default_color = Color(0.3, 0.4, 0.3, 0.5)
	center_circle.width = 2.0
	add_child(center_circle)

	# 边界墙(视觉)
	var border := Line2D.new()
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(FIELD_WIDTH / 2.0, FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, FIELD_HEIGHT / 2.0))
	border.add_point(Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0))
	border.default_color = Color(0.4, 0.5, 0.4)
	border.width = 4.0
	add_child(border)


## ==================== 创建球员 ====================

func _create_players() -> void:
	"""创建两个测试球员(A/B 队各一个)"""
	var data_a := _get_char_data(0)
	var data_b := _get_char_data(1)

	player_a = _create_player_node(data_a, "a", Vector2(-300.0, 0.0))
	player_b = _create_player_node(data_b, "b", Vector2(300.0, 0.0))
	add_child(player_a)
	add_child(player_b)

	controlled_player = player_a


func _get_char_data(index: int) -> Dictionary:
	"""获取角色数据(从 DataManager 或默认)"""
	if DataManager and DataManager.characters.size() > index:
		return DataManager.characters[index]
	# 备用默认数据
	return {
		"id": "test_%d" % index,
		"name": "测试%d" % (index + 1),
		"stamina": 100.0, "attack": 38.0, "defense": 60.0,
		"speed": 70.0, "resilience": 50.0, "defense_factor": 0.15,
	}


func _create_player_node(data: Dictionary, team_name: String, start_pos: Vector2) -> CharacterBody2D:
	"""创建球员节点(复用 player_tag_test 的模式)"""
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.set_script(player_script)
	player.character_id = str(data.get("id", ""))
	player.team = team_name
	player.is_player_controlled = false  # 初始都设为非控制,移动逻辑在本测试脚本里处理
	player.global_position = start_pos
	# initialize 需要 DataManager 有数据
	if DataManager:
		player.initialize(str(data.get("id", "")), team_name, false)
	# 手动确保属性正确(防止 DataManager 没数据)
	player.max_stamina = float(data.get("stamina", 100.0))
	player.stamina = player.max_stamina
	player.attack_power = float(data.get("attack", 38.0))
	player.defense = float(data.get("defense", 60.0))
	player.speed = float(data.get("speed", 70.0)) * 3.25
	player.resilience = float(data.get("resilience", 50.0))
	player.defense_factor = float(data.get("defense_factor", 0.15))
	player.add_to_group("players")
	return player


## ==================== 移动逻辑 ====================

func _physics_process(_delta: float) -> void:
	if not controlled_player or not is_instance_valid(controlled_player):
		return
	# WASD 读取输入
	var move_speed: float = controlled_player._get_effective_value("speed", controlled_player.speed)
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir != Vector2.ZERO:
		controlled_player.velocity = input_dir.normalized() * move_speed
	else:
		controlled_player.velocity = Vector2.ZERO

	# 边界 clamp(防止跑出场地)
	var pos := controlled_player.global_position
	pos.x = clampf(pos.x, -FIELD_WIDTH / 2.0 + 30.0, FIELD_WIDTH / 2.0 - 30.0)
	pos.y = clampf(pos.y, -FIELD_HEIGHT / 2.0 + 30.0, FIELD_HEIGHT / 2.0 - 30.0)
	controlled_player.global_position = pos

	# 平视跟随模式: Camera2D 跟随球员(球员始终在画面中间)
	if _camera_mode == CAMERA_MODE_FOLLOW and camera_2d:
		camera_2d.global_position = controlled_player.global_position

	# 更新调试文字
	_update_debug_label()


## ==================== 输入处理 ====================

func _apply_camera_mode_to_players() -> void:
	"""根据 _camera_mode 调整所有球员的 SubViewport 内 Camera3D 角度
	模式0=俯视: 相机在角色正上方往下看
	模式1=平视: 相机与角色平齐,从正面看过去
	"""
	var players: Array[CharacterBody2D] = [player_a, player_b]
	for player in players:
		if not player or not is_instance_valid(player):
			continue
		player.set_view_mode(_camera_mode)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return

	match event.keycode:
		KEY_TAB:
			# 切换控制球员
			_current_control_index = 1 - _current_control_index
			controlled_player = player_a if _current_control_index == 0 else player_b
			print("[Player3DTest] 切换到球员 %s" % ("A" if _current_control_index == 0 else "B"))
			get_viewport().set_input_as_handled()
		KEY_F1:
			# 手动切 throw 动作
			controlled_player.play_3d_action("throw")
			print("[Player3DTest] 切 throw 动作")
			get_viewport().set_input_as_handled()
		KEY_F2:
			# 手动切 catch 动作
			controlled_player.play_3d_action("catch")
			print("[Player3DTest] 切 catch 动作")
			get_viewport().set_input_as_handled()
		KEY_F3:
			# 手动切 idle 动作
			controlled_player.play_3d_action("idle")
			print("[Player3DTest] 切 idle 动作")
			get_viewport().set_input_as_handled()
		KEY_F4:
			# 循环切换相机模式: 俯视全场 → 斜俯视全场 → 平视跟随 → 俯视全场...
			_camera_mode = (_camera_mode + 1) % 3
			print("[Player3DTest] 相机模式: %s" % CAMERA_MODE_NAMES[_camera_mode])
			# 同步调整所有球员的 SubViewport 相机角度
			_apply_camera_mode_to_players()
			# 平视跟随模式下 Camera2D 立即跳到球员位置
			if _camera_mode == CAMERA_MODE_FOLLOW and camera_2d and controlled_player:
				camera_2d.global_position = controlled_player.global_position
			get_viewport().set_input_as_handled()
		KEY_F5:
			# 重置位置
			player_a.global_position = Vector2(-300.0, 0.0)
			player_b.global_position = Vector2(300.0, 0.0)
			print("[Player3DTest] 重置位置")
			get_viewport().set_input_as_handled()


## ==================== 调试 UI ====================

func _create_debug_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var ctrl := Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(ctrl)

	# 右上角调试文字
	debug_label = Label.new()
	debug_label.position = Vector2(20, 20)
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	# 黑色描边效果(用 shadow)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
	ctrl.add_child(debug_label)

	# 左下角操作提示                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
	hint_label = Label.new()
	hint_label.position = Vector2(20, 600)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hint_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	hint_label.text = "WASD=移动 | Tab=切换球员 | F1=throw F2=catch F3=idle | F4=切相机(俯视/斜俯视/平视跟随) | F5=重置"
	ctrl.add_child(hint_label)


func _update_debug_label() -> void:
	if not controlled_player or not is_instance_valid(controlled_player):
		return
	var name: String = "A" if controlled_player == player_a else "B"
	var vel := controlled_player.velocity
	var pos := controlled_player.global_position
	var anim_info: Dictionary = controlled_player.get_3d_debug_info()
	var cam_mode: String = CAMERA_MODE_NAMES[_camera_mode]
	# 详细显示动画诊断(关键!帮主人看出为什么没播)
	var anim_line: String = "(无AnimationPlayer)"
	if anim_info.get("has_anim_player", false) == true:
		var cur_anim: String = anim_info.get("current_anim", "")
		var is_playing: bool = anim_info.get("is_playing", false)
		var anim_pos: float = anim_info.get("anim_pos", 0.0)
		var in_tree: bool = anim_info.get("inside_tree", false)
		anim_line = "%s | playing=%s | pos=%.2f | in_tree=%s" % [cur_anim if cur_anim else "(空)", is_playing, anim_pos, in_tree]
	debug_label.text = "球员 %s | 相机: %s\n位置: (%.0f, %.0f)\n速度len: %.0f\n动画: %s\n移动中: %s" % [
		name, cam_mode, pos.x, pos.y, vel.length(), anim_line, anim_info.get("is_moving", false)
	]
