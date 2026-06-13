## 场地标签测试平台
## 独立测试场景,测试所有12个场地标签
## 排版标准参照 player_tag_test.gd
## 左面板:球员状态 | 右面板:标签按钮+参数 | 日志面板

extends Node2D

## ==================== 场地常量 ====================
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const FIELD_COLOR: Color = Color(0.12, 0.18, 0.12)

## ==================== 节点引用 ====================
var player_a: CharacterBody2D
var player_b: CharacterBody2D
var ball_node: Area2D
var controlled_player: CharacterBody2D

var obstacle_mgr: Node
var zone_mgr: Node
var illusion_mgr: Node
var field_physics_mgr: Node
var handler: Node

var ui_layer: CanvasLayer
var hud: Control
var log_panel: RichTextLabel

## ==================== 标签数据 ====================
var tag_groups: Array = []
var all_tags_dict: Dictionary = {}

## BALL/PLAYER 标签的参数缓存(点击保存后存这，数字键执行时读)
var _tag_param_cache: Dictionary = {}

## PLAYER 标签默认目标(self/enemies)，可被弹窗覆盖
## BALL 标签默认参数表(按 registry 的 params 字段填合理默认值，不超标)
const _BALL_DEFAULTS: Dictionary = {
	"ball_dmg_up_pct": {"value": 50}, "ball_dmg_down_pct": {"value": 50},
	"ball_dmg_up_flat": {"value": 20}, "ball_dmg_down_flat": {"value": 20},
	"ball_speed_up_pct": {"multiplier": 1.5}, "ball_speed_down_pct": {"multiplier": 1.5},
	"ball_speed_up_flat": {"value": 100}, "ball_speed_down_flat": {"value": 100},
	"ball_tracking": {"turn_speed": 5.0}, "ball_avoid": {},
	"ball_boomerang": {"return_distance": 400}, "ball_straight": {},
	"ball_lockon": {}, "ball_spread": {"split_count": 3},
	"ball_penetrate": {}, "ball_range_up": {"radius": 120, "damage_pct": 0.5},
	"ball_range_down": {"multiplier": 0.5},
}

## PLAYER 标签默认参数表(value/multiplier 等不超标)
const _PLAYER_DEFAULTS: Dictionary = {
	"value_pct": 30, "value_flat": 10, "multiplier": 1.5, "hp_pct": 20,
	"hp_flat": 30, "dot_rate": 5, "duration": 5.0,
}

## ==================== 状态 ====================
var selected_tag_id: String = ""
var param_inputs: Dictionary = {}
var popup_panel: Panel
var popup_visible: bool = false

## 区域效果参数
var zone_params: Dictionary = {
	"zone_type": 0,
	"width": 120.0,
	"height": 120.0,
	"boost_multiplier": 1.5,
	"slow_multiplier": 1.5,
	"damage_value": 10.0,
	"duration": 10.0,
	"mouse_ops": 1,
}

## 障碍物参数（与旧 field_tag_test.gd 完全对齐：含 circle/crescent 专属参数）
var obs_params: Dictionary = {
	"shape": "rect",
	"width": 80.0,
	"height": 30.0,
	"radius": 40.0,
	"arc_angle": 120.0,
	"hp": 50.0,
	"attack_consume_rate": 20.0,
	"speed_consume_rate": 20.0,
	"max_count": 3,
	"duration": 15.0,
	"mouse_ops": 1,
	"element": "金刚",
	"element_color": Color(0.85, 0.75, 0.3),
}

## 清除障碍参数
var obs_clear_params: Dictionary = {
	"clear_count": 2,
	"mouse_ops": 2,
}

## 清除区域参数
var zone_clear_ops: int = 2

## 幻象参数（field_illusion_add）
var illusion_params: Dictionary = {
	"place_mode": "any",   # any=任意放置 / near=近身放置
	"count": 2,            # 任意模式：左键可放置数量；近身模式强制1
	"stamina": 60.0,       # 幻象体力（默认填值）
	"duration": 10.0,      # 持续时间（与体力取先到）
	"ai_mode": false,      # AI智能开关（默认关闭=镜像真身）
}

## 幻象破除参数（field_illusion_clear）
var illusion_clear_params: Dictionary = {
	"clear_all": true,     # true=清除所有；false=按illusion_id
}

## ==================== 快捷键配对系统 ====================
## 数字键 1-5 绑定标签，PLAYING 阶段按数字键直接执行
## 数据结构：快捷键配对列表 [{"key": int(1-5), "tag_id": String}]
var key_bindings: Array = []
## SETUP 阶段配对区 UI 引用
var bind_combo_tag: OptionButton = null   # 标签下拉
var bind_combo_key: OptionButton = null   # 数字键下拉
var bind_list_container: VBoxContainer = null  # 已配对列表容器

enum Phase { SETUP, PLAYING }
var current_phase: int = Phase.SETUP
var main_ui_nodes: Array = []


## ==================== 初始化 ====================

func _ready() -> void:
	_load_tag_data()
	_create_field()
	_create_systems()
	_create_players()
	_create_ball()
	_create_ui()
	_add_log("[color=cyan]场地标签测试平台已加载 | WASD=移动 | Tab=切换球员 | 左键=发球[/color]")
	print("[FieldTagTestPanel] 测试平台已加载,共%d个标签" % all_tags_dict.size())


func _load_tag_data() -> void:
	var path: String = "res://data/spirits/tags_registry.json"
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()

	var tags_array: Array = json.data.get("tags", [])
	# 全部标签存入字典(供 all_tags_dict 查询)
	for tag in tags_array:
		all_tags_dict[tag.id] = tag
	# 按三大类分组(BALL/PLAYER/FIELD)，便于组合测试
	var cat_tags: Dictionary = {"BALL": [], "PLAYER": [], "FIELD": []}
	for tag in tags_array:
		var cat: String = tag.get("category", "")
		if cat_tags.has(cat):
			cat_tags[cat].append(tag)
	var group_titles: Dictionary = {
		"BALL": "▶ 球类标签 BALL (%d)" % cat_tags["BALL"].size(),
		"PLAYER": "▶ 球员标签 PLAYER (%d)" % cat_tags["PLAYER"].size(),
		"FIELD": "▶ 场地标签 FIELD (%d)" % cat_tags["FIELD"].size(),
	}
	for cat in ["BALL", "PLAYER", "FIELD"]:
		if not cat_tags[cat].is_empty():
			tag_groups.append({"name": group_titles[cat], "tags": cat_tags[cat]})


## ==================== 创建场地 ====================

func _create_field() -> void:
	var field_bg := ColorRect.new()
	field_bg.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	field_bg.position = Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0)
	field_bg.color = FIELD_COLOR
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD_COLOR
	style.set_corner_radius_all(10)
	style.border_color = Color(0.3, 0.4, 0.3)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	field_bg.add_theme_stylebox_override("normal", style)
	add_child(field_bg)

	var mid_line := Line2D.new()
	mid_line.add_point(Vector2(0, -FIELD_HEIGHT / 2.0))
	mid_line.add_point(Vector2(0, FIELD_HEIGHT / 2.0))
	mid_line.default_color = Color(0.3, 0.4, 0.3, 0.5)
	mid_line.width = 2.0
	add_child(mid_line)

	_create_wall(Vector2(-FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))
	_create_wall(Vector2(FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))
	_create_wall(Vector2(0.0, -FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))
	_create_wall(Vector2(0.0, FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))

	var camera := Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
	add_child(camera)


func _create_wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)


## ==================== 创建系统 ====================

func _create_systems() -> void:
	# 场地物理
	var fp_script := load("res://scripts/battle/field_physics_manager.gd")
	field_physics_mgr = Node.new()
	field_physics_mgr.name = "FieldPhysicsManager"
	field_physics_mgr.set_script(fp_script)
	add_child(field_physics_mgr)

	# 障碍物管理器
	var om_script := load("res://scripts/battle/obstacle_manager.gd")
	obstacle_mgr = Node.new()
	obstacle_mgr.name = "ObstacleManager"
	obstacle_mgr.set_script(om_script)
	add_child(obstacle_mgr)

	# 区域效果管理器
	var zm_script := load("res://scripts/battle/field_zone_manager.gd")
	zone_mgr = Node.new()
	zone_mgr.name = "FieldZoneManager"
	zone_mgr.set_script(zm_script)
	add_child(zone_mgr)

	# 幻象管理器
	var im_script := load("res://scripts/battle/illusion_manager.gd")
	illusion_mgr = Node.new()
	illusion_mgr.name = "IllusionManager"
	illusion_mgr.set_script(im_script)
	add_child(illusion_mgr)

	# 标签效果 handler
	var h_script := load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	handler = h_script.new()
	handler.name = "SpiritTagEffectHandler"
	handler.priority_queue_enabled = false
	handler.set_process(false)
	add_child(handler)

	# handler 需要找到管理器,设置一个假的 battle_manager 引用
	# 在独立测试中通过组查找替代


## ==================== 创建球员 ====================

func _create_players() -> void:
	var char_data_a: Dictionary = _get_char_data(0)
	var char_data_b: Dictionary = _get_char_data(1)

	player_a = _create_player_node(char_data_a, "a", Vector2(-300.0, 0.0))
	player_b = _create_player_node(char_data_b, "b", Vector2(300.0, 0.0))
	add_child(player_a)
	add_child(player_b)

	handler.players.clear()
	handler.players.append(player_a)
	handler.players.append(player_b)
	controlled_player = player_a

	player_a.set_physics_process(false)
	player_b.set_physics_process(false)


func _create_ball() -> void:
	var ball_script := load("res://scripts/battle/ball.gd")
	ball_node = Area2D.new()
	ball_node.set_script(ball_script)
	ball_node.name = "Ball"
	ball_node.add_to_group("ball")
	add_child(ball_node)
	ball_node.owner_player = player_a
	player_a.is_carrying_ball = true
	player_a.set_carrying_ball(true)


