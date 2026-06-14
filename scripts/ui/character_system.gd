extends Control
## 角色系统界面 - 展示所有球员的详细属性
## 布局：左侧圆形头像列表 | 右侧选中球员详情面板

signal closed()

# 元素颜色映射
const ELEMENT_COLORS: Dictionary = {
	"金刚": Color(0.85, 0.75, 0.3),
	"梦幻": Color(0.7, 0.5, 0.9),
	"草木": Color(0.3, 0.8, 0.3),
	"雷火": Color(1.0, 0.4, 0.2),
	"冰雪": Color(0.4, 0.8, 1.0),
	"大地": Color(0.7, 0.55, 0.35),
}

# 属性条颜色
const STAT_COLORS: Dictionary = {
	"stamina": Color(0.9, 0.2, 0.2),    # 红
	"defense": Color(0.9, 0.75, 0.1),   # 黄
	"speed": Color(0.2, 0.5, 0.95),     # 蓝
	"attack": Color(0.65, 0.65, 0.65),     # 黑（深灰，深色背景可见）
	"resilience": Color(0.55, 0.55, 0.55), # 灰
	"defense_factor": Color(0.6, 0.8, 0.3), # 绿
	"ball_speed": Color(0.6, 0.4, 0.2),    # 棕色
}

const STAT_LABELS: Dictionary = {
	"stamina": "体力",
	"defense": "防御",
	"speed": "速度",
	"attack": "攻击",
	"resilience": "韧性",
	"defense_factor": "防御因子",
	"ball_speed": "发球球速",
}

# 属性最大值（用于条形图比例）
const STAT_MAX: float = 100.0

# === 右侧详情面板排版规范常量 === === 添加新属性时只需修改内容，不需要修改位置计算 ===
const PANEL_X: float = 370.0
const PANEL_Y: float = 90.0
const PANEL_WIDTH: float = 1070.0
const PANEL_HEIGHT: float = 700.0
const PANEL_VISIBLE_HEIGHT: float = 625.0  # 可见高度（启用滚动）

const CONTENT_X: float = 370.0
const NAME_Y: float = 90.0
const DESC_Y: float = 130.0
const STAT_Y_START: float = 175.0
const STAT_SPACING: float = 44.0
const STAT_BAR_X: float = 440.0
const STAT_BAR_WIDTH: float = 350.0
const STAT_BAR_HEIGHT: float = 18.0
const STAT_VAL_X: float = 800.0
const SEP_AFTER_STATS: float = 15.0  # 分隔线距离最后一条属性条的间距
const TALENT_TITLE_AFTER_SEP: float = 15.0
const TALENT_DESC_AFTER_TITLE: float = 27.0
const SPIRIT_AFTER_DESC: float = 43.0
const ULTIMATE_AFTER_SPIRIT: float = 35.0

var characters_data: Array = []
var selected_index: int = 0

# 属性键数组（添加新属性时只需修改这里）
var stat_keys: Array[String] = ["stamina", "defense", "speed", "attack", "resilience", "defense_factor", "ball_speed"]

# 左侧列表节点引用
var avatar_list: VBoxContainer
var avatar_buttons: Array[Button] = []

# 右侧面板节点引用
var detail_panel: Panel
var name_label: Label
var desc_label: Label
var stat_bars: Dictionary = {}  # {stat_key: {bar: ProgressBar, val_label: Label}}
var talent_title: Label
var talent_desc: Label
var spirit_label: Label
var ultimate_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_data()
	_build_ui()
	_select_character(0)


