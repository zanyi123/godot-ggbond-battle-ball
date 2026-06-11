## 场地标签测试界面
## 独立测试场景，用于测试场地障碍物标签
## 功能：选角色 → 两个球员（攻击+障碍） → 切换控制 → 测试障碍物

extends Node2D

## ==================== 场地常量 ====================

const FIELD_WIDTH: float = 1300.0
const FIELD_HEIGHT: float = 780.0
const FIELD_COLOR: Color = Color(0.15, 0.25, 0.15)

## ==================== 节点引用 ====================

var field_bg: ColorRect
var ball_node: Area2D
var player_attacker: CharacterBody2D
var player_defender: CharacterBody2D
var obstacle_mgr: Node
var field_physics_mgr: Node
var ui_layer: CanvasLayer
var hud: Control

## ==================== 状态 ====================

enum Phase {
	SELECT_CHARS,  # 选角色
	PLAYING,       # 对战中
}

var current_phase: int = Phase.SELECT_CHARS
var controlled_player: CharacterBody2D  # 当前控制的球员

## 选角色数据
var all_characters: Array = []
var attacker_index: int = 0
var defender_index: int = 1

## 技能参数（默认值，可在界面调整）
var skill_params: Dictionary = {
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
	"mouse_ops": 3,
	"element": "金刚",
	"element_color": Color(0.85, 0.75, 0.3),
}

## 清除技能参数
var clear_params: Dictionary = {
	"clear_count": 2,
	"mouse_ops": 2,
}


## ==================== 初始化 ====================

func _ready() -> void:
	all_characters = _load_characters()
	_create_field()
	_create_ui()
	_create_systems()
	print("[FieldTest] 测试界面已加载，共" + str(all_characters.size()) + "个角色")


func _load_characters() -> Array:
	"""加载角色数据"""
	if not DataManager:
		return []
	var result: Array = []
	# DataManager.characters 是公开数组
	if DataManager and DataManager.characters.size() > 0:
		return DataManager.characters.duplicate()
	# 备用：直接读取文件
	var path: String = "res://data/characters/characters.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_text) == OK:
				if json.data is Array:
					return json.data
	return result


## ==================== 创建场地 ====================

func _create_field() -> void:
	"""创建场地背景和边界墙"""
	# 背景
	field_bg = ColorRect.new()
	field_bg.size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	field_bg.position = Vector2(-FIELD_WIDTH / 2.0, -FIELD_HEIGHT / 2.0)
	field_bg.color = FIELD_COLOR
	# 圆角
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD_COLOR
	style.set_corner_radius_all(10)
	style.border_color = Color(0.4, 0.6, 0.4)
	style.border_width_bottom = 3
	style.border_width_top = 3
	style.border_width_left = 3
	style.border_width_right = 3
	field_bg.add_theme_stylebox_override("normal", style)
	add_child(field_bg)

	# 中线
	var mid_line := Line2D.new()
	mid_line.add_point(Vector2(0, -FIELD_HEIGHT / 2.0))
	mid_line.add_point(Vector2(0, FIELD_HEIGHT / 2.0))
	mid_line.default_color = Color(0.3, 0.5, 0.3, 0.5)
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
	"""创建边界墙"""
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
	"""创建物理和障碍物管理器"""
	# 场地物理管理器
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


## ==================== 创建UI ====================

func _create_ui() -> void:
	"""创建UI层"""
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	hud = Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(hud)

	_show_select_screen()


## ==================== 选角色界面 ====================

func _show_select_screen() -> void:
	"""显示选角色界面"""
	_clear_hud()
	current_phase = Phase.SELECT_CHARS

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(overlay)

	# 标题
	var title := Label.new()
	title.text = "场地标签测试 - 选择角色"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(420, 40)
	title.size = Vector2(600, 40)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	hud.add_child(title)

	# 攻击球员选择
	_create_char_selector("攻击球员", 100, 120, attacker_index, true)
	# 障碍球员选择
	_create_char_selector("障碍球员", 720, 120, defender_index, false)

	# 技能参数面板
	_create_skill_param_panel()

	# 开始按钮
	var start_btn := Button.new()
	start_btn.text = "开始测试"
	start_btn.position = Vector2(570, 680)
	start_btn.size = Vector2(300, 50)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(_on_start_test)
	hud.add_child(start_btn)

	# 提示
	var tip := Label.new()
	tip.text = "Tab=切换控制球员 | F1=放置障碍 | F2=清除障碍 | F5=重置 | 鼠标左键=发球"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.position = Vector2(250, 740)
	tip.size = Vector2(940, 30)
	tip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hud.add_child(tip)