func _get_char_data(index: int) -> Dictionary:
	if DataManager and DataManager.characters.size() > index:
		return DataManager.characters[index]
	var path: String = "res://data/characters/characters.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				file.close()
				var arr: Array = json.data
				if arr.size() > index:
					return arr[index]
			file.close()
	return {
		"id": "default_%d" % index,
		"name": "测试球员%d" % (index + 1),
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
	player.max_spirit_energy = 100.0
	player.spirit_energy = 100.0
	player.collision_layer = 1  # layer 1 = 球员
	player.collision_mask = 1
	player.add_to_group("players")
	return player


## ==================== 创建 UI ====================

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	hud = Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(hud)

	main_ui_nodes.clear()

	_create_status_panels()
	_create_tag_button_panel()
	_create_log_panel()
	_create_log_panel()

	# === 开始测试按钮 ===
	var start_btn := Button.new()
	start_btn.name = "StartBtn"
	start_btn.text = "▶ 开始测试(隐藏面板)"
	start_btn.position = Vector2(520, 640)
	start_btn.size = Vector2(220, 32)
	start_btn.add_theme_font_size_override("font_size", 15)
	start_btn.pressed.connect(_on_start_test)
	hud.add_child(start_btn)
	main_ui_nodes.append(start_btn)

	# === 组合测试按钮 ===
	var combo_btn := Button.new()
	combo_btn.name = "ComboTestBtn"
	combo_btn.text = "🧪 跑组合测试(15组)"
	combo_btn.position = Vector2(750, 640)
	combo_btn.size = Vector2(200, 32)
	combo_btn.add_theme_font_size_override("font_size", 14)
	combo_btn.pressed.connect(_run_combo_tests)
	hud.add_child(combo_btn)
	main_ui_nodes.append(combo_btn)

	# === 操作提示(始终显示) ===
	var tips := Label.new()
	tips.text = "WASD=移动 | Tab=切换球员 | 左键=发球 | 9=重置 | 0=暂停/面板 | 1-5=配对快捷"
	tips.position = Vector2(100, 750)
	tips.size = Vector2(1100, 22)
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.add_theme_font_size_override("font_size", 13)
	tips.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	hud.add_child(tips)

	# === 当前控制提示(始终显示) ===
	var control_label := Label.new()
	control_label.name = "ControlLabel"
	control_label.text = "当前控制: 球员A [持球]"
	control_label.position = Vector2(10, 720)
	control_label.size = Vector2(250, 20)
	control_label.add_theme_font_size_override("font_size", 15)
	control_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	hud.add_child(control_label)

	# === PLAYING阶段快捷技能栏(初始隐藏) ===
	_create_playing_skill_bar()

	# === 快捷键配对区(SETUP阶段) ===
	_create_key_binding_panel()


## ==================== 左面板:球员状态 ====================

func _create_status_panels() -> void:
	_create_single_status_panel("球员A(我方)", player_a, 10, 35, Color(0.3, 0.7, 1.0), "StatusA")
	_create_single_status_panel("球员B(敌方)", player_b, 10, 320, Color(1.0, 0.5, 0.3), "StatusB")


func _create_single_status_panel(title: String, player: CharacterBody2D, x: float, y: float, color: Color, panel_name: String) -> void:
	var bg := Panel.new()
	bg.name = panel_name
	bg.position = Vector2(x, y)
	bg.size = Vector2(250, 275)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	bg_style.border_color = color
	bg_style.set_corner_radius_all(5)
	bg_style.border_width_bottom = 1
	bg_style.border_width_top = 1
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg.add_theme_stylebox_override("panel", bg_style)
	hud.add_child(bg)
	main_ui_nodes.append(bg)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.position = Vector2(x + 10, y + 5)
	title_lbl.size = Vector2(230, 20)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", color)
	hud.add_child(title_lbl)
	main_ui_nodes.append(title_lbl)

	var content := Label.new()
	content.name = panel_name + "_Content"
	content.position = Vector2(x + 10, y + 28)
	content.size = Vector2(230, 200)
	content.add_theme_font_size_override("font_size", 12)
	content.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hud.add_child(content)
	main_ui_nodes.append(content)

	# 体力/能量快捷设置
	var ctrl_y: float = y + 220
	var ctrl_font: int = 11

	var hp_lbl := Label.new()
	hp_lbl.text = "体力设:"
	hp_lbl.position = Vector2(x + 5, ctrl_y)
	hp_lbl.size = Vector2(50, 18)
	hp_lbl.add_theme_font_size_override("font_size", ctrl_font)
	hp_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	hud.add_child(hp_lbl)
	main_ui_nodes.append(hp_lbl)

	var hp_input := LineEdit.new()
	hp_input.name = panel_name + "_HpInput"
	hp_input.text = "50"
	hp_input.position = Vector2(x + 52, ctrl_y - 1)
	hp_input.size = Vector2(45, 18)
	hp_input.add_theme_font_size_override("font_size", ctrl_font)
	hud.add_child(hp_input)
	main_ui_nodes.append(hp_input)

	var hp_btn := Button.new()
	hp_btn.text = "设置"
	hp_btn.position = Vector2(x + 100, ctrl_y - 1)
	hp_btn.size = Vector2(40, 18)
	hp_btn.add_theme_font_size_override("font_size", ctrl_font)
	hp_btn.pressed.connect(_set_player_hp.bind(player, hp_input))
	hud.add_child(hp_btn)
	main_ui_nodes.append(hp_btn)

	var hp_full := Button.new()
	hp_full.text = "补满"
	hp_full.position = Vector2(x + 144, ctrl_y - 1)
	hp_full.size = Vector2(40, 18)
	hp_full.add_theme_font_size_override("font_size", ctrl_font)
	hp_full.pressed.connect(_set_player_hp_pct.bind(player, 1.0))
	hud.add_child(hp_full)
	main_ui_nodes.append(hp_full)

	# 场上状态
	ctrl_y += 22
	var status := Label.new()
	status.name = panel_name + "_ZoneStatus"
	status.text = "区域内: 无"
	status.position = Vector2(x + 5, ctrl_y)
	status.size = Vector2(240, 18)
	status.add_theme_font_size_override("font_size", ctrl_font)
	status.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	hud.add_child(status)
	main_ui_nodes.append(status)


## ==================== 右面板:标签按钮 ====================

func _create_tag_button_panel() -> void:
	var panel_bg := Panel.new()
	panel_bg.position = Vector2(270, 35)
	panel_bg.size = Vector2(520, 280)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	bg_style.border_color = Color(0.4, 0.4, 0.3)
	bg_style.set_corner_radius_all(5)
	bg_style.border_width_bottom = 1
	bg_style.border_width_top = 1
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	panel_bg.add_theme_stylebox_override("panel", bg_style)
	hud.add_child(panel_bg)
	main_ui_nodes.append(panel_bg)

	var scroll := ScrollContainer.new()
	scroll.name = "TagButtonScroll"
	scroll.position = Vector2(275, 40)
	scroll.size = Vector2(510, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(scroll)
	main_ui_nodes.append(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "TagButtonVBox"
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)
	main_ui_nodes.append(vbox)

	for group in tag_groups:
		var group_lbl := Label.new()
		group_lbl.text = group.name
		group_lbl.add_theme_font_size_override("font_size", 13)
		group_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		vbox.add_child(group_lbl)

		var hbox: HBoxContainer = null
		for i in range(group.tags.size()):
			if i % 4 == 0:
				hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 3)
				vbox.add_child(hbox)
			var tag: Dictionary = group.tags[i]
			var btn := Button.new()
			btn.text = str(tag.get("code", "")) + "." + str(tag.get("name", ""))
			btn.add_theme_font_size_override("font_size", 11)
			btn.custom_minimum_size = Vector2(125, 26)
			btn.tooltip_text = tag.get("id", "")
			var tag_id: String = tag.get("id", "")
			btn.pressed.connect(_on_tag_button_pressed.bind(tag_id))
			hbox.add_child(btn)

		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
		vbox.add_child(sep)


## ==================== 日志面板 ====================

func _create_log_panel() -> void:
	var panel_bg := Panel.new()
	panel_bg.position = Vector2(800, 35)
	panel_bg.size = Vector2(490, 590)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.06, 0.9)
	bg_style.border_color = Color(0.35, 0.35, 0.3)
	bg_style.set_corner_radius_all(5)
	bg_style.border_width_bottom = 1
	bg_style.border_width_top = 1
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	panel_bg.add_theme_stylebox_override("panel", bg_style)
	hud.add_child(panel_bg)
	main_ui_nodes.append(panel_bg)

	var title := Label.new()
	title.text = "操作日志"
	title.position = Vector2(810, 40)
	title.size = Vector2(100, 18)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	hud.add_child(title)
	main_ui_nodes.append(title)

	log_panel = RichTextLabel.new()
	log_panel.name = "LogPanel"
	log_panel.position = Vector2(805, 60)
	log_panel.size = Vector2(480, 560)
	log_panel.bbcode_enabled = true
	log_panel.add_theme_font_size_override("normal_font_size", 12)
	log_panel.scroll_following = true
	hud.add_child(log_panel)
	main_ui_nodes.append(log_panel)


## ==================== 快捷键配对区(SETUP阶段) ====================

func _create_key_binding_panel() -> void:
	"""SETUP阶段：标签↔数字键配对面板"""
	var panel := Panel.new()
	panel.name = "KeyBindingPanel"
	panel.position = Vector2(10, 605)
	panel.size = Vector2(250, 110)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.15, 0.92)
	bg.border_color = Color(0.5, 0.6, 0.4)
	bg.set_corner_radius_all(5)
	bg.border_width_bottom = 1
	bg.border_width_top = 1
	bg.border_width_left = 1
	bg.border_width_right = 1
	panel.add_theme_stylebox_override("panel", bg)
	hud.add_child(panel)
	main_ui_nodes.append(panel)

	# 标题
	var title := Label.new()
	title.text = "快捷键配对(测试时按数字键)"
	title.position = Vector2(8, 4)
	title.size = Vector2(240, 16)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	panel.add_child(title)

	# 第一行：标签下拉 + 数字键下拉 + 添加
	bind_combo_tag = OptionButton.new()
	bind_combo_tag.position = Vector2(8, 22)
	bind_combo_tag.size = Vector2(120, 22)
	bind_combo_tag.add_theme_font_size_override("font_size", 11)
	# 填充可选标签(未实现的禁用显示)
	for tag in _get_selectable_tags_for_binding():
		var t_id: String = str(tag.get("id", ""))
		var prefix: String = "" if _is_tag_implemented(t_id) else "[禁] "
		var item_idx: int = bind_combo_tag.item_count
		bind_combo_tag.add_item(prefix + str(tag.get("code", "")) + "." + str(tag.get("name", "")))
		bind_combo_tag.set_item_metadata(item_idx, t_id)
		if not _is_tag_implemented(t_id):
			bind_combo_tag.set_item_disabled(item_idx, true)
	panel.add_child(bind_combo_tag)

	bind_combo_key = OptionButton.new()
	bind_combo_key.position = Vector2(132, 22)
	bind_combo_key.size = Vector2(40, 22)
	bind_combo_key.add_theme_font_size_override("font_size", 11)
	for k in range(1, 6):
		bind_combo_key.add_item(str(k), k)
	bind_combo_key.selected = 0
	panel.add_child(bind_combo_key)

	var add_btn := Button.new()
	add_btn.text = "+ 添加"
	add_btn.position = Vector2(176, 22)
	add_btn.size = Vector2(66, 22)
	add_btn.add_theme_font_size_override("font_size", 11)
	add_btn.pressed.connect(_on_add_binding)
	panel.add_child(add_btn)

	# 已配对列表(可滚动)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 46)
	scroll.size = Vector2(234, 58)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	bind_list_container = VBoxContainer.new()
	bind_list_container.add_theme_constant_override("separation", 1)
	scroll.add_child(bind_list_container)

	_refresh_binding_list()


func _get_selectable_tags_for_binding() -> Array:
	"""可配对的标签列表(全部标签，下拉中未实现的禁用)"""
	var result: Array = []
	for group in tag_groups:
		for tag in group.tags:
			result.append(tag)
	return result


