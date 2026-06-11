## 球员标签测试平台
## 独立测试场景,用于逐个测试51个球员标签的完整链路
## 链路:按钮点击 → handler.apply_tag_effect → player接口 → 效果结算 → 面板实时显示

extends Node2D

## ==================== 场地常量 ====================
const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const FIELD_COLOR: Color = Color(0.12, 0.18, 0.12)

## ==================== 节点引用 ====================
var player_a: CharacterBody2D  # 我方(蓝)
var player_b: CharacterBody2D  # 敌方(红)
var ball_node: Area2D          # 球
var controlled_player: CharacterBody2D  # 当前控制的球员
var handler: Node              # SpiritTagEffectHandler
var ui_layer: CanvasLayer
var hud: Control
var log_panel: RichTextLabel

## ==================== 标签数据 ====================
# 51个标签按8组分类
var tag_groups: Array = []   # [{name, tags: [{id, name, params}]}]
var all_tags_dict: Dictionary = {}  # id → tag数据

## ==================== 状态 ====================
var selected_tag_id: String = ""
var param_inputs: Dictionary = {}   # param_key → LineEdit
var target_option: OptionButton
var log_lines: Array = []
var popup_panel: Panel
var popup_visible: bool = false

## 阶段
enum Phase { SETUP, PLAYING }
var current_phase: int = Phase.SETUP
var main_ui_nodes: Array = []  # 存储主UI节点引用,用于显隐切换

## 默认测试参数(按标签类型给合理默认值)
var default_params: Dictionary = {
	"value": 30.0,
	"duration": 5.0,
	"multiplier": 1.5,
	"target": "self",
	"pos_x": 100.0,
	"pos_y": 0.0,
	"skill_id": "",
	"bonus_uses": 1,
}


## ==================== 初始化 ====================

func _ready() -> void:
	_load_tag_data()
	_create_field()
	_create_handler()
	_create_players()
	_create_ball()
	_create_ui()
	_add_log("[color=cyan]测试平台已加载 | WASD=移动 | Tab=切换球员 | 左键=发球 | F5=重置[/color]")
	print("[PlayerTagTest] 测试平台已加载,共%d个标签" % all_tags_dict.size())


func _load_tag_data() -> void:
	"""从 tags_registry.json 加载 PLAYER 标签"""
	var path: String = "res://data/spirits/tags_registry.json"
	if not FileAccess.file_exists(path):
		push_error("[PlayerTagTest] 找不到 tags_registry.json")
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()

	var tags_array: Array = json.data.get("tags", [])
	# 按 sub_category 分组
	var groups_dict: Dictionary = {}
	var group_order: Array = ["属性", "状态", "体力", "运动", "能量", "元灵", "控制", "交互"]
	var group_names: Dictionary = {
		"属性": "1属性类(改数值)",
		"状态": "2状态类(点灯)",
		"体力": "3体力类",
		"运动": "4运动类",
		"能量": "5能量类",
		"元灵": "6元灵类",
		"控制": "7控制类",
		"交互": "8交互类",
	}

	for tag in tags_array:
		if tag.get("category", "") != "PLAYER":
			continue
		var sub: String = tag.get("sub_category", "")
		all_tags_dict[tag.id] = tag
		if not groups_dict.has(sub):
			groups_dict[sub] = []
		groups_dict[sub].append(tag)

	# 按固定顺序排组
	for sub in group_order:
		if groups_dict.has(sub):
			tag_groups.append({
				"name": group_names.get(sub, sub),
				"tags": groups_dict[sub]
			})


## ==================== 创建场地 ====================

func _create_field() -> void:
	"""创建场地背景和边界"""
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

	# 中线
	var mid_line := Line2D.new()
	mid_line.add_point(Vector2(0, -FIELD_HEIGHT / 2.0))
	mid_line.add_point(Vector2(0, FIELD_HEIGHT / 2.0))
	mid_line.default_color = Color(0.3, 0.4, 0.3, 0.5)
	mid_line.width = 2.0
	add_child(mid_line)

	# 边界墙
	_create_wall(Vector2(-FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))
	_create_wall(Vector2(FIELD_WIDTH / 2.0, 0.0), Vector2(10.0, FIELD_HEIGHT))
	_create_wall(Vector2(0.0, -FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))
	_create_wall(Vector2(0.0, FIELD_HEIGHT / 2.0), Vector2(FIELD_WIDTH, 10.0))

	# 摄像机
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


## ==================== 创建 Handler ====================

func _create_handler() -> void:
	"""创建 SpiritTagEffectHandler"""
	var handler_script := load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd")
	handler = handler_script.new()
	handler.name = "SpiritTagEffectHandler"
	add_child(handler)
	# 球需要通过 group 找到 handler
	handler.add_to_group("spirit_system")


## ==================== 创建球员 ====================

func _create_players() -> void:
	"""创建两个测试球员"""
	# 尝试从 DataManager 加载角色数据
	var char_data_a: Dictionary = _get_char_data(0)
	var char_data_b: Dictionary = _get_char_data(1)

	player_a = _create_player_node(char_data_a, "a", Vector2(-300.0, 0.0), Color(0.3, 0.6, 1.0))
	player_b = _create_player_node(char_data_b, "b", Vector2(300.0, 0.0), Color(1.0, 0.4, 0.3))
	add_child(player_a)
	add_child(player_b)

	# 关键:handler.players 必须设置,否则 _get_caster / _get_player_targets 全部失效
	# handler.players 是 Array[Node] 类型,需要逐个 append
	handler.players.clear()
	handler.players.append(player_a)
	handler.players.append(player_b)

	controlled_player = player_a


func _create_ball() -> void:
	"""创建球"""
	var ball_script := load("res://scripts/battle/ball.gd")
	ball_node = Area2D.new()
	ball_node.set_script(ball_script)
	ball_node.name = "Ball"
	ball_node.add_to_group("ball")
	add_child(ball_node)
	# 球初始跟随球员A
	ball_node.owner_player = player_a
	player_a.is_carrying_ball = true
	player_a.set_carrying_ball(true)


func _get_char_data(index: int) -> Dictionary:
	"""获取角色数据"""
	if DataManager and DataManager.characters.size() > index:
		return DataManager.characters[index]
	# 备用:直接读文件
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
	# 最终备用:默认数据
	return {
		"id": "default_%d" % index,
		"name": "测试球员%d" % (index + 1),
		"stamina": 100.0, "attack": 38.0, "defense": 60.0,
		"speed": 70.0, "resilience": 50.0, "defense_factor": 0.15,
	}