func _create_char_selector(label_text: String, x: float, y: float, current_idx: int, is_attacker: bool) -> void:
	"""创建角色选择器"""
	# 标签
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(x, y)
	label.size = Vector2(440, 30)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hud.add_child(label)

	# 左箭头
	var left_btn := Button.new()
	left_btn.text = "◀"
	left_btn.position = Vector2(x, y + 40)
	left_btn.size = Vector2(40, 40)
	left_btn.pressed.connect(func(): _change_char_index(is_attacker, -1))
	hud.add_child(left_btn)

	# 角色名
	var name_label := Label.new()
	name_label.name = "CharName_" + label_text
	name_label.text = _get_char_name(current_idx)
	name_label.position = Vector2(x + 50, y + 40)
	name_label.size = Vector2(300, 40)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(name_label)

	# 右箭头
	var right_btn := Button.new()
	right_btn.text = "▶"
	right_btn.position = Vector2(x + 360, y + 40)
	right_btn.size = Vector2(40, 40)
	right_btn.pressed.connect(func(): _change_char_index(is_attacker, 1))
	hud.add_child(right_btn)

	# 属性显示
	var stats_label := Label.new()
	stats_label.name = "CharStats_" + label_text
	stats_label.text = _get_char_stats(current_idx)
	stats_label.position = Vector2(x + 20, y + 90)
	stats_label.size = Vector2(400, 100)
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(stats_label)


func _change_char_index(is_attacker: bool, delta: int) -> void:
	"""切换角色索引"""
	if is_attacker:
		attacker_index = wrapi(attacker_index + delta, 0, all_characters.size())
		_update_selector_label("攻击球员", attacker_index)
	else:
		defender_index = wrapi(defender_index + delta, 0, all_characters.size())
		_update_selector_label("障碍球员", defender_index)


func _update_selector_label(prefix: String, idx: int) -> void:
	"""更新选择器标签"""
	var name_node = hud.get_node_or_null("CharName_" + prefix)
	if name_node:
		name_node.text = _get_char_name(idx)
	var stats_node = hud.get_node_or_null("CharStats_" + prefix)
	if stats_node:
		stats_node.text = _get_char_stats(idx)


func _get_char_name(idx: int) -> String:
	"""获取角色名"""
	if idx >= 0 and idx < all_characters.size():
		return str(all_characters[idx].get("name", "未知"))
	return "无"


func _get_char_stats(idx: int) -> String:
	"""获取角色属性文本"""
	if idx >= 0 and idx < all_characters.size():
		var c: Dictionary = all_characters[idx]
		var text: String = ""
		text += "攻击: " + str(snapped(c.get("attack", 0.0), 1.0))
		text += "  防御: " + str(snapped(c.get("defense", 0.0), 1.0))
		text += "  速度: " + str(snapped(c.get("speed", 0.0), 1.0))
		text += "\n"
		text += "韧性: " + str(snapped(c.get("resilience", 0.0), 1.0))
		text += "  体力: " + str(snapped(c.get("stamina", 0.0), 1.0))
		text += "  元灵: " + str(c.get("spirit_preference", "无"))
		return text
	return ""


## ==================== 技能参数面板 ====================