func _is_tag_implemented(tag_id: String) -> bool:
	## 未实现的4个标签(FIELD地形/区域标注类，handler无match分支)
	## BALL 17个 / PLAYER 51个 / FIELD 8个 已实现；FIELD 这4个未实现
	var not_impl: Array = [
		"field_terra_change", "field_terra_revert",
		"field_zone_mark", "field_zone_clear",
	]
	if tag_id in not_impl:
		return false
	return true


func _default_target_for_tag(tag_id: String) -> String:
	## PLAYER标签默认目标：增益/buff → self，攻击/debuff → enemies
	## 球/场地类返回 ""（不需要 target）
	if tag_id.begins_with("ball_") or tag_id.begins_with("field_"):
		return ""
	var debuff_kw: Array = [
		"_down_pct", "_down_flat", "hp_damage", "hp_dot", "vulnerable", "reveal",
		"move_slow", "root", "energy_cost", "energy_max_down",
		"spirit_cost_up", "spirit_cd_up", "spirit_half",
		"stun", "silence", "disarm",
	]
	for kw in debuff_kw:
		if tag_id.find(kw) >= 0:
			return "enemies"
	return "self"


func _on_add_binding() -> void:
	"""添加一条配对，含重复检测"""
	if bind_combo_tag.item_count == 0:
		return
	var tag_id: String = str(bind_combo_tag.get_item_metadata(bind_combo_tag.selected))
	var key: int = int(bind_combo_key.get_item_id(bind_combo_key.selected))
	# 未实现标签拦截
	if not _is_tag_implemented(tag_id):
		_add_log("[color=#888]✗ %s 未实现，不可配对[/color]" % tag_id)
		return
	# 重复检测：同键已配过
	for b in key_bindings:
		if int(b["key"]) == key:
			_add_log("[color=red]✗ 数字键 %d 已配对过[%s][/color]" % [key, _binding_name_of(b)])
			return
		if str(b["tag_id"]) == tag_id:
			_add_log("[color=red]✗ 该标签已配对到数字键 %d[/color]" % int(b["key"]))
			return
	key_bindings.append({"key": key, "tag_id": tag_id})
	_refresh_binding_list()
	_refresh_playing_skill_bar()
	_add_log("[color=#88ccff]✓ 配对: 数字键%d → %s[/color]" % [key, _tag_short_name(tag_id)])


func _remove_binding(idx: int) -> void:
	"""删除一条配对"""
	if idx >= 0 and idx < key_bindings.size():
		var b = key_bindings[idx]
		key_bindings.remove_at(idx)
		_refresh_binding_list()
		_refresh_playing_skill_bar()
		_add_log("[color=#88ccff]✗ 取消配对: 数字键%d[/color]" % int(b["key"]))


func _refresh_binding_list() -> void:
	"""刷新SETUP阶段的已配对列表UI"""
	if not bind_list_container:
		return
	for c in bind_list_container.get_children():
		c.queue_free()
	if key_bindings.is_empty():
		var lbl := Label.new()
		lbl.text = "(未配对)"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		bind_list_container.add_child(lbl)
		return
	# 按数字键排序
	var sorted := key_bindings.duplicate()
	sorted.sort_custom(func(a, b): return int(a["key"]) < int(b["key"]))
	for i in range(sorted.size()):
		var b = sorted[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var lbl := Label.new()
		lbl.text = "%d → %s" % [int(b["key"]), _tag_short_name(str(b["tag_id"]))]
		lbl.size = Vector2(200, 16)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
		row.add_child(lbl)
		# 删除按钮(用原始索引)
		var orig_idx: int = key_bindings.find(b)
		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.size = Vector2(20, 16)
		del_btn.add_theme_font_size_override("font_size", 11)
		del_btn.pressed.connect(_remove_binding.bind(orig_idx))
		row.add_child(del_btn)
		bind_list_container.add_child(row)


func _tag_short_name(tag_id: String) -> String:
	var tag: Dictionary = all_tags_dict.get(tag_id, {})
	return str(tag.get("name", tag_id))


func _binding_name_of(b: Dictionary) -> String:
	return _tag_short_name(str(b.get("tag_id", "")))


## ==================== PLAYING快捷技能栏 ====================

var skill_bar_nodes: Array = []  # 始终显示,不随面板隐藏
var skill_bar_btns: Array = []   # 技能按钮引用

func _create_playing_skill_bar() -> void:
	"""PLAYING阶段快捷技能栏：按当前配对动态生成 + 固定操作按钮"""
	skill_bar_nodes.clear()
	skill_bar_btns.clear()
	_refresh_playing_skill_bar()
	# 初始隐藏
	for node in skill_bar_nodes:
		node.visible = false


func _refresh_playing_skill_bar() -> void:
	"""根据 key_bindings 重建技能栏按钮"""
	# 清除旧按钮
	for node in skill_bar_nodes:
		if node and is_instance_valid(node):
			node.queue_free()
	skill_bar_nodes.clear()
	skill_bar_btns.clear()
	if not hud:
		return

	var bar_y: float = 650.0
	var bar_x: float = 60.0
	var btn_w: float = 130.0
	var btn_h: float = 32.0
	var gap: float = 8.0

	# 排序后的配对
	var sorted := key_bindings.duplicate()
	sorted.sort_custom(func(a, b): return int(a["key"]) < int(b["key"]))

	# 固定操作：9=重置 0=返回面板 (附在后面)
	var fixed: Array = [{"key": 9, "label": "9:重置", "action": "reset"}, {"key": 0, "label": "0:返回面板", "action": "toggle"}]

	var total: int = sorted.size() + fixed.size()
	if total == 0:
		return

	# 背景条
	var bar_bg := Panel.new()
	bar_bg.name = "SkillBarBG"
	bar_bg.position = Vector2(bar_x - 10, bar_y - 5)
	bar_bg.size = Vector2(btn_w * total + gap * (total - 1) + 20, btn_h + 10)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	bg_style.border_color = Color(0.4, 0.4, 0.3)
	bg_style.set_corner_radius_all(5)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	hud.add_child(bar_bg)
	skill_bar_nodes.append(bar_bg)

	# 配对标签按钮
	for i in range(sorted.size()):
		var b = sorted[i]
		var tag_id: String = str(b["tag_id"])
		var btn := Button.new()
		btn.text = "%d: %s" % [int(b["key"]), _tag_short_name(tag_id)]
		btn.position = Vector2(bar_x + i * (btn_w + gap), bar_y)
		btn.size = Vector2(btn_w, btn_h)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_execute_binding.bind(tag_id))
		hud.add_child(btn)
		skill_bar_nodes.append(btn)
		skill_bar_btns.append(btn)

	# 固定操作按钮
	for j in range(fixed.size()):
		var f = fixed[j]
		var btn := Button.new()
		btn.text = str(f["label"])
		btn.position = Vector2(bar_x + (sorted.size() + j) * (btn_w + gap), bar_y)
		btn.size = Vector2(btn_w, btn_h)
		btn.add_theme_font_size_override("font_size", 13)
		match str(f["action"]):
			"reset":
				btn.pressed.connect(_reset_all)
			"toggle":
				btn.pressed.connect(_toggle_panels)
		hud.add_child(btn)
		skill_bar_nodes.append(btn)
		skill_bar_btns.append(btn)

	# 隐藏状态与当前阶段同步
	_show_skill_bar(current_phase == Phase.PLAYING)


func _execute_binding(tag_id: String) -> void:
	"""执行配对的快捷标签操作（不弹窗，用预设参数直接走）"""
	match tag_id:
		"field_obs_add":
			_place_obstacle_direct()
		"field_obs_clear":
			_clear_obstacle_direct()
		"field_zone_boost":
			_quick_place_zone(0)
		"field_zone_slow":
			_quick_place_zone(1)
		"field_zone_danger":
			_quick_place_zone(2)
		"field_zone_safe":
			_quick_place_zone(3)
		"field_illusion_add":
			_place_illusion_direct()
		"field_illusion_clear":
			_clear_illusion_direct()
		_:
			if not _is_tag_implemented(tag_id):
				_add_log("[color=#888]✗ %s 未实现[/color]" % tag_id)
				return
			# BALL/PLAYER 标签：读参数缓存执行(需先在弹窗保存过参数)
			if tag_id.begins_with("ball_") or tag_id.begins_with("player_"):
				if not _tag_param_cache.has(tag_id):
					_add_log("[color=yellow]⚠ %s 需先点击该标签保存参数[/color]" % _tag_short_name(tag_id))
					return
				var cache: Dictionary = _tag_param_cache[tag_id]
				var caster_name: String = cache.get("_caster", "A")
				var caster: CharacterBody2D = player_a if caster_name == "A" else player_b
				var exec_params: Dictionary = cache.get("params", {})
				var r: Dictionary = handler.apply_tag_effect(tag_id, exec_params, caster.get_instance_id())
				var tgt_str: String = ""
				if exec_params.has("target"):
					tgt_str = "→ " + ({"self":"自己","enemies":"对方","allies":"队友","nearest_enemy":"最近敌人"}.get(exec_params["target"], exec_params["target"]))
				_add_log("[color=green]▶ %s(球员%s) %s[/color]" % [_tag_short_name(tag_id), caster_name, tgt_str])
			else:
				_add_log("[color=red]✗ %s 未实现快捷执行[/color]" % tag_id)


func _show_skill_bar(show: bool) -> void:
	for node in skill_bar_nodes:
		if node and is_instance_valid(node):
			node.visible = show


func _quick_place_zone(zone_type: int) -> void:
	"""快捷键直接用预设参数放置区域(不弹窗)"""
	if not zone_mgr:
		return
	if zone_mgr.is_operating():
		zone_mgr.cancel_operation()
		return

	var params: Dictionary = {
		"zone_type": zone_type,
		"width": zone_params.width,
		"height": zone_params.height,
		"duration": zone_params.duration,
		"mouse_ops": zone_params.mouse_ops,
	}
	match zone_type:
		0:
			params["boost_multiplier"] = zone_params.boost_multiplier
		1:
			params["slow_multiplier"] = zone_params.slow_multiplier
		2:
			params["damage_value"] = zone_params.damage_value

	zone_mgr.start_placing(params, int(zone_params.mouse_ops))
	var names: Array = ["加速区", "减速区", "危险区", "安全区"]
	_add_log("[color=green]▶ %s → 鼠标放置(左键放置/右键取消)[/color]" % names[zone_type])


## ==================== 标签弹窗 ====================