func _create_player_node(data: Dictionary, team_name: String, start_pos: Vector2, _color: Color) -> CharacterBody2D:
	"""创建球员节点"""
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.set_script(player_script)
	player.character_id = str(data.get("id", ""))
	player.team = team_name
	player.is_player_controlled = false
	player.global_position = start_pos
	# initialize 需要 DataManager 有数据
	if DataManager:
		player.initialize(str(data.get("id", "")), team_name, false)
	# 手动确保属性正确
	player.max_stamina = float(data.get("stamina", 100.0))
	player.stamina = player.max_stamina
	player.attack_power = float(data.get("attack", 38.0))
	player.defense = float(data.get("defense", 60.0))
	player.speed = float(data.get("speed", 70.0)) * 3.25
	player.resilience = float(data.get("resilience", 50.0))
	player.defense_factor = float(data.get("defense_factor", 0.15))
	player.max_spirit_energy = 100.0
	player.spirit_energy = 100.0
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

	# === 左面板:球员状态 ===
	_create_status_panels()

	# === 右面板:标签按钮 ===
	_create_tag_button_panel()

	# === 日志面板 ===
	_create_log_panel()

	# === "开始测试"按钮 ===
	var start_btn := Button.new()
	start_btn.name = "StartBtn"
	start_btn.text = "▶ 开始测试（隐藏面板）"
	start_btn.position = Vector2(520, 650)
	start_btn.size = Vector2(220, 36)
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.pressed.connect(_on_start_test)
	hud.add_child(start_btn)
	main_ui_nodes.append(start_btn)

	# === "一键验证51标签"按钮 ===
	var auto_test_btn := Button.new()
	auto_test_btn.name = "AutoTestBtn"
	auto_test_btn.text = "🔍 一键验证51标签"
	auto_test_btn.position = Vector2(520, 690)
	auto_test_btn.size = Vector2(220, 36)
	auto_test_btn.add_theme_font_size_override("font_size", 16)
	auto_test_btn.pressed.connect(_auto_test_all_tags)
	hud.add_child(auto_test_btn)
	main_ui_nodes.append(auto_test_btn)

	# === 操作提示(始终显示)===
	var tips := Label.new()
	tips.name = "TipsLabel"
	tips.text = "WASD=移动 | Tab=切换球员 | 左键=发球 | F5=重置 | F6=显示/隐藏面板"
	tips.position = Vector2(200, 750)
	tips.size = Vector2(900, 22)
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.add_theme_font_size_override("font_size", 14)
	tips.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	hud.add_child(tips)

	# === 当前控制提示(始终显示)===
	var control_label := Label.new()
	control_label.name = "ControlLabel"
	control_label.text = "当前控制: 球员A [持球]"
	control_label.position = Vector2(10, 720)
	control_label.size = Vector2(250, 20)
	control_label.add_theme_font_size_override("font_size", 15)
	control_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	hud.add_child(control_label)


func _create_status_panels() -> void:
	"""左面板:两个球员实时状态"""
	_create_single_status_panel("球员A(我方)", player_a, 10, 35, Color(0.3, 0.7, 1.0), "StatusA")
	_create_single_status_panel("球员B(敌方)", player_b, 10, 340, Color(1.0, 0.5, 0.3), "StatusB")


func _create_single_status_panel(title: String, player: CharacterBody2D, x: float, y: float, color: Color, panel_name: String) -> void:
	"""创建单个球员状态面板"""
	# 背景
	var bg := Panel.new()
	bg.name = panel_name
	bg.position = Vector2(x, y)
	bg.size = Vector2(250, 300)
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

	# 标题
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.position = Vector2(x + 10, y + 5)
	title_lbl.size = Vector2(230, 20)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", color)
	hud.add_child(title_lbl)
	main_ui_nodes.append(title_lbl)

	# 内容 VBox(用绝对定位模拟,避免 VBox 复杂布局)
	# 行内容在 _update_status_panel 中动态更新
	var content := Label.new()
	content.name = panel_name + "_Content"
	content.position = Vector2(x + 10, y + 28)
	content.size = Vector2(230, 210)
	content.add_theme_font_size_override("font_size", 12)
	content.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hud.add_child(content)
	main_ui_nodes.append(content)

	# === 体力/能量 快捷设置区 ===
	var ctrl_y: float = y + 242
	var ctrl_font: int = 11

	# "设置体力" 标签
	var hp_lbl := Label.new()
	hp_lbl.text = "体力设:"
	hp_lbl.position = Vector2(x + 5, ctrl_y)
	hp_lbl.size = Vector2(50, 18)
	hp_lbl.add_theme_font_size_override("font_size", ctrl_font)
	hp_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	hud.add_child(hp_lbl)
	main_ui_nodes.append(hp_lbl)

	# 体力输入框
	var hp_input := LineEdit.new()
	hp_input.name = panel_name + "_HpInput"
	hp_input.text = "50"
	hp_input.position = Vector2(x + 52, ctrl_y - 1)
	hp_input.size = Vector2(45, 18)
	hp_input.add_theme_font_size_override("font_size", ctrl_font)
	hud.add_child(hp_input)
	main_ui_nodes.append(hp_input)

	# 体力设置按钮
	var hp_btn := Button.new()
	hp_btn.text = "设置"
	hp_btn.position = Vector2(x + 100, ctrl_y - 1)
	hp_btn.size = Vector2(40, 18)
	hp_btn.add_theme_font_size_override("font_size", ctrl_font)
	hp_btn.pressed.connect(_set_player_hp.bind(player, hp_input))
	hud.add_child(hp_btn)
	main_ui_nodes.append(hp_btn)

	# 体力快捷按钮 -50%
	var hp_half := Button.new()
	hp_half.text = "-50%"
	hp_half.position = Vector2(x + 144, ctrl_y - 1)
	hp_half.size = Vector2(40, 18)
	hp_half.add_theme_font_size_override("font_size", ctrl_font)
	hp_half.pressed.connect(_set_player_hp_pct.bind(player, 0.5))
	hud.add_child(hp_half)
	main_ui_nodes.append(hp_half)

	# 体力快捷按钮 满
	var hp_full := Button.new()
	hp_full.text = "补满"
	hp_full.position = Vector2(x + 188, ctrl_y - 1)
	hp_full.size = Vector2(40, 18)
	hp_full.add_theme_font_size_override("font_size", ctrl_font)
	hp_full.pressed.connect(_set_player_hp_pct.bind(player, 1.0))
	hud.add_child(hp_full)
	main_ui_nodes.append(hp_full)

	# 第二行：能量
	ctrl_y += 20

	# "设置能量" 标签
	var nrg_lbl := Label.new()
	nrg_lbl.text = "能量设:"
	nrg_lbl.position = Vector2(x + 5, ctrl_y)
	nrg_lbl.size = Vector2(50, 18)
	nrg_lbl.add_theme_font_size_override("font_size", ctrl_font)
	nrg_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.8))
	hud.add_child(nrg_lbl)
	main_ui_nodes.append(nrg_lbl)

	# 能量输入框
	var nrg_input := LineEdit.new()
	nrg_input.name = panel_name + "_NrgInput"
	nrg_input.text = "50"
	nrg_input.position = Vector2(x + 52, ctrl_y - 1)
	nrg_input.size = Vector2(45, 18)
	nrg_input.add_theme_font_size_override("font_size", ctrl_font)
	hud.add_child(nrg_input)
	main_ui_nodes.append(nrg_input)

	# 能量设置按钮
	var nrg_btn := Button.new()
	nrg_btn.text = "设置"
	nrg_btn.position = Vector2(x + 100, ctrl_y - 1)
	nrg_btn.size = Vector2(40, 18)
	nrg_btn.add_theme_font_size_override("font_size", ctrl_font)
	nrg_btn.pressed.connect(_set_player_nrg.bind(player, nrg_input))
	hud.add_child(nrg_btn)
	main_ui_nodes.append(nrg_btn)

	# 能量快捷按钮 -50%
	var nrg_half := Button.new()
	nrg_half.text = "-50%"
	nrg_half.position = Vector2(x + 144, ctrl_y - 1)
	nrg_half.size = Vector2(40, 18)
	nrg_half.add_theme_font_size_override("font_size", ctrl_font)
	nrg_half.pressed.connect(_set_player_nrg_pct.bind(player, 0.5))
	hud.add_child(nrg_half)
	main_ui_nodes.append(nrg_half)

	# 能量快捷按钮 满
	var nrg_full := Button.new()
	nrg_full.text = "补满"
	nrg_full.position = Vector2(x + 188, ctrl_y - 1)
	nrg_full.size = Vector2(40, 18)
	nrg_full.add_theme_font_size_override("font_size", ctrl_font)
	nrg_full.pressed.connect(_set_player_nrg_pct.bind(player, 1.0))
	hud.add_child(nrg_full)
	main_ui_nodes.append(nrg_full)