func _create_skill_param_panel() -> void:
	"""创建技能参数调整面板"""
	var panel_x: float = 100.0
	var panel_y: float = 380.0

	var title := Label.new()
	title.text = "障碍物技能参数（测试前调整）"
	title.position = Vector2(panel_x, panel_y - 30)
	title.size = Vector2(500, 25)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	hud.add_child(title)

	# 形状下拉选择
	var shape_label := Label.new()
	shape_label.text = "形状:"
	shape_label.position = Vector2(panel_x, panel_y)
	shape_label.size = Vector2(50, 22)
	shape_label.add_theme_font_size_override("font_size", 14)
	shape_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(shape_label)

	var shape_option := OptionButton.new()
	shape_option.name = "ShapeOption"
	shape_option.position = Vector2(panel_x + 55, panel_y)
	shape_option.size = Vector2(130, 24)
	shape_option.add_theme_font_size_override("font_size", 14)
	shape_option.add_item("矩形", 0)
	shape_option.add_item("圆形", 1)
	shape_option.add_item("月牙", 2)
	var init_shape: String = str(skill_params.get("shape", "rect"))
	match init_shape:
		"circle": shape_option.selected = 1
		"crescent": shape_option.selected = 2
		_: shape_option.selected = 0
	shape_option.item_selected.connect(_on_shape_option_selected)
	hud.add_child(shape_option)

	# 所有参数行（形状专属 + 通用），一次创建
	var all_params_config: Array = [
		["矩形宽度", "width", "float", "rect"],
		["矩形高度", "height", "float", "rect"],
		["半径", "radius", "float", "circle"],
		["月牙弧度角", "arc_angle", "float", "crescent"],
		["防御生命值", "hp", "float", ""],
		["攻击消耗速率(/s)", "attack_consume_rate", "float", ""],
		["球速消耗速率(px/s)", "speed_consume_rate", "float", ""],
		["最大数量", "max_count", "float", ""],
		["持续秒数", "duration", "float", ""],
		["鼠标操作次数", "mouse_ops", "float", ""],
		["元素(金刚/大地/雷火/冰雪/草木/梦幻)", "element", "string", ""],
	]

	var row_offset: int = 1
	var visible_row: int = 0
	for i in range(all_params_config.size()):
		var param_label_text: String = all_params_config[i][0]
		var param_key: String = all_params_config[i][1]
		var param_type: String = all_params_config[i][2]
		var param_shape: String = all_params_config[i][3]  # ""=通用, "rect"/"circle"/"crescent"=专属

		# 标签
		var lbl := Label.new()
		lbl.name = "Label_" + param_key
		lbl.text = param_label_text
		lbl.position = Vector2(panel_x, panel_y + (row_offset + visible_row) * 24)
		lbl.size = Vector2(320, 22)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		# 形状专属参数：非当前形状则隐藏
		if param_shape != "" and param_shape != init_shape:
			lbl.visible = false
		hud.add_child(lbl)

		# 输入框
		var input := LineEdit.new()
		input.name = "Param_" + param_key
		var current_val = skill_params.get(param_key, "")
		if param_type == "string":
			input.text = str(current_val)
		else:
			input.text = str(snappedf(float(current_val), 0.01))
		input.position = Vector2(panel_x + 330, panel_y + (row_offset + visible_row) * 24)
		input.size = Vector2(120, 22)
		input.add_theme_font_size_override("font_size", 14)
		if param_shape != "" and param_shape != init_shape:
			input.visible = false
		hud.add_child(input)

		if param_shape == "" or param_shape == init_shape:
			visible_row += 1

	# 清除技能参数
	var clear_title := Label.new()
	clear_title.text = "清除技能参数"
	clear_title.position = Vector2(650, panel_y - 30)
	clear_title.size = Vector2(300, 25)
	clear_title.add_theme_font_size_override("font_size", 18)
	clear_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	hud.add_child(clear_title)

	var clear_display: Array = [
		["清除数量", "clear_count", "float"],
		["鼠标操作次数", "mouse_ops", "float"],
	]

	for i in range(clear_display.size()):
		var param_label_text: String = clear_display[i][0]
		var param_key: String = clear_display[i][1]

		var row_y: float = panel_y + i * 24

		var lbl := Label.new()
		lbl.text = param_label_text
		lbl.position = Vector2(650, row_y)
		lbl.size = Vector2(200, 22)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		hud.add_child(lbl)

		var input := LineEdit.new()
		input.name = "ClearParam_" + param_key
		input.text = str(clear_params.get(param_key, 1))
		input.position = Vector2(860, row_y)
		input.size = Vector2(120, 22)
		input.add_theme_font_size_override("font_size", 14)
		hud.add_child(input)