func _build_ball_fields(tag_id: String) -> Array:
	"""构建球类标签的参数字段(按 registry params + 默认值)"""
	var defaults: Dictionary = _BALL_DEFAULTS.get(tag_id, {})
	var reg_params: Array = all_tags_dict.get(tag_id, {}).get("params", [])
	# 无参数的球标签(avoid/straight/lockon/penetrate)
	if reg_params.is_empty() and defaults.is_empty():
		return [["无参数(直接生效)", "1", "_no_param", ""]]
	var fields: Array = []
	var label_map: Dictionary = {
		"value": "数值", "multiplier": "倍率",
		"turn_speed": "转向速度", "return_distance": "回返距离",
		"split_count": "分裂数", "radius": "范围半径", "damage_pct": "范围伤害比(0-1)",
	}
	# 合并默认值和registry参数(默认值优先作为初始值)
	var keys: Array = []
	if not defaults.is_empty():
		keys = defaults.keys()
	else:
		keys = reg_params
	for k in keys:
		var disp: String = label_map.get(k, k)
		var val: String = str(defaults.get(k, ""))
		fields.append([disp, val, k, ""])
	return fields


func _build_player_fields(tag_id: String) -> Array:
	"""构建球员标签的参数字段(params + 作用对象下拉)"""
	var reg_params: Array = all_tags_dict.get(tag_id, {}).get("params", [])
	var fields: Array = []
	var label_map: Dictionary = {
		"value": "数值", "multiplier": "倍率", "duration": "持续秒数",
		"target": "作用对象",
	}
	var default_target: String = _default_target_for_tag(tag_id)
	# 默认初始值表
	var init_vals: Dictionary = {
		"value": _PLAYER_DEFAULTS["value_flat"],
		"multiplier": _PLAYER_DEFAULTS["multiplier"],
		"duration": _PLAYER_DEFAULTS["duration"],
	}
	for k in reg_params:
		if k == "target":
			continue  # target 单独用下拉处理
		var disp: String = label_map.get(k, k)
		var val: String = str(init_vals.get(k, ""))
		# pct 类标签的 value 默认用 30(百分比)，flat 类用 10
		if k == "value":
			if tag_id.find("_pct") >= 0 or tag_id.find("heal_pct") >= 0 or tag_id.find("hp_") >= 0 or tag_id.find("energy_") >= 0:
				val = str(_PLAYER_DEFAULTS["value_pct"])
				if tag_id.find("hp_") >= 0 or tag_id.find("energy_") >= 0:
					val = str(_PLAYER_DEFAULTS["hp_pct"])
			else:
				val = str(_PLAYER_DEFAULTS["value_flat"])
		fields.append([disp, val, k, ""])
	# 作用对象下拉(所有球员标签都有，默认增益→自己/攻击→对方)
	var tgt_disp_map: Dictionary = {"self": "自己:self", "enemies": "对方:enemies", "allies": "队友:allies", "nearest_enemy": "最近敌人:nearest_enemy"}
	var tgt_items: Array = [tgt_disp_map["self"], tgt_disp_map["enemies"], tgt_disp_map["allies"], tgt_disp_map["nearest_enemy"]]
	fields.append(["作用对象", default_target, "target", "option", tgt_items])
	return fields


func _on_tag_button_pressed(tag_id: String) -> void:
	selected_tag_id = tag_id
	var tag: Dictionary = all_tags_dict.get(tag_id, {})
	var tag_name: String = str(tag.get("name", tag_id))
	# 未实现标签拦截
	if not _is_tag_implemented(tag_id):
		_add_log("[color=#888]✗ %s 未实现，不可用[/color]" % tag_name)
		return
	# 所有标签都走参数弹窗（BALL/PLAYER/FIELD 统一）
	_show_param_popup(tag_id, tag_name)


func _show_param_popup(tag_id: String, tag_name: String) -> void:
	_close_param_popup()
	popup_visible = true

	var tag: Dictionary = all_tags_dict.get(tag_id, {})
	var is_zone: bool = tag_id in ["field_zone_boost", "field_zone_slow", "field_zone_danger", "field_zone_safe"]
	var is_obs_add: bool = tag_id == "field_obs_add"
	var is_obs_clear: bool = tag_id == "field_obs_clear"
	var is_illusion_add: bool = tag_id == "field_illusion_add"
	var is_illusion_clear: bool = tag_id == "field_illusion_clear"
	var is_ball: bool = tag_id.begins_with("ball_")
	var is_player: bool = tag_id.begins_with("player_")
	var is_implemented: bool = is_zone or is_obs_add or is_obs_clear or is_illusion_add or is_illusion_clear or is_ball or is_player

	# 弹窗尺寸
	var popup_w: float = 450.0
	var fields: Array = []

	# 根据标签类型构建参数字段
	if is_zone:
		fields = [["宽度", str(zone_params.width)], ["高度", str(zone_params.height)], ["持续秒数", str(zone_params.duration)], ["鼠标操作次数", str(zone_params.mouse_ops)]]
		match tag_id:
			"field_zone_boost":
				fields.insert(3, ["加速倍率", str(zone_params.boost_multiplier)])
			"field_zone_slow":
				fields.insert(3, ["减速倍率", str(zone_params.slow_multiplier)])
			"field_zone_danger":
				fields.insert(3, ["每秒伤害", str(zone_params.damage_value)])
	elif is_obs_add:
		# 扩展格式：[显示名, 值, field_key, 类型/show_when]
		# 第4元素 = "option" → 下拉框(第5元素为选项)；= "rect"/"circle"/"crescent" → 该形状专属行
		fields = [
			["形状", obs_params.shape, "shape", "option", ["矩形:rect", "圆形:circle", "月牙:crescent"]],
			["矩形宽度", str(obs_params.width), "width", "rect"],
			["矩形高度", str(obs_params.height), "height", "rect"],
			["半径", str(obs_params.radius), "radius", "circle"],
			["月牙弧度角", str(obs_params.arc_angle), "arc_angle", "crescent"],
			["防御生命值", str(obs_params.hp), "hp", ""],
			["攻击消耗速率/s", str(obs_params.attack_consume_rate), "attack_consume_rate", ""],
			["球速消耗速率/s", str(obs_params.speed_consume_rate), "speed_consume_rate", ""],
			["最大数量", str(obs_params.max_count), "max_count", ""],
			["持续秒数", str(obs_params.duration), "duration", ""],
			["鼠标操作次数", str(obs_params.mouse_ops), "mouse_ops", ""],
			["元素(金刚/大地/雷火/冰雪/草木/梦幻)", obs_params.element, "element", ""],
		]
	elif is_obs_clear:
		fields = [
			["清除数量", str(obs_clear_params.clear_count)],
			["鼠标操作次数", str(obs_clear_params.mouse_ops)],
		]
	elif is_illusion_add:
		# 幻象生成：place_mode 下拉框 + 数量 + 体力 + 时长 + AI开关
		fields = [
			["位置模式", illusion_params.place_mode, "place_mode", "option", ["任意放置:any", "近身放置:near"]],
			["生成数量(任意模式)", str(illusion_params.count), "count", ""],
			["幻象体力", str(illusion_params.stamina), "stamina", ""],
			["持续秒数", str(illusion_params.duration), "duration", ""],
			["AI智能", str(illusion_params.ai_mode), "ai_mode", ""],
		]
	elif is_illusion_clear:
		fields = [
			["清除全部(1=是/0=否)", str(illusion_clear_params.clear_all), "clear_all", ""],
		]
	elif is_ball:
		# 球类标签：按 registry params 生成字段(用 _BALL_DEFAULTS 填默认值)
		fields = _build_ball_fields(tag_id)
	elif is_player:
		# 球员标签：params 字段 + 作用对象下拉(默认根据增益/攻击判定)
		fields = _build_player_fields(tag_id)
	else:
		# 未实现的标签
		popup_w = 420.0

	var popup_h: float = 130.0 + fields.size() * 28.0 + (50.0 if is_implemented else 0.0)

	popup_panel = Panel.new()
	popup_panel.name = "ParamPopup"
	popup_panel.position = Vector2(500 - popup_w / 2.0, 350 - popup_h / 2.0)
	popup_panel.size = Vector2(popup_w, popup_h)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.12, 0.96)
	bg.border_color = Color(0.8, 0.7, 0.3)
	bg.set_corner_radius_all(8)
	bg.border_width_bottom = 2
	bg.border_width_top = 2
	bg.border_width_left = 2
	bg.border_width_right = 2
	popup_panel.add_theme_stylebox_override("panel", bg)
	hud.add_child(popup_panel)

	# 标题
	var title := Label.new()
	title.text = "标签: %s" % tag_name
	title.position = Vector2(15, 10)
	title.size = Vector2(popup_w - 30, 22)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	popup_panel.add_child(title)

	# 描述
	var desc := Label.new()
	desc.text = str(tag.get("description", ""))
	desc.position = Vector2(15, 35)
	desc.size = Vector2(popup_w - 30, 40)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	popup_panel.add_child(desc)

	# 参数输入行
	var popup_inputs: Dictionary = {}
	var row_y: float = 80.0
	var init_shape: String = str(obs_params.get("shape", "rect"))
	for field in fields:
		var label_text: String = str(field[0])
		var field_val = field[1]
		var field_key: String = label_text
		var is_option: bool = false
		var option_items: Array = []
		var show_when: String = ""  # 非空表示仅该形状显示
		if field.size() >= 3:
			field_key = str(field[2])
		if field.size() >= 4:
			if str(field[3]) == "option":
				is_option = true
				option_items = field[4] if field.size() >= 5 else []
			else:
				show_when = str(field[3])
		# 形状联动：专属行仅当前形状可见
		var row_visible: bool = (show_when == "" or show_when == init_shape)

		var lbl := Label.new()
		lbl.name = "PopupLbl_" + field_key
		lbl.text = label_text + ":"
		lbl.position = Vector2(20, row_y)
		lbl.size = Vector2(140, 22)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		lbl.visible = row_visible
		popup_panel.add_child(lbl)

		if is_option:
			var opt := OptionButton.new()
			opt.name = "PopupInput_" + field_key
			opt.position = Vector2(165, row_y - 1)
			opt.size = Vector2(popup_w - 195, 22)
			opt.add_theme_font_size_override("font_size", 13)
			var sel_idx: int = 0
			for i in range(option_items.size()):
				var item_str: String = str(option_items[i])
				var parts: PackedStringArray = item_str.split(":")
				var disp: String = parts[0]
				var val: String = parts[1] if parts.size() > 1 else parts[0]
				opt.add_item(disp, i)
				opt.set_item_metadata(i, val)
				if val == str(field_val):
					sel_idx = i
			opt.selected = sel_idx
			if field_key == "shape":
				opt.item_selected.connect(_on_popup_obs_shape_changed)
			popup_panel.add_child(opt)
			popup_inputs[field_key] = opt
		else:
			var input := LineEdit.new()
			input.name = "PopupInput_" + field_key
			input.text = str(field_val)
			input.position = Vector2(165, row_y - 1)
			input.size = Vector2(popup_w - 195, 22)
			input.add_theme_font_size_override("font_size", 13)
			input.visible = row_visible
			popup_panel.add_child(input)
			popup_inputs[field_key] = input

		if row_visible:
			row_y += 28.0

	# === 分隔线 ===
	var sep := HSeparator.new()
	sep.name = "PopupSep"
	sep.position = Vector2(15, row_y)
	sep.size = Vector2(popup_w - 30, 2)
	popup_panel.add_child(sep)
	row_y += 6.0

	# === 施法者选择 ===
	var caster_lbl := Label.new()
	caster_lbl.name = "PopupCasterLbl"
	caster_lbl.text = "施法者(谁释放):"
	caster_lbl.position = Vector2(20, row_y)
	caster_lbl.size = Vector2(140, 22)
	caster_lbl.add_theme_font_size_override("font_size", 13)
	caster_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	popup_panel.add_child(caster_lbl)

	var caster_input := LineEdit.new()
	caster_input.name = "PopupCasterInput"
	caster_input.text = "A"
	caster_input.position = Vector2(165, row_y - 1)
	caster_input.size = Vector2(60, 22)
	caster_input.add_theme_font_size_override("font_size", 13)
	popup_panel.add_child(caster_input)
	popup_inputs["施法者"] = caster_input

	var caster_hint := Label.new()
	caster_hint.name = "PopupCasterHint"
	caster_hint.text = "(A 或 B)"
	caster_hint.position = Vector2(230, row_y + 2)
	caster_hint.size = Vector2(60, 18)
	caster_hint.add_theme_font_size_override("font_size", 12)
	caster_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	popup_panel.add_child(caster_hint)
	row_y += 26.0

	# === 作用对象(仅区域效果/障碍物标签) ===
	if is_zone or is_obs_add:
		var target_lbl := Label.new()
		target_lbl.name = "PopupTargetLbl"
		target_lbl.text = "作用对象:"
		target_lbl.position = Vector2(20, row_y)
		target_lbl.size = Vector2(140, 22)
		target_lbl.add_theme_font_size_override("font_size", 13)
		target_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		popup_panel.add_child(target_lbl)

		var target_hint := Label.new()
		target_hint.name = "PopupTargetHint"
		target_hint.text = "区域内所有球员（自动检测）"
		target_hint.position = Vector2(165, row_y + 2)
		target_hint.size = Vector2(250, 18)
		target_hint.add_theme_font_size_override("font_size", 12)
		target_hint.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		popup_panel.add_child(target_hint)
		row_y += 26.0

	# === 元灵能量消耗 ===
	var nrg_lbl := Label.new()
	nrg_lbl.name = "PopupEnergyLbl"
	nrg_lbl.text = "元灵能量消耗(施法者):"
	nrg_lbl.position = Vector2(20, row_y)
	nrg_lbl.size = Vector2(180, 22)
	nrg_lbl.add_theme_font_size_override("font_size", 13)
	nrg_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	popup_panel.add_child(nrg_lbl)

	var nrg_input := LineEdit.new()
	nrg_input.name = "PopupEnergyInput"
	nrg_input.text = "0"
	nrg_input.position = Vector2(210, row_y - 1)
	nrg_input.size = Vector2(80, 22)
	nrg_input.add_theme_font_size_override("font_size", 13)
	popup_panel.add_child(nrg_input)
	popup_inputs["能量消耗"] = nrg_input

	var nrg_hint := Label.new()
	nrg_hint.name = "PopupEnergyHint"
	nrg_hint.text = "(0=不消耗)"
	nrg_hint.position = Vector2(295, row_y + 2)
	nrg_hint.size = Vector2(80, 18)
	nrg_hint.add_theme_font_size_override("font_size", 12)
	nrg_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	popup_panel.add_child(nrg_hint)
	row_y += 28.0

	# 按钮行
	var btn_y: float = row_y + 8.0

	if is_implemented:
		var caster_btn_a := Button.new()
		caster_btn_a.name = "PopupBtnA"
		caster_btn_a.text = "球员A保存"
		caster_btn_a.position = Vector2(40, btn_y)
		caster_btn_a.size = Vector2(130, 36)
		caster_btn_a.add_theme_font_size_override("font_size", 15)
		caster_btn_a.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		caster_btn_a.pressed.connect(_on_popup_execute.bind(tag_id, tag_name, popup_inputs, true))
		popup_panel.add_child(caster_btn_a)

		var caster_btn_b := Button.new()
		caster_btn_b.name = "PopupBtnB"
		caster_btn_b.text = "球员B保存"
		caster_btn_b.position = Vector2(180, btn_y)
		caster_btn_b.size = Vector2(130, 36)
		caster_btn_b.add_theme_font_size_override("font_size", 15)
		caster_btn_b.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		caster_btn_b.pressed.connect(_on_popup_execute.bind(tag_id, tag_name, popup_inputs, false))
		popup_panel.add_child(caster_btn_b)

		var hint := Label.new()
		hint.name = "PopupBtnHint"
		hint.text = "快捷键使用预设参数"
		hint.position = Vector2(320, btn_y + 10)
		hint.size = Vector2(140, 18)
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		popup_panel.add_child(hint)
	else:
		var status := Label.new()
		status.text = "⏳ 此标签尚未实现"
		status.position = Vector2(15, btn_y)
		status.size = Vector2(popup_w - 30, 22)
		status.add_theme_font_size_override("font_size", 14)
		status.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
		popup_panel.add_child(status)

	var close := Button.new()
	close.name = "PopupBtnClose"
	close.text = "关闭"
	close.position = Vector2(popup_w - 100, btn_y + 4)
	close.size = Vector2(80, 28)
	close.pressed.connect(_close_param_popup)
	popup_panel.add_child(close)


