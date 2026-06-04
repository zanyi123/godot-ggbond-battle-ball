extends Control
## 开发者工具 - 球员管理面板
## 左侧：球员头像列表（滚动）+ 底部新建按钮
## 右侧：详情面板（所有属性用滑块可调）+ 锁定/确认按钮

signal closed()

# 元素颜色
const ELEMENT_COLORS: Dictionary = {
	"金刚": Color(0.85, 0.75, 0.3),
	"梦幻": Color(0.7, 0.5, 0.9),
	"草木": Color(0.3, 0.8, 0.3),
	"雷火": Color(1.0, 0.4, 0.2),
	"冰雪": Color(0.4, 0.8, 1.0),
	"大地": Color(0.7, 0.55, 0.35),
}

# 属性定义
const STAT_DEFS: Array[Dictionary] = [
	{"key": "stamina", "label": "体力", "min": 10.0, "max": 200.0, "step": 1.0, "color": Color(0.9, 0.2, 0.2)},
	{"key": "defense", "label": "防御", "min": 10.0, "max": 200.0, "step": 1.0, "color": Color(0.9, 0.75, 0.1)},
	{"key": "speed", "label": "速度", "min": 10.0, "max": 200.0, "step": 1.0, "color": Color(0.2, 0.5, 0.95)},
	{"key": "attack", "label": "攻击", "min": 5.0, "max": 100.0, "step": 1.0, "color": Color(0.65, 0.65, 0.65)},
	{"key": "resilience", "label": "韧性", "min": 0.0, "max": 100.0, "step": 1.0, "color": Color(0.55, 0.55, 0.55)},
	{"key": "defense_factor", "label": "防御因子", "min": 0.01, "max": 0.50, "step": 0.01, "color": Color(0.6, 0.8, 0.3)},
]

# 字段定义（文本类）
const TEXT_FIELDS: Array[Dictionary] = [
	{"key": "name", "label": "名字", "placeholder": "输入球员名字"},
	{"key": "talent_name", "label": "天赋名称", "placeholder": "输入天赋名称"},
	{"key": "talent_desc", "label": "天赋描述", "placeholder": "输入天赋描述"},
	{"key": "ultimate_skill", "label": "大招名称", "placeholder": "输入大招名称"},
	{"key": "description", "label": "描述", "placeholder": "输入球员描述"},
]

var characters_data: Array = []
var selected_index: int = -1
var is_editing: bool = false
var is_creating: bool = false
var create_data: Dictionary = {}

# UI引用
var avatar_scroll: ScrollContainer
var avatar_list: VBoxContainer
var avatar_buttons: Array[Button] = []
var detail_container: VBoxContainer
var stat_sliders: Dictionary = {}  # {key: HSlider}
var stat_value_labels: Dictionary = {}  # {key: Label}
var text_edits: Dictionary = {}  # {key: LineEdit}
var element_option: OptionButton
var btn_edit: Button
var btn_confirm: Button
var btn_cancel: Button
var btn_back: Button
var name_display: Label
var upload_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	characters_data = DevDataSync.load_characters()
	_build_ui()
	_refresh_list()
	if characters_data.size() > 0:
		_select_character(0)