func _on_shape_option_selected(index: int) -> void:
	"""形状下拉切换：隐藏/显示对应参数行"""
	var shapes: Array = ["rect", "circle", "crescent"]
	var new_shape: String = shapes[index]
	skill_params["shape"] = new_shape

	# 根据形状决定哪些行可见
	var shape_keys: Dictionary = {
		"rect": ["width", "height"],
		"circle": ["radius"],
		"crescent": ["radius", "arc_angle"],
	}
	var visible_keys: Array = shape_keys.get(new_shape, [])

	# 重新布局：先隐藏所有形状专属行
	var shape_only_keys: Array = ["width", "height", "radius", "arc_angle"]
	for key in shape_only_keys:
		var lbl = hud.get_node_or_null("Label_" + key)
		var inp = hud.get_node_or_null("Param_" + key)
		if key in visible_keys:
			if lbl: lbl.visible = true
			if inp: inp.visible = true
		else:
			if lbl: lbl.visible = false
			if inp: inp.visible = false

	# 重新计算可见行的 Y 坐标
	var panel_y: float = 380.0
	var row_offset: int = 1
	var all_keys: Array = ["width", "height", "radius", "arc_angle", "hp", "attack_consume_rate", "speed_consume_rate", "max_count", "duration", "mouse_ops", "element"]
	for key in all_keys:
		var lbl = hud.get_node_or_null("Label_" + key)
		var inp = hud.get_node_or_null("Param_" + key)
		if lbl and lbl.visible:
			lbl.position.y = panel_y + row_offset * 24
			row_offset += 1
		if inp and inp.visible:
			inp.position.y = lbl.position.y if lbl else panel_y + (row_offset - 1) * 24


func _read_params_from_ui() -> void:
	"""从UI读取参数"""
	var string_keys: Array = ["shape", "element"]
	var float_keys: Array = ["width", "height", "radius", "arc_angle", "hp", "attack_consume_rate", "speed_consume_rate", "max_count", "duration", "mouse_ops"]

	for key in string_keys:
		var input = hud.get_node_or_null("Param_" + key)
		if input and input.text != "":
			skill_params[key] = input.text

	for key in float_keys:
		var input = hud.get_node_or_null("Param_" + key)
		if input and input.text != "":
			skill_params[key] = float(input.text)

	# 元素颜色
	var element: String = str(skill_params.get("element", "金刚"))
	skill_params["element_color"] = _get_element_color(element)

	# source_skill
	skill_params["source_skill"] = "test_obstacle_skill"

	# 清除参数
	var clear_count_input = hud.get_node_or_null("ClearParam_clear_count")
	if clear_count_input and clear_count_input.text != "":
		clear_params["clear_count"] = int(float(clear_count_input.text))
	var mouse_ops_input = hud.get_node_or_null("ClearParam_mouse_ops")
	if mouse_ops_input and mouse_ops_input.text != "":
		clear_params["mouse_ops"] = int(float(mouse_ops_input.text))


func _get_element_color(element: String) -> Color:
	"""获取元素颜色"""
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(1.0, 1.0, 0.5))


## ==================== 开始测试 ====================

func _on_start_test() -> void:
	"""开始测试"""
	_read_params_from_ui()
	_clear_hud()
	current_phase = Phase.PLAYING

	_create_players()
	_create_ball()
	_create_play_hud()

	print("[FieldTest] 测试开始!")
	print("[FieldTest] 攻击: " + _get_char_name(attacker_index))
	print("[FieldTest] 障碍: " + _get_char_name(defender_index))