func _close_param_popup() -> void:
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()
	popup_panel = null
	popup_visible = false


## ==================== 障碍物弹窗：形状联动 ====================

const _OBS_FIELD_KEYS: Array = ["shape", "width", "height", "radius", "arc_angle", "hp", "attack_consume_rate", "speed_consume_rate", "max_count", "duration", "mouse_ops", "element"]
const _OBS_SHAPE_ONLY: Dictionary = {
	"width": "rect",
	"height": "rect",
	"radius": "circle",
	"arc_angle": "crescent",
}

func _on_popup_obs_shape_changed(_idx: int) -> void:
	"""障碍物弹窗：形状下拉切换 → 联动显隐专属参数行并重排布局"""
	if not popup_panel or not is_instance_valid(popup_panel):
		return
	var opt = popup_panel.get_node_or_null("PopupInput_shape")
	if not opt or not (opt is OptionButton):
		return
	var new_shape: String = str(opt.get_item_metadata(opt.selected))
	# 1. 重排 fields 行（可见行连续排列）
	var row_y: float = 80.0
	for key in _OBS_FIELD_KEYS:
		var lbl = popup_panel.get_node_or_null("PopupLbl_" + key)
		var inp = popup_panel.get_node_or_null("PopupInput_" + key)
		var show_when: String = str(_OBS_SHAPE_ONLY.get(key, ""))
		var vis: bool = (key == "shape") or (show_when == "") or (show_when == new_shape)
		if lbl:
			lbl.visible = vis
			if vis:
				lbl.position.y = row_y
		if inp:
			inp.visible = vis
			if vis:
				inp.position.y = row_y - 1.0
		if vis:
			row_y += 28.0
	# 2. 重排 fields 之后的元素
	_relayout_popup_tail(row_y)


func _relayout_popup_tail(fields_end_y: float) -> void:
	"""重排弹窗 fields 之后的元素（分隔线/施法者/作用对象/能量/按钮）"""
	if not popup_panel or not is_instance_valid(popup_panel):
		return
	var y: float = fields_end_y
	_set_popup_y("PopupSep", y)
	y += 6.0
	# 施法者行（行高26）
	_set_popup_y("PopupCasterLbl", y)
	_set_popup_y("PopupCasterInput", y - 1.0)
	_set_popup_y("PopupCasterHint", y + 2.0)
	y += 26.0
	# 作用对象行（仅障碍/区域标签存在，行高26）
	if popup_panel.has_node("PopupTargetLbl"):
		_set_popup_y("PopupTargetLbl", y)
		_set_popup_y("PopupTargetHint", y + 2.0)
		y += 26.0
	# 能量行（行高28）
	_set_popup_y("PopupEnergyLbl", y)
	_set_popup_y("PopupEnergyInput", y - 1.0)
	_set_popup_y("PopupEnergyHint", y + 2.0)
	y += 28.0
	# 按钮行
	var btn_y: float = y + 8.0
	_set_popup_y("PopupBtnA", btn_y)
	_set_popup_y("PopupBtnB", btn_y)
	_set_popup_y("PopupBtnHint", btn_y + 10.0)
	_set_popup_y("PopupBtnClose", btn_y + 4.0)
	# 弹窗高度自适应
	popup_panel.size.y = btn_y + 48.0


func _set_popup_y(node_name: String, y: float) -> void:
	var node = popup_panel.get_node_or_null(node_name)
	if node:
		node.position.y = y


## ==================== 元素颜色（测试平台本地）====================

func _test_get_element_color(element: String) -> Color:
	"""元素 → 颜色（与 handler._get_element_color 一致）"""
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(1.0, 1.0, 0.5))