func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.10, 0.98)
	add_child(bg)

	# 顶部栏
	var top_bar := HBoxContainer.new()
	top_bar.offset_top = 10
	top_bar.offset_bottom = 50
	top_bar.offset_left = 20
	top_bar.offset_right = 1420
	add_child(top_bar)

	btn_back = Button.new()
	btn_back.text = "← 返回"
	btn_back.custom_minimum_size = Vector2(100, 35)
	btn_back.pressed.connect(_on_close)
	top_bar.add_child(btn_back)

	var title := Label.new()
	title.text = "球员管理"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(100, 35)
	top_bar.add_child(spacer)

	# === 左侧面板 ===
	var left_panel := Panel.new()
	left_panel.offset_top = 60
	left_panel.offset_bottom = 780
	left_panel.offset_left = 20
	left_panel.offset_right = 280
	add_child(left_panel)

	var left_title := Label.new()
	left_title.text = "— 球员列表 —"
	left_title.offset_top = 65
	left_title.offset_bottom = 90
	left_title.offset_left = 20
	left_title.offset_right = 280
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_title.add_theme_font_size_override("font_size", 15)
	left_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(left_title)

	avatar_scroll = ScrollContainer.new()
	avatar_scroll.offset_top = 95
	avatar_scroll.offset_bottom = 720
	avatar_scroll.offset_left = 25
	avatar_scroll.offset_right = 275
	avatar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(avatar_scroll)

	avatar_list = VBoxContainer.new()
	avatar_list.custom_minimum_size = Vector2(240, 0)
	avatar_list.add_theme_constant_override("separation", 5)
	avatar_scroll.add_child(avatar_list)

	# 新建按钮（底部）
	var add_btn := Button.new()
	add_btn.text = "+ 新建球员"
	add_btn.offset_top = 730
	add_btn.offset_bottom = 770
	add_btn.offset_left = 30
	add_btn.offset_right = 270
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	add_btn.pressed.connect(_on_create_new)
	add_child(add_btn)

	# === 右侧详情面板 ===
	var right_bg := Panel.new()
	right_bg.offset_top = 60
	right_bg.offset_bottom = 780
	right_bg.offset_left = 300
	right_bg.offset_right = 1420
	add_child(right_bg)

	detail_container = VBoxContainer.new()
	detail_container.offset_top = 70
	detail_container.offset_bottom = 770
	detail_container.offset_left = 320
	detail_container.offset_right = 1400
	detail_container.add_theme_constant_override("separation", 4)
	add_child(detail_container)

	# 球员名称显示
	name_display = Label.new()
	name_display.text = ""
	name_display.add_theme_font_size_override("font_size", 26)
	name_display.add_theme_color_override("font_color", Color.WHITE)
	name_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_display.custom_minimum_size = Vector2(0, 40)
	detail_container.add_child(name_display)

	# 文本字段
	for field in TEXT_FIELDS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)

		var lbl := Label.new()
		lbl.text = field.label + ":"
		lbl.custom_minimum_size = Vector2(90, 28)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(lbl)

		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.placeholder_text = field.placeholder
		edit.editable = false
		edit.add_theme_font_size_override("font_size", 14)
		row.add_child(edit)

		text_edits[field.key] = edit
		detail_container.add_child(row)

	# 元素偏好选择
	var elem_row := HBoxContainer.new()
	elem_row.custom_minimum_size = Vector2(0, 32)

	var elem_lbl := Label.new()
	elem_lbl.text = "元灵偏好:"
	elem_lbl.custom_minimum_size = Vector2(90, 28)
	elem_lbl.add_theme_font_size_override("font_size", 14)
	elem_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	elem_row.add_child(elem_lbl)

	element_option = OptionButton.new()
	element_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for elem in DevDataSync.get_elements():
		element_option.add_item(elem)
	element_option.disabled = true
	elem_row.add_child(element_option)
	detail_container.add_child(elem_row)

	# 分隔线
	var sep1 := HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 10)
	detail_container.add_child(sep1)

	# 属性滑块
	for stat in STAT_DEFS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 35)

		var lbl := Label.new()
		lbl.text = stat.label + ":"
		lbl.custom_minimum_size = Vector2(90, 28)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", stat.color)
		row.add_child(lbl)

		var slider := HSlider.new()
		slider.min_value = stat.min
		slider.max_value = stat.max
		slider.step = stat.step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.editable = false
		slider.value_changed.connect(_on_slider_changed.bind(stat.key))
		row.add_child(slider)
		stat_sliders[stat.key] = slider

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(60, 28)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", stat.color)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		stat_value_labels[stat.key] = val_lbl

		detail_container.add_child(row)

	# 分隔线
	var sep2 := HSeparator.new()
	sep2.custom_minimum_size = Vector2(0, 10)
	detail_container.add_child(sep2)

	# 上传图片按钮（可选）
	upload_btn = Button.new()
	upload_btn.text = "上传球员图片（可选）"
	upload_btn.custom_minimum_size = Vector2(0, 32)
	upload_btn.disabled = true
	upload_btn.pressed.connect(_on_upload_image)
	detail_container.add_child(upload_btn)

	# 操作按钮
	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size = Vector2(0, 45)
	btn_row.add_theme_constant_override("separation", 15)

	btn_edit = Button.new()
	btn_edit.text = "数值修改"
	btn_edit.custom_minimum_size = Vector2(160, 40)
	btn_edit.add_theme_font_size_override("font_size", 16)
	btn_edit.pressed.connect(_on_toggle_edit)
	btn_row.add_child(btn_edit)

	btn_confirm = Button.new()
	btn_confirm.text = "确认修改"
	btn_confirm.custom_minimum_size = Vector2(160, 40)
	btn_confirm.add_theme_font_size_override("font_size", 16)
	btn_confirm.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	btn_confirm.disabled = true
	btn_confirm.pressed.connect(_on_confirm)
	btn_row.add_child(btn_confirm)

	btn_cancel = Button.new()
	btn_cancel.text = "取消"
	btn_cancel.custom_minimum_size = Vector2(100, 40)
	btn_cancel.disabled = true
	btn_cancel.pressed.connect(_on_cancel)
	btn_row.add_child(btn_cancel)

	# 右对齐弹簧
	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer_right)

	detail_container.add_child(btn_row)