func _create_players() -> void:
	"""创建两个球员"""
	# 攻击球员（左侧）
	player_attacker = _create_player_node(
		all_characters[attacker_index],
		"a",
		true,
		Vector2(-300.0, 0.0)
	)
	add_child(player_attacker)
	controlled_player = player_attacker

	# 球员加入 players 组（球落地/出界后需要查找球员）
	player_attacker.add_to_group("players")
	player_defender = _create_player_node(
		all_characters[defender_index],
		"b",
		false,
		Vector2(300.0, 0.0)
	)
	add_child(player_defender)

	# 球员加入 players 组
	player_defender.add_to_group("players")


func _create_player_node(char_data: Dictionary, team_name: String, controlled: bool, start_pos: Vector2) -> CharacterBody2D:
	"""创建球员节点"""
	var player_script := load("res://scripts/battle/player.gd")
	var player := CharacterBody2D.new()
	player.set_script(player_script)
	player.character_id = char_data.get("id", "")
	player.team = team_name
	player.is_player_controlled = false  # 由本脚本控制
	player.global_position = start_pos
	player.initialize(char_data.get("id", ""), team_name, false)
	# 手动设置属性（因为 initialize 可能不完整）
	player.max_stamina = char_data.get("stamina", 100.0)
	player.stamina = player.max_stamina
	player.attack_power = char_data.get("attack", 50.0)
	player.defense = char_data.get("defense", 50.0)
	var raw_speed: float = char_data.get("speed", 50.0)
	player.speed = raw_speed * 3.25
	player.resilience = char_data.get("resilience", 50.0)
	player.defense_factor = char_data.get("defense_factor", 0.15)
	return player


func _create_ball() -> void:
	"""创建球"""
	var ball_script := load("res://scripts/battle/ball.gd")
	ball_node = Area2D.new()
	ball_node.set_script(ball_script)
	ball_node.name = "Ball"
	ball_node.add_to_group("ball")
	add_child(ball_node)
	# 球初始跟随攻击球员
	ball_node.owner_player = player_attacker
	player_attacker.is_carrying_ball = true
	player_attacker.set_carrying_ball(true)


## ==================== 游戏HUD ====================

func _create_play_hud() -> void:
	"""创建游戏内HUD"""
	# 攻击球员信息
	_create_player_hud("攻击", player_attacker, 20, 20, Color(0.3, 0.6, 1.0))
	# 障碍球员信息
	_create_player_hud("障碍", player_defender, 20, 100, Color(1.0, 0.5, 0.3))

	# 当前控制提示
	var control_label := Label.new()
	control_label.name = "ControlLabel"
	control_label.text = "当前控制: 攻击球员"
	control_label.position = Vector2(400, 10)
	control_label.size = Vector2(300, 25)
	control_label.add_theme_font_size_override("font_size", 18)
	control_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
	hud.add_child(control_label)

	# 操作提示
	var tips := Label.new()
	tips.text = "Tab=切换控制 | F1=放置障碍 | F2=清除障碍 | 左键=发球 | F5=重置"
	tips.position = Vector2(200, 760)
	tips.size = Vector2(1000, 25)
	tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.add_theme_font_size_override("font_size", 15)
	tips.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hud.add_child(tips)

	# 障碍物数量
	var obs_label := Label.new()
	obs_label.name = "ObstacleCount"
	obs_label.text = "场上障碍物: 0"
	obs_label.position = Vector2(1100, 10)
	obs_label.size = Vector2(200, 25)
	obs_label.add_theme_font_size_override("font_size", 16)
	obs_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(obs_label)

	# 摩擦系数
	var friction_label := Label.new()
	friction_label.name = "FrictionLabel"
	friction_label.text = "摩擦系数: 1.00"
	friction_label.position = Vector2(1100, 35)
	friction_label.size = Vector2(200, 25)
	friction_label.add_theme_font_size_override("font_size", 16)
	friction_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(friction_label)