func _create_tag_button_panel() -> void:
	"""右面板:8组标签按钮"""
	var panel_bg := Panel.new()
	panel_bg.position = Vector2(270, 35)
	panel_bg.size = Vector2(520, 520)
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

	# ScrollContainer
	var scroll := ScrollContainer.new()
	scroll.name = "TagButtonScroll"
	scroll.position = Vector2(275, 40)
	scroll.size = Vector2(510, 510)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(scroll)
	main_ui_nodes.append(scroll)

	# VBox
	var vbox := VBoxContainer.new()
	vbox.name = "TagButtonVBox"
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)
	main_ui_nodes.append(vbox)

	# 按组生成按钮
	for group in tag_groups:
		# 组标题
		var group_lbl := Label.new()
		group_lbl.text = group.name
		group_lbl.add_theme_font_size_override("font_size", 13)
		group_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		vbox.add_child(group_lbl)

		# 标签按钮(一行放3个)
		var hbox: HBoxContainer = null
		for i in range(group.tags.size()):
			if i % 3 == 0:
				hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 3)
				vbox.add_child(hbox)
			var tag: Dictionary = group.tags[i]
			var btn := Button.new()
			btn.text = str(tag.get("code", "")) + "." + str(tag.get("name", ""))
			btn.add_theme_font_size_override("font_size", 11)
			btn.custom_minimum_size = Vector2(165, 26)
			btn.tooltip_text = tag.get("id", "")
			var tag_id: String = tag.get("id", "")
			btn.pressed.connect(_on_tag_button_pressed.bind(tag_id))
			hbox.add_child(btn)

		# 分隔
		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
		vbox.add_child(sep)


func _create_log_panel() -> void:
	"""底部日志面板"""
	var panel_bg := Panel.new()
	panel_bg.position = Vector2(800, 35)
	panel_bg.size = Vector2(490, 520)
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
	log_panel.size = Vector2(480, 490)
	log_panel.bbcode_enabled = true
	log_panel.add_theme_font_size_override("normal_font_size", 12)
	log_panel.scroll_following = true
	hud.add_child(log_panel)
	main_ui_nodes.append(log_panel)


## ==================== 参数弹窗 ====================

func _on_tag_button_pressed(tag_id: String) -> void:
	"""点击标签按钮 → 弹出参数填写面板"""
	selected_tag_id = tag_id
	_show_param_popup(tag_id)