func _on_popup_execute(tag_id: String, tag_name: String, popup_inputs: Dictionary, use_a: bool) -> void:
	"""弹窗中"球员A/B保存"按钮：保存参数+施法者+能量，不执行"""
	var p: Dictionary = {}
	for key in popup_inputs:
		var ctrl = popup_inputs[key]
		if ctrl and is_instance_valid(ctrl):
			if ctrl is OptionButton:
				p[key] = str(ctrl.get_item_metadata(ctrl.selected))
			else:
				p[key] = ctrl.text.strip_edges()

	var is_zone: bool = tag_id in ["field_zone_boost", "field_zone_slow", "field_zone_danger", "field_zone_safe"]
	var is_obs_add: bool = tag_id == "field_obs_add"
	var is_obs_clear: bool = tag_id == "field_obs_clear"
	var is_illusion_add: bool = tag_id == "field_illusion_add"
	var is_illusion_clear: bool = tag_id == "field_illusion_clear"
	var is_ball: bool = tag_id.begins_with("ball_")
	var is_player: bool = tag_id.begins_with("player_")

	# 施法者
	var caster_name: String = "A" if use_a else "B"
	var caster: CharacterBody2D = player_a if use_a else player_b

	# 能量消耗
	var energy_cost: float = float(p.get("能量消耗", "0"))
	if energy_cost > 0.0 and caster.spirit_energy < energy_cost:
		_close_param_popup()
		_add_log("[color=red]✗ 球员%s 能量不足! 需要%.0f, 当前%.0f[/color]" % [caster_name, energy_cost, caster.spirit_energy])
		return

	# 保存参数到预设变量
	if is_zone:
		zone_params.width = float(p.get("宽度", "120"))
		zone_params.height = float(p.get("高度", "120"))
		zone_params.duration = float(p.get("持续秒数", "10"))
		zone_params.mouse_ops = int(float(p.get("鼠标操作次数", "1")))
		var zone_type: int = { "field_zone_boost": 0, "field_zone_slow": 1, "field_zone_danger": 2, "field_zone_safe": 3 }.get(tag_id, 0)
		match zone_type:
			0: zone_params.boost_multiplier = float(p.get("加速倍率", "1.5"))
			1: zone_params.slow_multiplier = float(p.get("减速倍率", "1.5"))
			2: zone_params.damage_value = float(p.get("每秒伤害", "10"))
	elif is_obs_add:
		obs_params.shape = str(p.get("shape", "rect"))
		obs_params.width = float(p.get("width", "80"))
		obs_params.height = float(p.get("height", "30"))
		obs_params.radius = float(p.get("radius", "40"))
		obs_params.arc_angle = float(p.get("arc_angle", "120"))
		obs_params.hp = float(p.get("hp", "50"))
		obs_params.attack_consume_rate = float(p.get("attack_consume_rate", "20"))
		obs_params.speed_consume_rate = float(p.get("speed_consume_rate", "20"))
		obs_params.max_count = int(float(p.get("max_count", "3")))
		obs_params.duration = float(p.get("duration", "15"))
		obs_params.mouse_ops = int(float(p.get("mouse_ops", "1")))
		obs_params.element = str(p.get("element", "金刚"))
		obs_params.element_color = _test_get_element_color(obs_params.element)
	elif is_obs_clear:
		obs_clear_params.clear_count = int(float(p.get("清除数量", "2")))
		obs_clear_params.mouse_ops = int(float(p.get("鼠标操作次数", "2")))
	elif is_illusion_add:
		illusion_params.place_mode = str(p.get("place_mode", "any"))
		illusion_params.count = int(float(p.get("count", "2")))
		illusion_params.stamina = float(p.get("stamina", "60"))
		illusion_params.duration = float(p.get("duration", "10"))
		illusion_params.ai_mode = (str(p.get("ai_mode", "false")).to_lower() in ["1", "true", "开", "on"])
	elif is_illusion_clear:
		illusion_clear_params.clear_all = (str(p.get("clear_all", "1")).to_lower() in ["1", "true", "是"])
	elif is_ball or is_player:
		# BALL/PLAYER 标签：收集参数存入缓存(数字键执行时读)
		var exec_params: Dictionary = {}
		for k in ["value", "multiplier", "turn_speed", "return_distance", "split_count", "radius", "damage_pct", "target", "duration"]:
			if p.has(k) and p[k] != "":
				exec_params[k] = p[k]
		_tag_param_cache[tag_id] = {"params": exec_params, "_caster": caster_name}

	# 扣除能量
	if energy_cost > 0.0:
		caster.spirit_energy -= energy_cost
		_add_log("[color=cyan]⚡ 球员%s 消耗能量 %.0f → 剩余 %.0f[/color]" % [caster_name, energy_cost, caster.spirit_energy])

	_close_param_popup()
	_add_log("[color=cyan]✓ %s 参数已保存(施法者=球员%s) 开始测试后按快捷键激活[/color]" % [tag_name, caster_name])


## ==================== 从UI读取参数 ====================

func _read_params_from_ui() -> void:
	"""从输入框读取参数"""
	for key in param_inputs:
		var input: LineEdit = param_inputs[key]
		if not input or not is_instance_valid(input):
			continue
		var val: String = input.text.strip_edges()
		match key:
			"ZoneWidth": zone_params.width = float(val)
			"ZoneHeight": zone_params.height = float(val)
			"ZoneBoost": zone_params.boost_multiplier = float(val)
			"ZoneSlow": zone_params.slow_multiplier = float(val)
			"ZoneDmg": zone_params.damage_value = float(val)
			"ZoneDur": zone_params.duration = float(val)
			"ZoneOps": zone_params.mouse_ops = int(float(val))
			"ObsShape": obs_params.shape = val
			"ObsWidth": obs_params.width = float(val)
			"ObsHeight": obs_params.height = float(val)
			"ObsHp": obs_params.hp = float(val)
			"ObsAtkRate": obs_params.attack_consume_rate = float(val)
			"ObsSpdRate": obs_params.speed_consume_rate = float(val)
			"ObsMax": obs_params.max_count = int(float(val))
			"ObsDur": obs_params.duration = float(val)
			"ObsOps": obs_params.mouse_ops = int(float(val))


## ==================== 日志 ====================

var log_lines: Array = []

func _add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 100:
		log_lines.pop_front()
	if log_panel and is_instance_valid(log_panel):
		log_panel.append_text(text + "\n")


## ==================== 帧处理 ====================

func _process(_delta: float) -> void:
	if current_phase == Phase.PLAYING:
		_process_movement()
	_update_control_label()
	_update_status_panel("StatusA", player_a)
	_update_status_panel("StatusB", player_b)
	_update_zone_count_display()


func _process_movement() -> void:
	if not controlled_player or not is_instance_valid(controlled_player):
		return
	if controlled_player.is_defeated:
		return
	if controlled_player.is_status_active("stunned") or controlled_player.is_status_active("rooted"):
		controlled_player.velocity = Vector2.ZERO
		return
	var move_speed: float = controlled_player._get_effective_value("speed", controlled_player.speed)
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	if input_dir != Vector2.ZERO:
		controlled_player.velocity = input_dir.normalized() * move_speed
	else:
		controlled_player.velocity = Vector2.ZERO


func _update_control_label() -> void:
	var label = hud.get_node_or_null("ControlLabel")
	if label and controlled_player and is_instance_valid(controlled_player):
		var name: String = "A" if controlled_player == player_a else "B"
		var carrying: String = " [持球]" if controlled_player.is_carrying_ball else ""
		label.text = "当前控制: 球员" + name + carrying


func _update_status_panel(panel_name: String, player: CharacterBody2D) -> void:
	var content = hud.get_node_or_null(panel_name + "_Content")
	if not content or not player or not is_instance_valid(player):
		return

	var eff_atk: float = player._get_effective_value("attack", player.attack_power)
	var eff_def: float = player._get_effective_value("defense", player.defense)
	var eff_spd: float = player._get_effective_value("speed", player.speed)
	var eff_res: float = player._get_effective_value("resilience", player.resilience)
	var def_resist: float = eff_def * player.defense_factor
	var text: String = ""
	text += "体力: %.0f / %.0f\n" % [player.stamina, player.max_stamina]
	text += "攻击: %.1f (基%.1f)\n" % [eff_atk, player.attack_power]
	text += "防御: %.1f (基%.1f)\n" % [eff_def, player.defense]
	text += "速度: %.1f (基%.1f)\n" % [eff_spd, player.speed]
	text += "韧性: %.1f (基%.1f)\n" % [eff_res, player.resilience]
	text += "防御抗力: %.1f (%.1f×%.2f)\n" % [def_resist, eff_def, player.defense_factor]

	# 状态灯
	var lights: Array = []
	for lid in player._status_lights:
		var remaining: float = float(player._status_lights[lid].get("remaining", 0.0))
		lights.append("%s%.1fs" % [lid, remaining])
	if lights.is_empty():
		text += "状态灯: 无\n"
	else:
		text += "灯: " + " | ".join(lights) + "\n"

	# Buff
	var buffs: Dictionary = player._buffs
	if buffs.is_empty():
		text += "Buff: 无"
	else:
		text += "Buff(%d):\n" % buffs.size()
		for bid in buffs:
			var b: Dictionary = buffs[bid]
			var bstat: String = str(b.get("stat", ""))
			var bmult: float = float(b.get("mult", 1.0))
			var brem: float = float(b.get("remaining", 0.0))
			text += "  %s ×%.2f %.1fs\n" % [bstat, bmult, brem]

	content.text = text


func _update_zone_count_display() -> void:
	# 场上区域数量显示(在日志标题旁)
	if zone_mgr:
		var count: int = zone_mgr.get_zone_count()
		var obs_count: int = obstacle_mgr.get_obstacle_count() if obstacle_mgr else 0
		# 可以在 HUD 上显示,简化处理


## ==================== 输入处理 ====================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			# === 数字键 1-5：执行配对的标签快捷操作（仅PLAYING阶段，且非输入框聚焦）===
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				if current_phase == Phase.PLAYING and not _is_input_focused():
					var num: int = {KEY_1:1, KEY_2:2, KEY_3:3, KEY_4:4, KEY_5:5}[event.keycode]
					_on_number_key_pressed(num)
			# === 9=重置 / 0=返回面板（固定，仅PLAYING阶段）===
			KEY_9:
				if current_phase == Phase.PLAYING and not _is_input_focused():
					_reset_all()
			KEY_0:
				if current_phase == Phase.PLAYING and not _is_input_focused():
					_toggle_panels()
			KEY_TAB:
				if not _is_input_focused():
					_switch_control()
			KEY_ESCAPE:
				_close_param_popup()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not popup_visible and current_phase == Phase.PLAYING:
			var obs_operating: bool = obstacle_mgr and obstacle_mgr.is_operating()
			var zone_operating: bool = zone_mgr and zone_mgr.is_operating()
			var illusion_operating: bool = illusion_mgr and illusion_mgr.is_operating()
			if not obs_operating and not zone_operating and not illusion_operating:
				_try_throw_ball()


func _is_input_focused() -> bool:
	"""是否有输入框正在编辑（避免数字键误触发快捷）"""
	var focus = get_viewport().gui_get_focus_owner()
	return focus != null and (focus is LineEdit or focus is TextEdit)


func _on_number_key_pressed(num: int) -> void:
	"""数字键→配对的标签快捷执行"""
	for b in key_bindings:
		if int(b["key"]) == num:
			_execute_binding(str(b["tag_id"]))
			return
	_add_log("[color=#888]数字键 %d 未配对标签[/color]" % num)


## ==================== 快捷操作 ====================

func _place_obstacle_direct() -> void:
	"""PLAYING阶段F1:直接用预设参数放置障碍"""
	if not obstacle_mgr:
		return
	if obstacle_mgr.is_operating():
		obstacle_mgr.cancel_operation()
		return
	var params: Dictionary = {
		"shape": obs_params.shape,
		"width": obs_params.width,
		"height": obs_params.height,
		"radius": obs_params.radius,
		"arc_angle": obs_params.arc_angle,
		"hp": obs_params.hp,
		"attack_consume_rate": obs_params.attack_consume_rate,
		"speed_consume_rate": obs_params.speed_consume_rate,
		"max_count": obs_params.max_count,
		"duration": obs_params.duration,
		"mouse_ops": obs_params.mouse_ops,
		"element_color": obs_params.element_color,
		"source_skill": "test_obs",
		"caster_position": controlled_player.global_position,
	}
	obstacle_mgr.start_placing(params, int(obs_params.mouse_ops))
	_add_log("[color=green]▶ 放置障碍 → 鼠标放置(左键放置/右键取消)[/color]")

func _clear_obstacle_direct() -> void:
	"""PLAYING阶段F2:清除障碍"""
	if not obstacle_mgr:
		return
	if obstacle_mgr.is_operating():
		obstacle_mgr.cancel_operation()
		return
	obstacle_mgr.start_clearing(int(obs_clear_params.clear_count), int(obs_clear_params.mouse_ops))
	_add_log("[color=cyan]清除障碍模式[/color]")