func _create_player_hud(prefix: String, player: CharacterBody2D, x: float, y: float, color: Color) -> void:
	"""创建球员HUD"""
	var label_name := "HUD_" + prefix

	# 名称
	var name_lbl := Label.new()
	name_lbl.name = label_name + "_Name"
	name_lbl.text = prefix + ": " + str(player.char_data.get("name", "?"))
	name_lbl.position = Vector2(x, y)
	name_lbl.size = Vector2(200, 22)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", color)
	hud.add_child(name_lbl)

	# 体力条
	var bar := ProgressBar.new()
	bar.name = label_name + "_HP"
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.size = Vector2(180, 14)
	bar.position = Vector2(x, y + 24)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.2)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.8, 0.2)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	hud.add_child(bar)

	# 体力数值
	var hp_text := Label.new()
	hp_text.name = label_name + "_HPText"
	hp_text.text = str(int(player.stamina)) + "/" + str(int(player.max_stamina))
	hp_text.position = Vector2(x + 185, y + 22)
	hp_text.size = Vector2(100, 18)
	hp_text.add_theme_font_size_override("font_size", 13)
	hp_text.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hud.add_child(hp_text)


## ==================== 帧处理 ====================

func _process(delta: float) -> void:
	if current_phase != Phase.PLAYING:
		return

	_process_controlled_player(delta)
	_update_hud()


func _process_controlled_player(delta: float) -> void:
	"""处理控制的球员移动"""
	if not controlled_player or not is_instance_valid(controlled_player):
		return

	# 球员击退/僵直处理由 player.gd 自身的 _physics_process 完成
	# 这里只处理移动输入
	var move_speed: float = controlled_player.speed
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	# 只在非击退非僵直时设置速度
	if controlled_player._knockback_timer <= 0.0 and controlled_player._stagger_timer <= 0.0:
		if input_dir != Vector2.ZERO:
			controlled_player.velocity = input_dir.normalized() * move_speed
		else:
			controlled_player.velocity = Vector2.ZERO


func _update_hud() -> void:
	"""更新HUD"""
	_update_player_hud_values("攻击", player_attacker)
	_update_player_hud_values("障碍", player_defender)

	# 障碍物数量
	var obs_label = hud.get_node_or_null("ObstacleCount")
	if obs_label and obstacle_mgr:
		obs_label.text = "场上障碍物: " + str(obstacle_mgr.get_obstacle_count())

	# 摩擦系数
	var friction_label = hud.get_node_or_null("FrictionLabel")
	if friction_label and field_physics_mgr and field_physics_mgr.has_method("get_friction"):
		var mu: float = field_physics_mgr.get_friction()
		friction_label.text = "摩擦系数: " + str(snapped(mu, 0.01))


func _update_player_hud_values(prefix: String, player: CharacterBody2D) -> void:
	"""更新球员HUD数值"""
	var label_name := "HUD_" + prefix

	var bar = hud.get_node_or_null(label_name + "_HP")
	if bar and player and is_instance_valid(player):
		var ratio: float = (player.stamina / player.max_stamina) * 100.0
		bar.value = ratio
		if ratio < 30.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.9, 0.2, 0.2)
			fill.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("fill", fill)
		elif ratio < 60.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(0.9, 0.7, 0.2)
			fill.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("fill", fill)

	var hp_text = hud.get_node_or_null(label_name + "_HPText")
	if hp_text and player and is_instance_valid(player):
		hp_text.text = str(int(player.stamina)) + "/" + str(int(player.max_stamina))


## ==================== 输入处理 ====================

func _input(event: InputEvent) -> void:
	if current_phase != Phase.PLAYING:
		return

	# Tab 切换控制
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_switch_control()

	# F1 放置障碍
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_start_place_obstacle()

	# F2 清除障碍
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_start_clear_obstacle()

	# F5 重置
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_reset_test()

	# 左键发球
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not obstacle_mgr or not obstacle_mgr.is_operating():
			_try_throw_ball()


## ==================== 游戏操作 ====================

func _switch_control() -> void:
	"""切换控制球员"""
	# 不在障碍物操作中才能切换
	if obstacle_mgr and obstacle_mgr.is_operating():
		return

	if controlled_player == player_attacker:
		controlled_player = player_defender
		# 球跟随攻击球员（如果攻击球员持球）
		_switch_ball_ownership()
	else:
		controlled_player = player_attacker
		_switch_ball_ownership()

	var control_label = hud.get_node_or_null("ControlLabel")
	if control_label:
		if controlled_player == player_attacker:
			control_label.text = "当前控制: 攻击球员"
		else:
			control_label.text = "当前控制: 障碍球员"

	print("[FieldTest] 切换控制: " + str(controlled_player.char_data.get("name", "?")))