func _show_param_popup(tag_id: String) -> void:
	"""显示参数填写弹窗"""
	# 清除旧弹窗
	_close_param_popup()

	popup_visible = true
	var tag: Dictionary = all_tags_dict.get(tag_id, {})
	var tag_name: String = str(tag.get("name", tag_id))
	var param_keys: Array = tag.get("params", [])

	# 弹窗背景
	popup_panel = Panel.new()
	popup_panel.name = "ParamPopup"
	popup_panel.position = Vector2(400, 200)
	popup_panel.size = Vector2(400, 400 + param_keys.size() * 28)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	bg_style.border_color = Color(0.8, 0.7, 0.3)
	bg_style.set_corner_radius_all(8)
	bg_style.border_width_bottom = 2
	bg_style.border_width_top = 2
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	popup_panel.add_theme_stylebox_override("panel", bg_style)
	hud.add_child(popup_panel)

	# 标题
	var title := Label.new()
	title.text = "标签: %s (%s)" % [tag_name, tag_id]
	title.position = Vector2(15, 10)
	title.size = Vector2(370, 22)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	popup_panel.add_child(title)

	# 施法者选择(谁释放标签)
	var caster_lbl := Label.new()
	caster_lbl.text = "施法者(谁释放):"
	caster_lbl.position = Vector2(15, 40)
	caster_lbl.size = Vector2(150, 18)
	caster_lbl.add_theme_font_size_override("font_size", 13)
	caster_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	popup_panel.add_child(caster_lbl)

	# 作用对象选择(效果落在谁身上)
	var target_lbl := Label.new()
	target_lbl.text = "作用对象(效果落在谁身上):"
	target_lbl.position = Vector2(15, 62)
	target_lbl.size = Vector2(250, 18)
	target_lbl.add_theme_font_size_override("font_size", 13)
	target_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	popup_panel.add_child(target_lbl)

	target_option = OptionButton.new()
	target_option.position = Vector2(15, 82)
	target_option.size = Vector2(350, 22)
	target_option.add_theme_font_size_override("font_size", 13)
	target_option.add_item("施法者自己 (self)", 0)
	target_option.add_item("敌方全体 (enemies)", 1)
	target_option.add_item("队友全体 (allies)", 2)
	target_option.add_item("最近敌人 (nearest_enemy)", 3)
	popup_panel.add_child(target_option)

	# 参数输入框(根据 tags_registry 的 params 生成)
	param_inputs.clear()
	var row_y: float = 112.0
	for key in param_keys:
		var key_str: String = str(key)
		if key_str == "target":
			continue  # target 用下拉选

		var lbl := Label.new()
		lbl.text = _translate_param(key_str) + ":"
		lbl.position = Vector2(15, row_y)
		lbl.size = Vector2(120, 18)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		popup_panel.add_child(lbl)

		var input := LineEdit.new()
		input.name = "Input_" + key_str
		# 预填默认值
		var default_val = _get_default_param_value(tag_id, key_str)
		input.text = str(default_val)
		input.position = Vector2(140, row_y - 2)
		input.size = Vector2(230, 22)
		input.add_theme_font_size_override("font_size", 13)
		popup_panel.add_child(input)
		param_inputs[key_str] = input

		row_y += 28

	# === 元灵能量消耗 ===
	row_y += 4
	var cost_sep := HSeparator.new()
	cost_sep.position = Vector2(15, row_y)
	cost_sep.size = Vector2(370, 2)
	popup_panel.add_child(cost_sep)
	row_y += 6

	var cost_lbl := Label.new()
	cost_lbl.text = "元灵能量消耗(施法者):"
	cost_lbl.position = Vector2(15, row_y)
	cost_lbl.size = Vector2(180, 18)
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	popup_panel.add_child(cost_lbl)

	var cost_input := LineEdit.new()
	cost_input.name = "Input_energy_cost"
	cost_input.text = "0"
	cost_input.position = Vector2(200, row_y - 2)
	cost_input.size = Vector2(80, 22)
	cost_input.add_theme_font_size_override("font_size", 13)
	popup_panel.add_child(cost_input)
	param_inputs["energy_cost"] = cost_input

	var cost_hint := Label.new()
	cost_hint.text = "(0=不消耗)"
	cost_hint.position = Vector2(285, row_y)
	cost_hint.size = Vector2(80, 18)
	cost_hint.add_theme_font_size_override("font_size", 12)
	cost_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	popup_panel.add_child(cost_hint)

	row_y += 30

	# 施法者按钮行(两个按钮:用A或用B当施法者)
	var caster_btn_a := Button.new()
	caster_btn_a.text = "球员A释放"
	caster_btn_a.position = Vector2(50, row_y + 5)
	caster_btn_a.size = Vector2(120, 35)
	caster_btn_a.add_theme_font_size_override("font_size", 15)
	caster_btn_a.pressed.connect(_execute_tag.bind(true))
	popup_panel.add_child(caster_btn_a)

	var caster_btn_b := Button.new()
	caster_btn_b.text = "球员B释放"
	caster_btn_b.position = Vector2(180, row_y + 5)
	caster_btn_b.size = Vector2(120, 35)
	caster_btn_b.add_theme_font_size_override("font_size", 15)
	caster_btn_b.pressed.connect(_execute_tag.bind(false))
	popup_panel.add_child(caster_btn_b)

	var cancel_btn := Button.new()
	cancel_btn.text = "✕ 关闭"
	cancel_btn.position = Vector2(310, row_y + 5)
	cancel_btn.size = Vector2(70, 35)
	cancel_btn.pressed.connect(_close_param_popup)
	popup_panel.add_child(cancel_btn)


func _close_param_popup() -> void:
	"""关闭参数弹窗"""
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()
		popup_panel = null
	popup_visible = false


func _translate_param(key: String) -> String:
	"""翻译参数名为中文"""
	var translations: Dictionary = {
		"value": "数值",
		"duration": "持续时间(秒)",
		"multiplier": "倍率",
		"target": "目标",
		"skill_id": "技能ID",
		"bonus_uses": "增加次数",
		"target_id": "目标球员ID",
		"player_id": "球员ID",
		"target_position": "目标位置",
		"pos_x": "X坐标",
		"pos_y": "Y坐标",
	}
	return translations.get(key, key)


func _translate_stat(stat: String) -> String:
	"""翻译属性名为中文"""
	var map: Dictionary = {
		"attack": "攻击",
		"defense": "防御",
		"speed": "速度",
		"resilience": "韧性",
		"max_energy": "最大能量",
	}
	return map.get(stat, stat)


func _translate_status(status: String) -> String:
	"""翻译状态灯名为中文"""
	var map: Dictionary = {
		"stunned": "眩晕",
		"rooted": "定身",
		"silenced": "沉默",
		"disarmed": "缴械",
		"invincible": "无敌",
		"stealthed": "隐身",
		"cc_immune": "免控",
		"vulnerable": "易伤",
	}
	return map.get(status, status)


func _translate_tick_type(ttype: String) -> String:
	"""翻译持续效果类型"""
	var map: Dictionary = {
		"regen": "回血",
		"dot": "掉血",
	}
	return map.get(ttype, ttype)


func _get_default_param_value(tag_id: String, key: String) -> Variant:
	"""获取参数默认值"""
	# 根据标签类型给出合理默认值
	match key:
		"value":
			if "pct" in tag_id or "pct" in tag_id.to_lower():
				return 30.0
			elif "flat" in tag_id:
				return 10.0
			return 20.0
		"duration":
			return 5.0
		"multiplier":
			return 1.5
		"pos_x":
			return 100.0
		"pos_y":
			return 0.0
		"skill_id":
			return "test_skill_1"
		"bonus_uses":
			return 1
		"target_id", "player_id":
			return ""
	return 30.0


## ==================== 执行标签 ====================