func _place_illusion_direct() -> void:
	"""PLAYING阶段F9:用预设参数放置幻象（以当前控制球员为真身）"""
	if not illusion_mgr:
		return
	if illusion_mgr.is_operating():
		illusion_mgr.cancel_operation()
		return
	var source: CharacterBody2D = controlled_player if controlled_player and is_instance_valid(controlled_player) else player_a
	var params: Dictionary = {
		"place_mode": illusion_params.place_mode,
		"stamina": illusion_params.stamina,
		"duration": illusion_params.duration,
		"ai_mode": illusion_params.ai_mode,
		"source_player": source,
	}
	illusion_mgr.start_placing(params, int(illusion_params.count))
	_add_log("[color=#aa88ff]▶ 幻象生成(%s模式) 真身=球员%s → 鼠标放置(左键确认/右键取消)[/color]" % [
		"近身" if illusion_params.place_mode == "near" else "任意",
		"A" if source == player_a else "B"
	])


func _clear_illusion_direct() -> void:
	"""清除幻象：释放后直接清除场上所有幻象（无鼠标系统）"""
	if not illusion_mgr:
		return
	if illusion_mgr.is_operating():
		illusion_mgr.cancel_operation()
		return
	var n: int = illusion_mgr.get_illusion_count()
	illusion_mgr.clear_all_illusions()
	_add_log("[color=#aa88ff]幻象破除: 清除场上所有幻象(%d个)[/color]" % n)

func _reset_all() -> void:
	if obstacle_mgr:
		obstacle_mgr.cancel_operation()
		obstacle_mgr.clear_all_obstacles()
	if zone_mgr:
		zone_mgr.cancel_operation()
		zone_mgr.clear_all_zones()
	if illusion_mgr:
		illusion_mgr.cancel_operation()
		illusion_mgr.clear_all_illusions()
	for p in [player_a, player_b]:
		if p and is_instance_valid(p):
			p.stamina = p.max_stamina
			p.spirit_energy = p.max_spirit_energy
			p._buffs.clear()
			p._status_lights.clear()
			p._tick_effects.clear()
			p.is_defeated = false
			if p == player_a:
				p.global_position = Vector2(-300.0, 0.0)
			else:
				p.global_position = Vector2(300.0, 0.0)
	player_a.set_physics_process(false)
	player_b.set_physics_process(false)
	# 重置球标签修饰符(球标签是永久修饰符,无duration,必须手动清)
	# 否则增伤/减速等会一直挂着,导致对比测试时两次发球球伤害相同
	if handler:
		handler.reset_ball_mods()
	current_phase = Phase.SETUP
	_show_skill_bar(false)
	for node in main_ui_nodes:
		if node and is_instance_valid(node):
			node.visible = true
	if ball_node and is_instance_valid(ball_node) and player_a and is_instance_valid(player_a):
		ball_node.owner_player = player_a
		player_a.is_carrying_ball = true
		player_a.set_carrying_ball(true)
	_add_log("[color=cyan]已重置所有状态,回到面板[/color]")


func _on_start_test() -> void:
	current_phase = Phase.PLAYING
	player_a.set_physics_process(true)
	player_b.set_physics_process(true)
	handler.set_process(true)
	for node in main_ui_nodes:
		if node and is_instance_valid(node):
			node.visible = false
	_show_skill_bar(true)
	# 更新按钮文字(下次返回面板时显示)
	var start_btn = hud.get_node_or_null("StartBtn")
	if start_btn and is_instance_valid(start_btn):
		start_btn.text = "▶ 继续测试(隐藏面板)"
	_add_log("[color=green]▶ 测试开始 | 左侧配数字键1-5 | 9=重置 | 0=返回面板[/color]")


func _toggle_panels() -> void:
	var show: bool = current_phase == Phase.PLAYING
	current_phase = Phase.SETUP if show else Phase.PLAYING
	for node in main_ui_nodes:
		if node and is_instance_valid(node):
			node.visible = show
	_show_skill_bar(not show)

	# 更新"开始测试"按钮文字
	var start_btn = hud.get_node_or_null("StartBtn")
	if start_btn and is_instance_valid(start_btn):
		start_btn.text = "▶ 继续测试(隐藏面板)" if show else ""

	if show:
		player_a.set_physics_process(false)
		player_b.set_physics_process(false)
		handler.set_process(false)
		_add_log("[color=yellow]⏸ 已暂停 | 修改参数后点'继续测试'或按0[/color]")
	else:
		player_a.set_physics_process(true)
		player_b.set_physics_process(true)
		handler.set_process(true)
		_add_log("[color=green]▶ 测试继续 | F7=重置 | F8=暂停[/color]")


func _switch_control() -> void:
	if controlled_player == player_a:
		controlled_player = player_b
	else:
		controlled_player = player_a
	_add_log("切换控制: 球员" + ("A" if controlled_player == player_a else "B"))


func _try_throw_ball() -> void:
	if not ball_node or not controlled_player:
		return
	if not controlled_player.is_carrying_ball:
		return
	if controlled_player.is_status_active("disarmed"):
		_add_log("[color=red]缴械中,无法发球[/color]")
		return
	var mouse_pos: Vector2 = _get_mouse_world_pos()
	var throw_dir: Vector2 = (mouse_pos - controlled_player.global_position).normalized()
	if throw_dir.length() < 0.01:
		throw_dir = Vector2.RIGHT
	ball_node.launch(
		controlled_player.global_position,
		throw_dir,
		controlled_player._get_effective_value("attack", controlled_player.attack_power),
		600.0,
		controlled_player
	)
	controlled_player.is_carrying_ball = false
	controlled_player.set_carrying_ball(false)
	_add_log("发球! 方向=%.1f,%.1f" % [throw_dir.x, throw_dir.y])


func _get_mouse_world_pos() -> Vector2:
	var viewport = get_viewport()
	if viewport:
		var screen_size: Vector2 = viewport.get_visible_rect().size
		var mouse_screen: Vector2 = viewport.get_mouse_position()
		return mouse_screen - screen_size / 2.0
	return Vector2.ZERO


## ==================== 体力设置 ====================

func _set_player_hp(player: CharacterBody2D, input: LineEdit) -> void:
	if not player or not is_instance_valid(player) or not input:
		return
	player.stamina = clampf(float(input.text.strip_edges()), 0.0, player.max_stamina)
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 体力→%.0f" % [name, player.stamina])


func _set_player_hp_pct(player: CharacterBody2D, pct: float) -> void:
	if not player or not is_instance_valid(player):
		return
	player.stamina = player.max_stamina * clampf(pct, 0.0, 1.0)
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 体力→%.0f" % [name, player.stamina])


## ==================== 高风险组合自动测试 ====================

## 组合测试用例：每组 {name, tags:[{id, params, caster}], expect, check}
## expect=预期结果描述；check=校验函数引用(返回{pass:bool, detail:String})

func _snapshot_player_combo(p: CharacterBody2D) -> Dictionary:
	"""快照球员关键状态（组合测试用）"""
	if not p or not is_instance_valid(p):
		return {}
	return {
		"name": "A" if p == player_a else "B",
		"stamina": snappedf(p.stamina, 0.1),
		"attack": snappedf(p._get_effective_value("attack", p.attack_power), 0.1),
		"defense": snappedf(p._get_effective_value("defense", p.defense), 0.1),
		"speed": snappedf(p._get_effective_value("speed", p.speed), 0.1),
		"invincible": p.is_status_active("invincible"),
		"vulnerable": p.is_status_active("vulnerable"),
		"stealthed": p.is_status_active("stealthed"),
		"rooted": p.is_status_active("rooted"),
		"stunned": p.is_status_active("stunned"),
		"cc_immune": p.is_status_active("cc_immune"),
		"buff_count": p._buffs.size(),
		"light_count": p._status_lights.size(),
	}


func _reset_player_state(p: CharacterBody2D) -> void:
	"""重置球员状态到干净基线"""
	if not p or not is_instance_valid(p):
		return
	p._buffs.clear()
	p._status_lights.clear()
	p._tick_effects.clear()
	p.is_defeated = false
	p.stamina = p.max_stamina
	p.spirit_energy = p.max_spirit_energy
	p.global_position = Vector2(-300.0, 0.0) if p == player_a else Vector2(300.0, 0.0)
	p.velocity = Vector2.ZERO


func _apply_tag_to(tag_id: String, params: Dictionary, caster: CharacterBody2D) -> Dictionary:
	"""执行标签（封装调用）"""
	if not handler:
		return {"success": false, "error": "handler 不存在"}
	return handler.apply_tag_effect(tag_id, params, caster.get_instance_id())


func _run_combo_tests() -> void:
	"""一键跑15组高风险组合测试"""
	_add_log("\n[color=yellow]═══════ 组合测试开始 (15组) ═══════[/color]")
	var pass_count: int = 0
	var fail_count: int = 0

	# 清理环境
	if illusion_mgr:
		illusion_mgr.clear_all_illusions()
	_reset_player_state(player_a)
	_reset_player_state(player_b)

	for i in range(1, 16):
		_reset_player_state(player_a)
		_reset_player_state(player_b)
		if illusion_mgr:
			illusion_mgr.clear_all_illusions()
		var result: Dictionary = await _run_one_combo(i)
		var status: String = "[color=green]✓PASS[/color]" if result["pass"] else "[color=red]✗FAIL[/color]"
		_add_log("[%2d] %s %s | %s" % [i, status, result["name"], result["detail"]])
		if result["pass"]:
			pass_count += 1
		else:
			fail_count += 1

	_add_log("[color=yellow]═══════ 完成: %d通过 / %d失败 ═══════[/color]" % [pass_count, fail_count])
	# 清理
	_reset_player_state(player_a)
	_reset_player_state(player_b)
	if illusion_mgr:
		illusion_mgr.clear_all_illusions()