func _refresh_list() -> void:
	# 清空旧列表
	for child in avatar_list.get_children():
		child.queue_free()
	avatar_buttons.clear()

	# 重建列表
	for i in range(characters_data.size()):
		var data: Dictionary = characters_data[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(235, 55)
		var spirit: String = data.get("spirit_preference", "")
		var c: Color = ELEMENT_COLORS.get(spirit, Color.WHITE)
		btn.text = "  %s  |  %s" % [data.get("name", "?"), spirit]
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", c)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_character.bind(i))
		avatar_list.add_child(btn)
		avatar_buttons.append(btn)

	# 选中状态高亮
	if selected_index >= 0 and selected_index < avatar_buttons.size():
		avatar_buttons[selected_index].modulate = Color(1.3, 1.3, 1.3)


func _select_character(index: int) -> void:
	if index < 0 or index >= characters_data.size():
		return

	# 如果正在编辑/新建，先取消
	if is_editing or is_creating:
		_on_cancel()

	selected_index = index
	var data: Dictionary = characters_data[index]

	# 高亮选中
	for i in range(avatar_buttons.size()):
		avatar_buttons[i].modulate = Color(0.7, 0.7, 0.7) if i != index else Color(1.3, 1.3, 1.3)

	# 更新右侧面板
	_update_detail_panel(data)


func _update_detail_panel(data: Dictionary) -> void:
	name_display.text = data.get("name", "未命名")
	name_display.add_theme_color_override("font_color", Color.WHITE)

	# 文本字段
	for field in TEXT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			text_edits[key].text = str(data.get(key, ""))

	# 元素选择
	var spirit: String = data.get("spirit_preference", "")
	var elements := DevDataSync.get_elements()
	for i in range(elements.size()):
		if elements[i] == spirit:
			element_option.selected = i
			break

	# 属性滑块
	for stat in STAT_DEFS:
		var key: String = stat.key
		if stat_sliders.has(key):
			var val: float = float(data.get(key, 0))
			stat_sliders[key].value = val
			_update_stat_label(key, val)


func _update_stat_label(key: String, val: float) -> void:
	if key == "defense_factor":
		stat_value_labels[key].text = "%.2f" % val
	else:
		stat_value_labels[key].text = str(int(val))


func _on_slider_changed(val: float, key: String) -> void:
	_update_stat_label(key, val)


func _on_toggle_edit() -> void:
	if is_creating:
		return
	if selected_index < 0:
		return

	is_editing = !is_editing
	_set_editable(is_editing)

	if is_editing:
		btn_edit.text = "编辑中..."
		btn_edit.disabled = true
		btn_confirm.disabled = false
		btn_cancel.disabled = false
	else:
		btn_edit.text = "数值修改"
		btn_edit.disabled = false
		btn_confirm.disabled = true
		btn_cancel.disabled = true


func _set_editable(editable: bool) -> void:
	for key in text_edits:
		text_edits[key].editable = editable
	for key in stat_sliders:
		stat_sliders[key].editable = editable
	element_option.disabled = not editable
	upload_btn.disabled = not editable


func _on_confirm() -> void:
	if is_creating:
		_confirm_create()
		return

	if selected_index < 0:
		return

	# 从UI收集数据
	var data := _collect_data_from_ui()

	# 更新本地数据
	characters_data[selected_index] = data

	# 保存到文件
	DevDataSync.save_characters(characters_data)

	# 刷新UI
	_refresh_list()
	_select_character(selected_index)

	# 退出编辑模式
	is_editing = false
	_set_editable(false)
	btn_edit.text = "数值修改"
	btn_edit.disabled = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true

	print("[DevPlayerPanel] 已保存修改: ", data.get("name", ""))


func _collect_data_from_ui() -> Dictionary:
	var data: Dictionary = {}

	if is_creating:
		data = create_data.duplicate()
	else:
		data = characters_data[selected_index].duplicate()

	# 文本字段
	for field in TEXT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			data[key] = text_edits[key].text

	# 属性滑块
	for stat in STAT_DEFS:
		var key: String = stat.key
		if stat_sliders.has(key):
			if key == "defense_factor":
				data[key] = stat_sliders[key].value
			else:
				data[key] = int(stat_sliders[key].value)

	# 元素偏好
	var elements := DevDataSync.get_elements()
	if element_option.selected >= 0 and element_option.selected < elements.size():
		data["spirit_preference"] = elements[element_option.selected]

	return data


func _on_cancel() -> void:
	is_editing = false
	is_creating = false
	_set_editable(false)
	btn_edit.text = "数值修改"
	btn_edit.disabled = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true

	if selected_index >= 0 and selected_index < characters_data.size():
		_update_detail_panel(characters_data[selected_index])
	else:
		_clear_detail_panel()


func _clear_detail_panel() -> void:
	name_display.text = "请选择球员"
	for key in text_edits:
		text_edits[key].text = ""
	for key in stat_sliders:
		stat_sliders[key].value = 0
		stat_sliders[key].editable = false


func _on_create_new() -> void:
	is_creating = true
	var new_id := DevDataSync.generate_char_id(characters_data)
	create_data = DevDataSync.create_character_template(new_id)

	# 清除选中状态
	selected_index = -1
	for btn in avatar_buttons:
		btn.modulate = Color(0.7, 0.7, 0.7)

	# 填充新模板到面板
	_update_detail_panel(create_data)

	# 进入编辑模式
	_set_editable(true)
	btn_edit.text = "新建中..."
	btn_edit.disabled = true
	btn_confirm.disabled = false
	btn_confirm.text = "确认创建"
	btn_cancel.disabled = false

	name_display.text = "新建球员"
	name_display.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))


func _confirm_create() -> void:
	var data := _collect_data_from_ui()

	# 验证必填字段
	if data.get("name", "").strip_edges() == "":
		print("[DevPlayerPanel] 错误：球员名字不能为空")
		return

	# 添加到数据列表
	characters_data.append(data)

	# 保存到文件
	DevDataSync.save_characters(characters_data)

	# 刷新UI
	is_creating = false
	_refresh_list()
	_select_character(characters_data.size() - 1)

	btn_confirm.text = "确认修改"
	print("[DevPlayerPanel] 已创建新球员: ", data.get("name", ""))


func _on_upload_image() -> void:
	# TODO: 图片上传功能（使用NativeFileDialog）
	print("[DevPlayerPanel] 图片上传功能待实现")


func _on_close() -> void:
	closed.emit()
	queue_free()