func _execute_tag(use_a_as_caster: bool) -> void:
	"""执行标签效果--核心链路"""
	if selected_tag_id == "":
		return

	# 构建参数字典
	var params: Dictionary = {}
	for key in param_inputs:
		var input: LineEdit = param_inputs[key]
		var text: String = input.text.strip_edges()
		# 尝试转数字
		if text.is_valid_float():
			params[key] = float(text)
		elif text.is_valid_int():
			params[key] = int(text)
		else:
			params[key] = text

	# target
	if target_option:
		var target_modes: Array = ["self", "enemies", "allies", "nearest_enemy"]
		params["target"] = target_modes[target_option.selected]

	# 选择施法者
	var caster: CharacterBody2D = player_a if use_a_as_caster else player_b
	var caster_id: int = caster.get_instance_id()

	# === 元灵能量消耗 ===
	var energy_cost: float = 0.0
	if params.has("energy_cost"):
		energy_cost = float(params["energy_cost"])
		params.erase("energy_cost")
	if energy_cost > 0.0:
		var caster_name: String = "球员A" if use_a_as_caster else "球员B"
		if caster.spirit_energy < energy_cost:
			_add_log("[color=red]✗[/color] %s 能量不足! 需要%.0f, 当前%.0f" % [caster_name, energy_cost, caster.spirit_energy])
			_close_param_popup()
			return
		caster.spirit_energy -= energy_cost
		_add_log("[color=cyan]%s 消耗能量 %.0f → 剩余 %.0f[/color]" % [caster_name, energy_cost, caster.spirit_energy])

	# 调试日志
	_add_log("[color=gray]DEBUG %s caster=%s id=%d target=%s params=%s[/color]" % [selected_tag_id, ("A" if caster == player_a else "B"), caster_id, str(params.get("target", "?")), str(params)])

	# 记录执行前状态
	var before: Dictionary = _snapshot_player(params.get("target", "self"), caster)

	# === 核心链路:调用 handler ===
	var result: Dictionary = handler.apply_tag_effect(selected_tag_id, params, caster_id)

	# 记录执行后状态
	var after: Dictionary = _snapshot_player(params.get("target", "self"), caster)

	# 日志
	var tag_info: Dictionary = all_tags_dict.get(selected_tag_id, {})
	var tag_name: String = str(tag_info.get("name", selected_tag_id))
	var success: bool = result.get("success", false)
	var caster_name: String = "球员A" if use_a_as_caster else "球员B"
	var target_name: String = str(params.get("target", "self"))

	if success:
		_add_log("[color=green]✓[/color] [%s→%s] %s | %s" % [caster_name, target_name, tag_name, _format_params(params)])
		_log_diff(before, after)
	else:
		_add_log("[color=red]✗[/color] 标签未实现: %s" % tag_name)

	_close_param_popup()


func _snapshot_player(target_mode: String, caster: CharacterBody2D) -> Dictionary:
	"""快照目标球员当前状态"""
	var targets: Array = []
	match target_mode:
		"self":
			targets = [caster]
		"enemies":
			targets = [player_b] if caster == player_a else [player_a]
		"allies":
			targets = [player_a] if caster == player_a else [player_b]
		"nearest_enemy":
			targets = [player_b] if caster == player_a else [player_a]
		_:
			targets = [caster]

	if targets.is_empty():
		return {}
	var p: CharacterBody2D = targets[0]
	return {
		"name": "A" if p == player_a else "B",
		"stamina": snappedf(p.stamina, 0.1),
		"attack": snappedf(p._get_effective_value("attack", p.attack_power), 0.1),
		"defense": snappedf(p._get_effective_value("defense", p.defense), 0.1),
		"speed": snappedf(p._get_effective_value("speed", p.speed), 0.1),
		"resilience": snappedf(p._get_effective_value("resilience", p.resilience), 0.1),
		"energy": snappedf(p.spirit_energy, 0.1),
		"max_energy": snappedf(p._get_effective_value("max_energy", p.max_spirit_energy), 0.1),
		"buffs": p._buffs.duplicate(true),
		"lights": p._status_lights.duplicate(true),
		"ticks": p._tick_effects.duplicate(true),
	}


func _log_diff(before: Dictionary, after: Dictionary) -> void:
	"""对比前后差异,记录日志"""
	if before.is_empty() or after.is_empty():
		return
	var name: String = str(before.get("name", "?"))

	# 属性变化
	var attrs: Array = ["stamina", "attack", "defense", "speed", "resilience", "energy", "max_energy"]
	var attr_names: Array = ["体力", "攻击", "防御", "速度", "韧性", "能量", "最大能量"]
	for i in attrs.size():
		var key: String = attrs[i]
		var bv: float = float(before.get(key, 0.0))
		var av: float = float(after.get(key, 0.0))
		if absf(av - bv) > 0.05:
			var diff: float = av - bv
			var sign: String = "+" if diff > 0 else ""
			_add_log("  球员%s %s: %.1f → %.1f (%s%.1f)" % [name, attr_names[i], bv, av, sign, diff])

	# buff变化
	var new_buffs: int = 0
	var after_buffs: Dictionary = after.get("buffs", {})
	var before_buffs: Dictionary = before.get("buffs", {})
	for bid in after_buffs:
		if not before_buffs.has(bid):
			new_buffs += 1
	if new_buffs > 0:
		_add_log("  球员%s 新增%d个buff (共%d个)" % [name, new_buffs, after_buffs.size()])

	# 状态灯变化
	var after_lights: Dictionary = after.get("lights", {})
	var before_lights: Dictionary = before.get("lights", {})
	for lid in after_lights:
		if not before_lights.has(lid):
			var remaining: float = float(after_lights[lid].get("remaining", 0.0))
			_add_log("  球员%s [color=yellow]点灯: %s %.1fs[/color]" % [name, lid, remaining])


func _format_params(params: Dictionary) -> String:
	"""格式化参数为字符串"""
	var parts: Array = []
	for key in params:
		if key == "target":
			continue
		parts.append("%s=%s" % [key, str(params[key])])
	return " ".join(parts)


## ==================== 日志 ====================

func _add_log(text: String) -> void:
	"""添加日志"""
	log_lines.append(text)
	if log_lines.size() > 50:
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