func _switch_ball_ownership() -> void:
	"""球始终跟随攻击球员"""
	if ball_node and player_attacker and is_instance_valid(player_attacker):
		ball_node.owner_player = player_attacker
		if not player_attacker.is_carrying_ball:
			player_attacker.is_carrying_ball = true
			player_attacker.set_carrying_ball(true)


func _start_place_obstacle() -> void:
	"""F1: 障碍球员放置障碍"""
	if not obstacle_mgr:
		return

	if obstacle_mgr.is_operating():
		obstacle_mgr.cancel_operation()
		return

	# 使用技能参数，传入释放球员位置（月牙朝向用）
	skill_params["caster_position"] = player_defender.global_position
	obstacle_mgr.start_placing(skill_params, int(skill_params.get("mouse_ops", 1)))
	print("[FieldTest] 障碍球员放置障碍 (F1)")


func _start_clear_obstacle() -> void:
	"""F2: 清除障碍"""
	if not obstacle_mgr:
		return

	if obstacle_mgr.is_operating():
		obstacle_mgr.cancel_operation()
		return

	obstacle_mgr.start_clearing(
		int(clear_params.get("clear_count", 1)),
		int(clear_params.get("mouse_ops", 1))
	)
	print("[FieldTest] 清除障碍 (F2)")


func _try_throw_ball() -> void:
	"""左键发球"""
	if not ball_node or controlled_player != player_attacker:
		return

	if not player_attacker.is_carrying_ball:
		return

	# 计算发球方向（朝鼠标方向）
	var mouse_pos: Vector2 = _get_mouse_world_pos()
	var throw_dir: Vector2 = (mouse_pos - player_attacker.global_position).normalized()

	if throw_dir.length() < 0.01:
		throw_dir = Vector2.RIGHT

	# 使用 launch 方法发球（重置飞行距离等）
	ball_node.launch(
		player_attacker.global_position,
		throw_dir,
		player_attacker._get_effective_value("attack", player_attacker.attack_power),
		600.0,
		player_attacker
	)

	player_attacker.is_carrying_ball = false
	player_attacker.set_carrying_ball(false)

	print("[FieldTest] 发球! 方向=" + str(snapped(throw_dir.x, 0.1)) + "," + str(snapped(throw_dir.y, 0.1)))


func _get_mouse_world_pos() -> Vector2:
	"""获取鼠标世界坐标"""
	var viewport = get_viewport()
	if viewport:
		var screen_size: Vector2 = viewport.get_visible_rect().size
		var mouse_screen: Vector2 = viewport.get_mouse_position()
		# 转换为世界坐标（摄像机居中）
		return mouse_screen - screen_size / 2.0
	return Vector2.ZERO


func _reset_test() -> void:
	"""F5: 重置测试"""
	# 清除障碍物
	if obstacle_mgr:
		obstacle_mgr.cancel_operation()
		obstacle_mgr.clear_all_obstacles()

	# 恢复摩擦
	if field_physics_mgr and field_physics_mgr.has_method("restore_all_defaults"):
		field_physics_mgr.restore_all_defaults()

	# 移除球员和球
	if player_attacker and is_instance_valid(player_attacker):
		player_attacker.queue_free()
	if player_defender and is_instance_valid(player_defender):
		player_defender.queue_free()
	if ball_node and is_instance_valid(ball_node):
		ball_node.queue_free()

	player_attacker = null
	player_defender = null
	ball_node = null

	# 回到选角色
	_show_select_screen()
	print("[FieldTest] 测试已重置")


## ==================== 工具方法 ====================

func _clear_hud() -> void:
	"""清空HUD"""
	if hud:
		for child in hud.get_children():
			child.queue_free()