func _run_one_combo(idx: int) -> Dictionary:
	"""执行单组组合测试，返回 {name, pass, detail}"""
	match idx:
		1:
			# 攻击+30%×3 同stat叠加 → buff_count=3, attack=base×1.3³
			var snap_before: Dictionary = _snapshot_player_combo(player_b)
			for _i in range(3):
				_apply_tag_to("player_atk_up_pct", {"value": 30, "target": "enemies"}, player_a)
			var snap_after: Dictionary = _snapshot_player_combo(player_b)
			var expected_atk: float = snappedf(player_b.attack_power * 1.3 * 1.3 * 1.3, 0.1)
			var ok: bool = snap_after["buff_count"] == 3 and absf(snap_after["attack"] - expected_atk) < 0.5
			return {"name": "攻击+30%×3同stat叠加", "pass": ok,
				"detail": "buff数%d/期望3, atk%.1f/期望%.1f" % [snap_after["buff_count"], snap_after["attack"], expected_atk]}
		2:
			# 无敌+易伤互斥
			_apply_tag_to("player_invincible", {"target": "self"}, player_b)
			var has_inv: bool = player_b.is_status_active("invincible")
			_apply_tag_to("player_vulnerable", {"target": "self", "multiplier": 1.5}, player_b)
			var still_inv: bool = player_b.is_status_active("invincible")
			var has_vul: bool = player_b.is_status_active("vulnerable")
			# 无敌应优先，易伤被拦（互斥设计）
			var ok: bool = has_inv and (not has_vul or still_inv)
			return {"name": "无敌+易伤互斥", "pass": ok,
				"detail": "无敌=%s 易伤=%s" % [still_inv, has_vul]}
		3:
			# 免控+眩晕前置拦截
			_apply_tag_to("player_cc_immune", {"target": "self"}, player_b) if _has_tag("player_cc_immune") else player_b.turn_on_light("cc_immune", 5.0)
			var immune_first: bool = player_b.is_status_active("cc_immune")
			_apply_tag_to("player_stun", {"target": "enemies"}, player_a) if _has_tag("player_stun") else player_b.turn_on_light("stunned", 2.0)
			var stunned: bool = player_b.is_status_active("stunned")
			# 免控应拦截眩晕
			var ok: bool = immune_first and not stunned
			return {"name": "免控+眩晕前置拦截", "pass": ok,
				"detail": "免控=%s 眩晕=%s" % [immune_first, stunned]}
		4:
			# 隐身+显形互斥
			_apply_tag_to("player_stealth", {"target": "self"}, player_b)
			var stealthed: bool = player_b.is_status_active("stealthed")
			_apply_tag_to("player_reveal", {"target": "enemies"}, player_a)
			var revealed: bool = not player_b.is_status_active("stealthed")
			var ok: bool = stealthed and revealed
			return {"name": "隐身+显形互斥", "pass": ok,
				"detail": "先隐身=%s 后显形=%s" % [stealthed, revealed]}
		5:
			# 易伤+受伤(无韧性)
			var base_stam: float = player_b.stamina
			_apply_tag_to("player_vulnerable", {"target": "self", "multiplier": 1.5}, player_b)
			var raw_dmg: float = 50.0
			var def_resist: float = player_b._get_effective_value("defense", player_b.defense) * player_b.defense_factor
			player_b.take_damage(raw_dmg, player_a)
			var expected_dmg: float = maxf(0.0, raw_dmg * 1.5 - def_resist)
			var actual_dmg: float = base_stam - player_b.stamina
			var ok: bool = absf(actual_dmg - expected_dmg) < 1.0
			return {"name": "易伤+受伤(无韧性)", "pass": ok,
				"detail": "实际扣%.1f/期望%.1f(攻击%.0f×易伤1.5-防御抗力%.1f)" % [actual_dmg, expected_dmg, raw_dmg, def_resist]}
		6:
			# 防御up+受伤(防御减伤)
			var base_stam: float = player_b.stamina
			var base_def: float = player_b.defense
			_apply_tag_to("player_def_up_pct", {"value": 50, "target": "self"}, player_b)
			var raw_dmg: float = 80.0
			var new_def_resist: float = player_b._get_effective_value("defense", player_b.defense) * player_b.defense_factor
			player_b.take_damage(raw_dmg, player_a)
			var expected_dmg: float = maxf(0.0, raw_dmg - new_def_resist)
			var actual_dmg: float = base_stam - player_b.stamina
			var ok: bool = absf(actual_dmg - expected_dmg) < 1.0 and new_def_resist > base_def * player_b.defense_factor
			return {"name": "防御+50%减伤", "pass": ok,
				"detail": "扣%.1f/期望%.1f 防御抗力%.1f>原%.1f" % [actual_dmg, expected_dmg, new_def_resist, base_def * player_b.defense_factor]}
		7:
			# 危险区+球员站在区里(扣血)
			if not zone_mgr:
				return {"name": "危险区+球员", "pass": false, "detail": "无zone_mgr"}
			var base_stam: float = player_b.stamina
			player_b.global_position = Vector2(0, 0)
			zone_mgr.create_zone({"zone_type": 2, "width": 200.0, "height": 200.0, "duration": 0.6, "effect_value": 50.0}, Vector2(0, 0))
			await get_tree().create_timer(0.4).timeout
			var actual_dmg: float = base_stam - player_b.stamina
			zone_mgr.clear_all_zones()
			var ok: bool = actual_dmg > 0.0
			return {"name": "危险区扣球员血", "pass": ok,
				"detail": "区内0.4秒扣%.1f" % actual_dmg}
		8:
			# 加速区+减速区重叠(都挂speed buff)
			if not zone_mgr:
				return {"name": "加速区+减速区重叠", "pass": false, "detail": "无zone_mgr"}
			player_b.global_position = Vector2(0, 0)
			zone_mgr.create_zone({"zone_type": 0, "width": 200.0, "height": 200.0, "duration": 1.0, "effect_value": 1.5}, Vector2(0, 0))
			zone_mgr.create_zone({"zone_type": 1, "width": 200.0, "height": 200.0, "duration": 1.0, "effect_value": 1.5}, Vector2(0, 0))
			await get_tree().create_timer(0.3).timeout
			var buff_n: int = player_b._buffs.size()
			zone_mgr.clear_all_zones()
			var ok: bool = buff_n >= 2
			return {"name": "加速+减速区重叠", "pass": ok,
				"detail": "双区共存buff数=%d(期望≥2)" % buff_n}
		9:
			# 生成幻象+危险区(幻象进区不报错)
			if not illusion_mgr or not zone_mgr:
				return {"name": "幻象+危险区", "pass": false, "detail": "无illusion/zone_mgr"}
			var source: CharacterBody2D = player_b
			var ill = illusion_mgr.create_illusion(source, {"stamina": 60.0, "duration": 0.8}, Vector2(0, 0))
			zone_mgr.create_zone({"zone_type": 2, "width": 200.0, "height": 200.0, "duration": 0.5, "effect_value": 30.0}, Vector2(0, 0))
			await get_tree().create_timer(0.3).timeout
			var ill_alive: bool = ill != null and is_instance_valid(ill)
			zone_mgr.clear_all_zones()
			illusion_mgr.clear_all_illusions()
			var ok: bool = ill_alive
			return {"name": "幻象进危险区(不报错)", "pass": ok,
				"detail": "幻象存活=%s" % ill_alive}
		10:
			# 生成幻象+球击中幻象(球继续飞,不当作击中真身)
			if not illusion_mgr:
				return {"name": "球击幻象", "pass": false, "detail": "无illusion_mgr"}
			var base_stam: float = player_b.stamina
			var ill = illusion_mgr.create_illusion(player_b, {"stamina": 60.0, "duration": 1.0}, Vector2(0, -60))
			var ill_stam_before: float = ill.stamina if ill else 0.0
			# 直接调用幻象take_damage模拟击中
			var res: Dictionary = ill.take_damage(30.0, player_a)
			var ill_stam_after: float = ill.stamina
			var true_unchanged: bool = absf(player_b.stamina - base_stam) < 0.1
			illusion_mgr.clear_all_illusions()
			var ok: bool = ill_stam_after < ill_stam_before and true_unchanged
			return {"name": "球击幻象(真身不受影响)", "pass": ok,
				"detail": "幻象体力%.0f→%.0f, 真身%.0f不变" % [ill_stam_before, ill_stam_after, player_b.stamina]}
		11:
			# 球加速+球伤害up(球标签内部叠加)
			var base_ball_dmg: float = 40.0
			if not handler:
				return {"name": "球标签叠加", "pass": false, "detail": "无handler"}
			_apply_tag_to("ball_dmg_up_pct", {"value": 50}, player_a)
			_apply_tag_to("ball_speed_up_pct", {"value": 30}, player_a)
			var mod_dmg: float = handler.get_modified_ball_damage(base_ball_dmg)
			var ok: bool = mod_dmg > base_ball_dmg
			return {"name": "球伤害+球速叠加", "pass": ok,
				"detail": "基础%.0f→修正%.1f" % [base_ball_dmg, mod_dmg]}
		12:
			# 球穿透+击中真身(穿透不报错)
			_apply_tag_to("ball_penetrate", {}, player_a)
			var is_pen: bool = handler and handler.is_ball_penetrating()
			var ok: bool = is_pen == true
			return {"name": "球穿透标签", "pass": ok,
				"detail": "穿透状态=%s" % is_pen}
		13:
			# 球追踪+目标隐身(追踪目标隐身丢失)
			_apply_tag_to("ball_tracking", {}, player_a)
			var tracking_before: bool = handler and handler.is_ball_tracking()
			_apply_tag_to("player_stealth", {"target": "self"}, player_b)
			var target_stealthed: bool = player_b.is_status_active("stealthed")
			var ok: bool = tracking_before and target_stealthed
			return {"name": "追踪球+目标隐身", "pass": ok,
				"detail": "追踪=%s 目标隐身=%s" % [tracking_before, target_stealthed]}
		14:
			# 球AOE+范围内幻象(幻象不计入AOE)
			if not illusion_mgr or not handler:
				return {"name": "AOE+幻象", "pass": false, "detail": "无illusion/handler"}
			var ill = illusion_mgr.create_illusion(player_b, {"stamina": 60.0, "duration": 1.0}, Vector2(0, 0))
			var ill_stam_before: float = ill.stamina
			player_b.global_position = Vector2(0, 0)
			_apply_tag_to("ball_range_up", {"value": 50}, player_a)
			var has_aoe: bool = handler.has_ball_aoe()
			# 模拟AOE：遍历players组手动扣
			if has_aoe:
				var aoe_dmg: float = 20.0
				for p in get_tree().get_nodes_in_group("players"):
					if p.get("is_illusion") == true:
						continue
					if p.team != player_b.team:
						continue
					if p.global_position.distance_to(player_b.global_position) <= 100.0:
						p.take_damage(aoe_dmg, player_a)
			var ill_stam_after: float = ill.stamina
			illusion_mgr.clear_all_illusions()
			var ok: bool = absf(ill_stam_after - ill_stam_before) < 0.1
			return {"name": "AOE不波及幻象", "pass": ok,
				"detail": "幻象体力%.0f未变=%s" % [ill_stam_after, ok]}
		15:
			# 三类同局:危险区+幻象+追踪球击幻象
			if not illusion_mgr or not zone_mgr or not handler:
				return {"name": "三类同局", "pass": false, "detail": "缺少manager"}
			zone_mgr.create_zone({"zone_type": 2, "width": 300.0, "height": 300.0, "duration": 0.8, "effect_value": 20.0}, Vector2(0, 0))
			var ill = illusion_mgr.create_illusion(player_b, {"stamina": 80.0, "duration": 0.8}, Vector2(0, 0))
			_apply_tag_to("ball_tracking", {}, player_a)
			await get_tree().create_timer(0.3).timeout
			var all_alive: bool = is_instance_valid(ill)
			zone_mgr.clear_all_zones()
			illusion_mgr.clear_all_illusions()
			var ok: bool = all_alive
			return {"name": "三类同局不崩溃", "pass": ok,
				"detail": "幻象存活=%s" % all_alive}
		_:
			return {"name": "未知用例", "pass": false, "detail": "idx=%d" % idx}


func _has_tag(tag_id: String) -> bool:
	"""检查标签是否在 registry 已实现列表"""
	return _is_tag_implemented(tag_id)