func _process_movement() -> void:
	"""处理当前控制球员移动"""
	if not controlled_player or not is_instance_valid(controlled_player):
		return
	if controlled_player.is_defeated:
		return
	# 眩晕/定身检查
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
	"""更新当前控制提示"""
	var label = hud.get_node_or_null("ControlLabel")
	if label and controlled_player and is_instance_valid(controlled_player):
		var name: String = "A" if controlled_player == player_a else "B"
		var carrying: String = " [持球]" if controlled_player.is_carrying_ball else ""
		label.text = "当前控制: 球员" + name + carrying


func _update_status_panel(panel_name: String, player: CharacterBody2D) -> void:
	"""更新球员状态面板"""
	var content = hud.get_node_or_null(panel_name + "_Content")
	if not content or not player or not is_instance_valid(player):
		return

	var eff_atk: float = player._get_effective_value("attack", player.attack_power)
	var eff_def: float = player._get_effective_value("defense", player.defense)
	var eff_spd: float = player._get_effective_value("speed", player.speed)
	var eff_res: float = player._get_effective_value("resilience", player.resilience)
	var eff_max_nrg: float = player._get_effective_value("max_energy", player.max_spirit_energy)

	var text: String = ""
	text += "体力: %.0f / %.0f\n" % [player.stamina, player.max_stamina]
	text += "能量: %.0f / %.0f\n" % [player.spirit_energy, eff_max_nrg]
	text += "──有效属性──\n"
	text += "攻击: %.1f (基%.1f)\n" % [eff_atk, player.attack_power]
	text += "防御: %.1f (基%.1f)\n" % [eff_def, player.defense]
	text += "速度: %.1f (基%.1f)\n" % [eff_spd, player.speed]
	text += "韧性: %.1f (基%.1f)\n" % [eff_res, player.resilience]

	# 状态灯
	var lights: Array = []
	for lid in player._status_lights:
		var remaining: float = float(player._status_lights[lid].get("remaining", 0.0))
		lights.append("%s%.1fs" % [_translate_status(lid), remaining])
	if lights.is_empty():
		text += "状态灯: 无\n"
	else:
		text += "灯: " + " | ".join(lights) + "\n"

	# Buff列表
	var buffs: Dictionary = player._buffs
	if buffs.is_empty():
		text += "Buff: 无\n"
	else:
		text += "Buff(%d):\n" % buffs.size()
		for bid in buffs:
			var b: Dictionary = buffs[bid]
			var bstat: String = _translate_stat(str(b.get("stat", "")))
			var bmult: float = float(b.get("mult", 1.0))
			var bflat: float = float(b.get("flat", 0.0))
			var brem: float = float(b.get("remaining", 0.0))
			text += "  %s ×%.2f%+.1f %.1fs\n" % [bstat, bmult, bflat, brem]

	# 持续效果
	var ticks: Dictionary = player._tick_effects
	if not ticks.is_empty():
		text += "持续:\n"
		for tid in ticks:
			var t: Dictionary = ticks[tid]
			text += "  %s %.1f/秒 %.1fs\n" % [_translate_tick_type(str(t.get("type", ""))), float(t.get("rate", 0.0)), float(t.get("remaining", 0.0))]

	content.text = text


## ==================== 输入处理 ====================

func _input(event: InputEvent) -> void:
	# F5 重置体力
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_reset_players()
	# ESC 关闭弹窗
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_param_popup()
	# Tab 切换控制球员
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_switch_control()
	# F6 切换面板显隐
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_panels()
	# 左键发球(仅PLAYING阶段且无弹窗时)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not popup_visible and current_phase == Phase.PLAYING:
			_try_throw_ball()


func _on_start_test() -> void:
	"""开始测试 → 隐藏面板"""
	current_phase = Phase.PLAYING
	for node in main_ui_nodes:
		if node and is_instance_valid(node):
			node.visible = false
	_add_log("[color=green]▶ 测试开始 | F6=显示面板 | WASD=移动 | 左键=发球[/color]")


func _toggle_panels() -> void:
	"""F6 切换面板显隐"""
	var show: bool = current_phase == Phase.PLAYING
	current_phase = Phase.SETUP if show else Phase.PLAYING
	for node in main_ui_nodes:
		if node and is_instance_valid(node):
			node.visible = show
	if show:
		_add_log("[color=yellow]面板已显示 | 选标签后点'开始测试'[/color]")
	else:
		_add_log("[color=green]▶ 测试继续 | F6=显示面板[/color]")


func _switch_control() -> void:
	"""Tab 切换控制球员"""
	if controlled_player == player_a:
		controlled_player = player_b
	else:
		controlled_player = player_a
	_add_log("切换控制: 球员" + ("A" if controlled_player == player_a else "B"))


func _try_throw_ball() -> void:
	"""左键发球"""
	if not ball_node or not controlled_player:
		return
	if not controlled_player.is_carrying_ball:
		return
	# 缴械检查
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
	"""获取鼠标世界坐标"""
	var viewport = get_viewport()
	if viewport:
		var screen_size: Vector2 = viewport.get_visible_rect().size
		var mouse_screen: Vector2 = viewport.get_mouse_position()
		return mouse_screen - screen_size / 2.0
	return Vector2.ZERO


func _reset_players() -> void:
	"""重置两个球员状态"""
	for p in [player_a, player_b]:
		if not p or not is_instance_valid(p):
			continue
		p.stamina = p.max_stamina
		p.spirit_energy = p.max_spirit_energy
		p._buffs.clear()
		p._status_lights.clear()
		p._tick_effects.clear()
		p._skill_cost_mults.clear()
		p._skill_cd_mults.clear()
		p._next_skill_mults.clear()
		p.is_defeated = false
		p.global_position = Vector2(-300.0, 0.0) if p == player_a else Vector2(300.0, 0.0)
	# 球回到球员A
	if ball_node and is_instance_valid(ball_node) and player_a and is_instance_valid(player_a):
		ball_node.owner_player = player_a
		player_a.is_carrying_ball = true
		player_a.set_carrying_ball(true)
	_add_log("[color=cyan]已重置所有状态[/color]")


## ==================== 自动验证51标签 ====================