func _load_data() -> void:
	var file := FileAccess.open("res://data/characters/characters.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		if err == OK:
			characters_data = json.data
		file.close()
	if characters_data.is_empty():
		push_error("[CharacterSystem] 角色数据加载失败")


func _build_ui() -> void:
	# 全屏半透明背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12, 0.95)
	add_child(bg)

	# 标题栏
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 15)
	title_bar.size = Vector2(1440, 45)
	add_child(title_bar)

	var title := Label.new()
	title.text = "角色系统"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	title.custom_minimum_size = Vector2(1300, 45)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(50, 45)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(_on_close)
	title_bar.add_child(close_btn)

	# === 左侧头像列表 ===
	var left_bg := Panel.new()
	left_bg.position = Vector2(40, 75)
	left_bg.size = Vector2(260, 700)
	add_child(left_bg)

	avatar_list = VBoxContainer.new()
	avatar_list.position = Vector2(50, 80)
	avatar_list.size = Vector2(240, 690)
	avatar_list.add_theme_constant_override("separation", 6)
	add_child(avatar_list)

	var list_title := Label.new()
	list_title.text = "— 球员列表 —"
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_title.custom_minimum_size = Vector2(240, 28)
	list_title.add_theme_font_size_override("font_size", 16)
	list_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	avatar_list.add_child(list_title)

	for i in range(characters_data.size()):
		var char_data: Dictionary = characters_data[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(240, 90)
		_build_avatar_button(btn, char_data, i)
		btn.pressed.connect(_select_character.bind(i))
		avatar_list.add_child(btn)
		avatar_buttons.append(btn)

	# === 右侧详情面板 === === 排版规范（添加新属性时只需修改类成员 stat_keys 数组） ===
	
	# === 创建滚动容器 ===
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(PANEL_X, PANEL_Y)
	scroll.size = Vector2(PANEL_WIDTH, PANEL_VISIBLE_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	
	# 计算内容总高度
	var stats_height: float = stat_keys.size() * STAT_SPACING
	var content_height: float = (
		NAME_Y +
		stats_height +
		SEP_AFTER_STATS +
		TALENT_TITLE_AFTER_SEP +
		TALENT_DESC_AFTER_TITLE +
		SPIRIT_AFTER_DESC +
		ULTIMATE_AFTER_SPIRIT +
		50.0  # 底部留白
	)
	
	var content := Control.new()
	content.custom_minimum_size = Vector2(PANEL_WIDTH, max(content_height, PANEL_VISIBLE_HEIGHT))
	scroll.add_child(content)
	
	# === 在content内添加所有元素 ===
	
	# 球员名称
	name_label = Label.new()
	name_label.position = Vector2(0, 0)
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(name_label)
	
	# 描述
	desc_label = Label.new()
	desc_label.position = Vector2(0, DESC_Y - NAME_Y)
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	content.add_child(desc_label)
	
	# 属性条
	for idx in range(stat_keys.size()):
		var key: String = stat_keys[idx]
		var y: float = (STAT_Y_START - NAME_Y) + idx * STAT_SPACING

		# 属性名标签
		var stat_name := Label.new()
		stat_name.text = STAT_LABELS[key]
		stat_name.position = Vector2(0, y)
		stat_name.size = Vector2(60, 22)
		stat_name.add_theme_font_size_override("font_size", 16)
		stat_name.add_theme_color_override("font_color", STAT_COLORS[key])
		content.add_child(stat_name)

		# 属性条背景
		var bar_bg := ColorRect.new()
		bar_bg.position = Vector2(STAT_BAR_X - PANEL_X, y + 2)
		bar_bg.size = Vector2(STAT_BAR_WIDTH, STAT_BAR_HEIGHT)
		bar_bg.color = Color(0.2, 0.2, 0.25)
		content.add_child(bar_bg)

		# 属性条填充
		var bar_fill := ColorRect.new()
		bar_fill.position = Vector2(STAT_BAR_X - PANEL_X, y + 2)
		bar_fill.size = Vector2(0, STAT_BAR_HEIGHT)
		bar_fill.color = STAT_COLORS[key]
		content.add_child(bar_fill)

		# 数值标签
		var val_label := Label.new()
		val_label.position = Vector2(STAT_VAL_X - PANEL_X, y)
		val_label.size = Vector2(60, 22)
		val_label.add_theme_font_size_override("font_size", 16)
		val_label.add_theme_color_override("font_color", STAT_COLORS[key])
		content.add_child(val_label)

		stat_bars[key] = {
			"fill": bar_fill,
			"val_label": val_label,
			"bg": bar_bg,
		}
	
	# 计算分隔线位置
	var sep_y: float = (STAT_Y_START - NAME_Y) + (stat_keys.size() - 1) * STAT_SPACING + 30.0
	
	# 分隔线
	var sep := ColorRect.new()
	sep.position = Vector2(0, sep_y)
	sep.size = Vector2(480, 1)
	sep.color = Color(0.4, 0.4, 0.45)
	content.add_child(sep)
	
	# 天赋标题
	talent_title = Label.new()
	talent_title.position = Vector2(0, sep_y + TALENT_TITLE_AFTER_SEP)
	talent_title.add_theme_font_size_override("font_size", 17)
	talent_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	content.add_child(talent_title)

	# 天赋描述
	talent_desc = Label.new()
	talent_desc.position = Vector2(0, sep_y + TALENT_TITLE_AFTER_SEP + TALENT_DESC_AFTER_TITLE)
	talent_desc.add_theme_font_size_override("font_size", 14)
	talent_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	talent_desc.size = Vector2(480, 20)
	content.add_child(talent_desc)

	# 元灵偏好
	spirit_label = Label.new()
	spirit_label.position = Vector2(0, sep_y + TALENT_TITLE_AFTER_SEP + TALENT_DESC_AFTER_TITLE + SPIRIT_AFTER_DESC)
	spirit_label.add_theme_font_size_override("font_size", 17)
	content.add_child(spirit_label)

	# 大招
	ultimate_label = Label.new()
	ultimate_label.position = Vector2(0, sep_y + TALENT_TITLE_AFTER_SEP + TALENT_DESC_AFTER_TITLE + SPIRIT_AFTER_DESC + ULTIMATE_AFTER_SPIRIT)
	ultimate_label.add_theme_font_size_override("font_size", 17)
	ultimate_label.add_theme_color_override("font_color", Color(1, 0.5, 0.2))
	content.add_child(ultimate_label)

	# 右侧圆形大头像占位（放在滚动容器外，固定位置）
	_build_large_avatar_placeholder()


func _build_avatar_button(btn: Button, char_data: Dictionary, index: int) -> void:
	"""构建左侧单个头像按钮"""
	# 用HBoxContainer布局：圆形头像 + 球员名
	# Button本身不支持复杂子节点，改用Panel+按钮模拟
	# 这里直接用按钮文字显示
	var spirit: String = char_data.get("spirit_preference", "")
	var spirit_color: Color = ELEMENT_COLORS.get(spirit, Color.WHITE)
	btn.text = "  %s\n  %s" % [char_data.get("name", "?"), spirit]
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", spirit_color)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT


func _build_large_avatar_placeholder() -> void:
	"""右侧面板上方圆形大头像占位区域"""
	# 大圆形背景（元素颜色）
	# 在 _select_character 中动态更新颜色
	var avatar_circle := ColorRect.new()
	avatar_circle.name = "LargeAvatarBG"
	avatar_circle.position = Vector2(1150, 95)
	avatar_circle.size = Vector2(120, 120)
	avatar_circle.color = Color(0.3, 0.3, 0.35)
	add_child(avatar_circle)

	# 大圆形内文字（球员首字）
	var avatar_char := Label.new()
	avatar_char.name = "LargeAvatarChar"
	avatar_char.position = Vector2(1150, 95)
	avatar_char.size = Vector2(120, 120)
	avatar_char.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_char.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_char.add_theme_font_size_override("font_size", 48)
	avatar_char.add_theme_color_override("font_color", Color.WHITE)
	add_child(avatar_char)

	# 大头像下方球员名
	var avatar_name := Label.new()
	avatar_name.name = "LargeAvatarName"
	avatar_name.position = Vector2(1150, 225)
	avatar_name.size = Vector2(120, 25)
	avatar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_name.add_theme_font_size_override("font_size", 14)
	avatar_name.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(avatar_name)


func _select_character(index: int) -> void:
	"""选中某个球员，更新右侧面板"""
	if index < 0 or index >= characters_data.size():
		return
	selected_index = index
	var data: Dictionary = characters_data[index]

	# 更新左侧选中高亮
	for i in range(avatar_buttons.size()):
		if i == index:
			avatar_buttons[i].add_theme_color_override("font_hover_color", Color.WHITE)
			avatar_buttons[i].modulate = Color(1.2, 1.2, 1.2)
		else:
			avatar_buttons[i].modulate = Color(0.7, 0.7, 0.7)

	# 球员名称
	name_label.text = data.get("name", "")

	# 描述
	desc_label.text = data.get("description", "")

	# 属性条（使用数组stat_keys）
	for key in stat_keys:
		var val: float = float(data.get(key, 0))
		var info: Dictionary = stat_bars[key]
		var fill: ColorRect = info["fill"]
		var label: Label = info["val_label"]
		# 防御因子范围0.1~0.2,按0.25算比例；发球球速范围300~600
		var max_val: float
		if key == "defense_factor":
			max_val = 0.25
		elif key == "ball_speed":
			max_val = 600.0
		else:
			max_val = STAT_MAX
		var ratio: float = clampf(val / max_val, 0.0, 1.0)
		fill.size = Vector2(STAT_BAR_WIDTH * ratio, STAT_BAR_HEIGHT)
		if key == "defense_factor":
			label.text = "%.2f" % val
		else:
			label.text = str(int(val))

	# 天赋
	talent_title.text = "天赋: %s" % data.get("talent_name", "")
	talent_desc.text = data.get("talent_desc", "")

	# 元灵偏好
	var spirit: String = data.get("spirit_preference", "")
	var spirit_color: Color = ELEMENT_COLORS.get(spirit, Color.WHITE)
	spirit_label.text = "元灵偏好: %s" % spirit
	spirit_label.add_theme_color_override("font_color", spirit_color)

	# 大招
	ultimate_label.text = "大招: %s" % data.get("ultimate_skill", "")

	# 大头像更新
	var large_bg := get_node_or_null("LargeAvatarBG")
	if large_bg:
		large_bg.color = Color(spirit_color.r * 0.4, spirit_color.g * 0.4, spirit_color.b * 0.4, 1.0)
	var large_char := get_node_or_null("LargeAvatarChar")
	if large_char:
		var display: String = str(data.get("name", "?"))
		large_char.text = display.substr(0, 1)
	var large_name := get_node_or_null("LargeAvatarName")
	if large_name:
		large_name.text = str(data.get("name", ""))


func _on_close() -> void:
	closed.emit()
	queue_free()