func _auto_test_all_tags() -> void:
	"""一键验证51个标签，报告通过/失败"""
	_add_log("[color=yellow]═══ 开始自动验证51个标签 ═══[/color]")
	var pass_count: int = 0
	var fail_count: int = 0
	var results: Array = []  # [{tag_id, tag_name, status, detail}]

	for group in tag_groups:
		for tag_info in group.tags:
			var tag_id: String = str(tag_info.get("id", ""))
			var tag_name: String = str(tag_info.get("name", tag_id))

			# 重置球员状态
			_reset_for_test()

			# 构建测试参数
			var params: Dictionary = _build_test_params(tag_id, tag_info)

			# 先用球员A当施法者，target=self
			var caster: CharacterBody2D = player_a
			var caster_id: int = caster.get_instance_id()

			# 恢复类标签：先扣血再测
			if tag_id in ["player_hp_heal_pct", "player_hp_heal_flat"]:
				caster.stamina = caster.max_stamina * 0.3  # 扣到30%
			elif tag_id in ["player_energy_gain_pct", "player_energy_gain_flat"]:
				caster.spirit_energy = caster.max_spirit_energy * 0.3
			# 显形：先给施法者挂隐身，目标改enemies打B
			if tag_id == "player_reveal":
				player_b.turn_on_light("stealthed", 10.0)
				params["target"] = "enemies"
			# 自由：先给定身
			if tag_id == "player_unroot":
				caster.turn_on_light("rooted", 10.0)

			# 执行前快照（显形看目标B，其他看施法者A）
			var observe_target: CharacterBody2D = player_b if tag_id == "player_reveal" else caster
			var before: Dictionary = _quick_snapshot(observe_target)

			# 调用 handler
			var result: Dictionary = handler.apply_tag_effect(tag_id, params, caster_id)
			var success: bool = result.get("success", false)

			if not success:
				results.append({"id": tag_id, "name": tag_name, "status": "SKIP", "detail": "handler返回false"})
				fail_count += 1
				continue

			# 执行后快照
			var after: Dictionary = _quick_snapshot(observe_target)

			# 验证：至少有一个属性变化
			var changed: bool = _has_change(before, after)
			var detail: String = _diff_text(before, after)

			if changed:
				results.append({"id": tag_id, "name": tag_name, "status": "PASS", "detail": detail})
				pass_count += 1
			else:
				results.append({"id": tag_id, "name": tag_name, "status": "FAIL", "detail": "无变化"})
				fail_count += 1

	# 输出结果
	_add_log("[color=yellow]═══ 验证结果: %d通过 / %d失败 / 共%d ═══[/color]" % [pass_count, fail_count, results.size()])

	# 写入文件
	var report: String = "=== 51标签自动验证报告 ===\n"
	report += "通过: %d / 失败: %d / 共: %d\n\n" % [pass_count, fail_count, results.size()]
	for r in results:
		var color: String = "green" if r.status == "PASS" else ("yellow" if r.status == "SKIP" else "red")
		var mark: String = "✓" if r.status == "PASS" else ("?" if r.status == "SKIP" else "✗")
		var line: String = "%s %s (%s) %s" % [mark, r.name, r.id, r.detail]
		_add_log("[color=%s]%s[/color]" % [color, line])
		report += line + "\n"

	report += "\n=== 施法者B→目标A 组合测试 ===\n"

	# 测试施法者B + target=enemies 组合（抽样5个标签）
	_add_log("[color=yellow]═══ 施法者B→目标A 组合测试 ═══[/color]")
	var sample_tags: Array = ["player_stun", "player_hp_damage_flat", "player_atk_up_pct", "player_vulnerable", "player_hp_dot"]
	for stag_id in sample_tags:
		_reset_for_test()
		var stag_info: Dictionary = all_tags_dict.get(stag_id, {})
		var sparams: Dictionary = _build_test_params(stag_id, stag_info)
		sparams["target"] = "enemies"  # B→打A
		var before_ba: Dictionary = _quick_snapshot(player_a)
		handler.apply_tag_effect(stag_id, sparams, player_b.get_instance_id())
		var after_ba: Dictionary = _quick_snapshot(player_a)
		if _has_change(before_ba, after_ba):
			_add_log("[color=green]✓[/color] B→A %s 生效" % stag_id)
			report += "✓ B→A %s 生效\n" % stag_id
		else:
			_add_log("[color=red]✗[/color] B→A %s 无变化" % stag_id)
			report += "✗ B→A %s 无变化\n" % stag_id

	_reset_for_test()

	# 保存报告文件
	var file = FileAccess.open("user://tag_test_report.txt", FileAccess.WRITE)
	if file:
		file.store_string(report)
		file.close()
		_add_log("[color=cyan]报告已保存: %s[/color]" % ProjectSettings.globalize_path("user://tag_test_report.txt"))
	else:
		_add_log("[color=red]保存报告失败[/color]")


func _reset_for_test() -> void:
	"""重置两个球员到测试初始状态"""
	for p in [player_a, player_b]:
		if not p or not is_instance_valid(p):
			return
		p.stamina = p.max_stamina
		p.spirit_energy = p.max_spirit_energy
		p._buffs.clear()
		p._status_lights.clear()
		p._tick_effects.clear()
		p._skill_cost_mults.clear()
		p._skill_cd_mults.clear()
		p._next_skill_mults.clear()
		p._skill_bonus_uses.clear()
		p.is_defeated = false


func _build_test_params(tag_id: String, tag_info: Dictionary) -> Dictionary:
	"""为标签构建测试参数"""
	var params: Dictionary = {}
	# 按标签类型构建不同参数
	var sub: String = str(tag_info.get("sub_category", ""))

	# 通用：读 registry 声明的 params 填默认值
	var declared: Array = tag_info.get("params", [])
	for key in declared:
		if key == "target":
			params["target"] = "self"
		elif key == "value":
			if "pct" in tag_id:
				params["value"] = 30.0
			elif "flat" in tag_id:
				params["value"] = 20.0
			else:
				params["value"] = 20.0
		elif key == "duration":
			params["duration"] = 5.0
		elif key == "multiplier":
			params["multiplier"] = 1.5
		elif key == "bonus_uses":
			params["bonus_uses"] = 1
		elif key == "skill_id":
			params["skill_id"] = "test_skill_1"
		elif key == "player_id":
			params["player_id"] = ""
		elif key == "target_id":
			params["target_id"] = ""

	# 传送特殊处理
	if tag_id == "player_teleport":
		params["pos_x"] = 100.0
		params["pos_y"] = 50.0

	# 显形需要先给目标挂隐身
	if tag_id == "player_reveal":
		# 先给B挂隐身
		player_b.turn_on_light("stealthed", 10.0)
		params["target"] = "enemies"

	# 解控需要先给定身
	if tag_id == "player_unroot":
		player_a.turn_on_light("rooted", 10.0)

	return params


func _quick_snapshot(player: CharacterBody2D) -> Dictionary:
	"""快速快照球员关键状态"""
	return {
		"hp": snappedf(player.stamina, 0.1),
		"energy": snappedf(player.spirit_energy, 0.1),
		"atk": snappedf(player._get_effective_value("attack", player.attack_power), 0.1),
		"def": snappedf(player._get_effective_value("defense", player.defense), 0.1),
		"spd": snappedf(player._get_effective_value("speed", player.speed), 0.1),
		"res": snappedf(player._get_effective_value("resilience", player.resilience), 0.1),
		"max_nrg": snappedf(player._get_effective_value("max_energy", player.max_spirit_energy), 0.1),
		"buff_count": player._buffs.size(),
		"lights": player._status_lights.keys().duplicate(),
		"tick_count": player._tick_effects.size(),
		"pos": player.global_position,
		"is_invincible": player.is_status_active("invincible"),
		"is_stunned": player.is_status_active("stunned"),
		"cost_mults": player._skill_cost_mults.size(),
		"cd_mults": player._skill_cd_mults.size(),
		"next_mults": player._next_skill_mults.size(),
		"bonus_uses": player._skill_bonus_uses.size(),
	}


func _has_change(before: Dictionary, after: Dictionary) -> bool:
	"""检查前后快照是否有变化"""
	# 属性变化
	for key in ["hp", "energy", "atk", "def", "spd", "res", "max_nrg"]:
		if absf(float(after.get(key, 0.0)) - float(before.get(key, 0.0))) > 0.05:
			return true
	# buff/灯/tick 变化
	if int(after.get("buff_count", 0)) != int(before.get("buff_count", 0)):
		return true
	if after.get("lights", []) != before.get("lights", []):
		return true
	if int(after.get("tick_count", 0)) != int(before.get("tick_count", 0)):
		return true
	# 元灵系字典变化
	if int(after.get("cost_mults", 0)) != int(before.get("cost_mults", 0)):
		return true
	if int(after.get("cd_mults", 0)) != int(before.get("cd_mults", 0)):
		return true
	if int(after.get("next_mults", 0)) != int(before.get("next_mults", 0)):
		return true
	if int(after.get("bonus_uses", 0)) != int(before.get("bonus_uses", 0)):
		return true
	# 位置变化
	if Vector2(after.get("pos", Vector2.ZERO)) != Vector2(before.get("pos", Vector2.ZERO)):
		return true
	# 布尔变化
	if after.get("is_invincible", false) != before.get("is_invincible", false):
		return true
	if after.get("is_stunned", false) != before.get("is_stunned", false):
		return true
	return false


func _diff_text(before: Dictionary, after: Dictionary) -> String:
	"""生成变化摘要"""
	var parts: Array = []
	var names: Dictionary = {"hp": "体力", "energy": "能量", "atk": "攻击", "def": "防御", "spd": "速度", "res": "韧性", "max_nrg": "最大能量"}
	for key in names:
		var bv: float = float(before.get(key, 0.0))
		var av: float = float(after.get(key, 0.0))
		if absf(av - bv) > 0.05:
			parts.append("%s%.0f" % [names[key], av - bv])
	if int(after.get("buff_count", 0)) > int(before.get("buff_count", 0)):
		parts.append("+buff")
	if after.get("lights", []) != before.get("lights", []):
		var new_lights: Array = []
		for l in after.get("lights", []):
			if l not in before.get("lights", []):
				new_lights.append(_translate_status(str(l)))
		var gone_lights: Array = []
		for l in before.get("lights", []):
			if l not in after.get("lights", []):
				gone_lights.append(_translate_status(str(l)))
		if new_lights.size() > 0:
			parts.append("+灯:" + ",".join(new_lights))
		if gone_lights.size() > 0:
			parts.append("-灯:" + ",".join(gone_lights))
	if int(after.get("tick_count", 0)) > int(before.get("tick_count", 0)):
		parts.append("+持续")
	if int(after.get("cost_mults", 0)) > int(before.get("cost_mults", 0)):
		parts.append("+消耗修正")
	if int(after.get("cd_mults", 0)) > int(before.get("cd_mults", 0)):
		parts.append("+CD修正")
	if int(after.get("next_mults", 0)) > int(before.get("next_mults", 0)):
		parts.append("+倍率卡")
	if int(after.get("bonus_uses", 0)) > int(before.get("bonus_uses", 0)):
		parts.append("+额外次数")
	if Vector2(after.get("pos", Vector2.ZERO)) != Vector2(before.get("pos", Vector2.ZERO)):
		parts.append("传送")
	if after.get("is_invincible", false) != before.get("is_invincible", false):
		parts.append("无敌")
	if after.get("is_stunned", false) != before.get("is_stunned", false):
		parts.append("眩晕")
	return " ".join(parts) if parts.size() > 0 else "无变化"


## ==================== 体力/能量 快捷设置 ====================


func _set_player_hp(player: CharacterBody2D, input: LineEdit) -> void:
	"""手动设置球员体力"""
	if not player or not is_instance_valid(player) or not input:
		return
	var val: float = float(input.text.strip_edges())
	player.stamina = clampf(val, 0.0, player.max_stamina)
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 体力设为 %.0f" % [name, player.stamina])


func _set_player_hp_pct(player: CharacterBody2D, pct: float) -> void:
	"""按百分比设置体力（0.5=扣半, 1.0=满）"""
	if not player or not is_instance_valid(player):
		return
	player.stamina = player.max_stamina * clampf(pct, 0.0, 1.0)
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 体力→%.0f (%.0f%%)" % [name, player.stamina, pct * 100.0])


func _set_player_nrg(player: CharacterBody2D, input: LineEdit) -> void:
	"""手动设置球员能量"""
	if not player or not is_instance_valid(player) or not input:
		return
	var val: float = float(input.text.strip_edges())
	player.spirit_energy = clampf(val, 0.0, player._get_effective_value("max_energy", player.max_spirit_energy))
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 能量设为 %.0f" % [name, player.spirit_energy])


func _set_player_nrg_pct(player: CharacterBody2D, pct: float) -> void:
	"""按百分比设置能量（0.5=扣半, 1.0=满）"""
	if not player or not is_instance_valid(player):
		return
	player.spirit_energy = player._get_effective_value("max_energy", player.max_spirit_energy) * clampf(pct, 0.0, 1.0)
	var name: String = "A" if player == player_a else "B"
	_add_log("球员%s 能量→%.0f (%.0f%%)" % [name, player.spirit_energy, pct * 100.0])
