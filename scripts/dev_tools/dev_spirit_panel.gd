extends Control
## 开发者工具 - 元灵管理面板
## 左侧：元灵头像列表（滚动）+ 底部新建按钮
## 右侧：详情面板（属性滑块+技能列表）+ 技能编辑/新建

signal closed()

const ELEMENT_COLORS: Dictionary = {
	"金刚": Color(0.85, 0.75, 0.3),
	"大地": Color(0.7, 0.55, 0.35),
	"雷火": Color(1.0, 0.4, 0.2),
	"冰雪": Color(0.4, 0.8, 1.0),
	"草木": Color(0.3, 0.8, 0.3),
	"梦幻": Color(0.7, 0.5, 0.9),
}

const SPIRIT_FIELDS: Array[Dictionary] = [
	{"key": "name", "label": "名字", "placeholder": "输入元灵名字"},
	{"key": "description", "label": "描述", "placeholder": "输入元灵描述"},
]

const SPIRIT_STATS: Array[Dictionary] = [
	{"key": "level", "label": "等级", "min": 1.0, "max": 10.0, "step": 1.0, "color": Color(0.4, 0.9, 0.6)},
	{"key": "max_level", "label": "最大等级", "min": 1.0, "max": 20.0, "step": 1.0, "color": Color(0.4, 0.9, 0.6)},
]

var spirits_data: Array = []
var all_skills: Array = []
var all_tags: Array = []
var selected_index: int = -1
var is_editing: bool = false
var is_creating: bool = false
var create_data: Dictionary = {}

# UI引用
var avatar_scroll: ScrollContainer
var avatar_list: VBoxContainer
var avatar_buttons: Array[Button] = []
var detail_container: VBoxContainer
var stat_sliders: Dictionary = {}
var stat_value_labels: Dictionary = {}
var text_edits: Dictionary = {}
var element_option: OptionButton
var icon_color_edit: LineEdit
var btn_edit: Button
var btn_confirm: Button
var btn_cancel: Button
var btn_back: Button
var name_display: Label
var skill_list_container: VBoxContainer
var skill_edit_panel: Control = null  # 技能编辑弹窗


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	spirits_data = DevDataSync.load_spirits()
	all_skills = DevDataSync.load_skills()
	all_tags = DevDataSync.load_tags()
	_build_ui()
	_refresh_list()
	if spirits_data.size() > 0:
		_select_spirit(0)


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
	title.text = "元灵管理"
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
	left_title.text = "— 元灵列表 —"
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

	# 新建按钮
	var add_btn := Button.new()
	add_btn.text = "+ 新建元灵"
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

	# 详情滚动区域
	var detail_scroll := ScrollContainer.new()
	detail_scroll.offset_top = 65
	detail_scroll.offset_bottom = 775
	detail_scroll.offset_left = 310
	detail_scroll.offset_right = 1410
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(detail_scroll)

	detail_container = VBoxContainer.new()
	detail_container.custom_minimum_size = Vector2(1080, 0)
	detail_container.add_theme_constant_override("separation", 4)
	detail_scroll.add_child(detail_container)

	# 元灵名称
	name_display = Label.new()
	name_display.text = ""
	name_display.add_theme_font_size_override("font_size", 26)
	name_display.add_theme_color_override("font_color", Color.WHITE)
	name_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_display.custom_minimum_size = Vector2(0, 40)
	detail_container.add_child(name_display)

	# 文本字段
	for field in SPIRIT_FIELDS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)
		var lbl := Label.new()
		lbl.text = field.label + ":"
		lbl.custom_minimum_size = Vector2(80, 28)
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

	# 元素选择
	var elem_row := HBoxContainer.new()
	elem_row.custom_minimum_size = Vector2(0, 32)
	var elem_lbl := Label.new()
	elem_lbl.text = "元素:"
	elem_lbl.custom_minimum_size = Vector2(80, 28)
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

	# 图标颜色
	var color_row := HBoxContainer.new()
	color_row.custom_minimum_size = Vector2(0, 32)
	var color_lbl := Label.new()
	color_lbl.text = "图标色:"
	color_lbl.custom_minimum_size = Vector2(80, 28)
	color_lbl.add_theme_font_size_override("font_size", 14)
	color_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	color_row.add_child(color_lbl)
	icon_color_edit = LineEdit.new()
	icon_color_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_color_edit.placeholder_text = "#FFD700"
	icon_color_edit.editable = false
	icon_color_edit.add_theme_font_size_override("font_size", 14)
	color_row.add_child(icon_color_edit)
	detail_container.add_child(color_row)

	# 数值滑块
	for stat in SPIRIT_STATS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 35)
		var lbl := Label.new()
		lbl.text = stat.label + ":"
		lbl.custom_minimum_size = Vector2(80, 28)
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
		val_lbl.custom_minimum_size = Vector2(50, 28)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", stat.color)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		stat_value_labels[stat.key] = val_lbl
		detail_container.add_child(row)

	# 分隔线
	var sep1 := HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 10)
	detail_container.add_child(sep1)

	# 技能列表标题
	var skill_title := Label.new()
	skill_title.text = "— 技能列表 —"
	skill_title.add_theme_font_size_override("font_size", 16)
	skill_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	skill_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_container.add_child(skill_title)

	skill_list_container = VBoxContainer.new()
	skill_list_container.add_theme_constant_override("separation", 4)
	detail_container.add_child(skill_list_container)

	# 添加技能按钮
	var add_skill_btn := Button.new()
	add_skill_btn.text = "+ 新建技能"
	add_skill_btn.custom_minimum_size = Vector2(0, 35)
	add_skill_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	add_skill_btn.pressed.connect(_on_create_skill)
	detail_container.add_child(add_skill_btn)

	# 分隔线
	var sep2 := HSeparator.new()
	sep2.custom_minimum_size = Vector2(0, 10)
	detail_container.add_child(sep2)

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

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer_right)
	detail_container.add_child(btn_row)


func _refresh_list() -> void:
	for child in avatar_list.get_children():
		child.queue_free()
	avatar_buttons.clear()

	for i in range(spirits_data.size()):
		var data: Dictionary = spirits_data[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(235, 55)
		var elem: String = data.get("element", "")
		var c: Color = ELEMENT_COLORS.get(elem, Color.WHITE)
		btn.text = "  %s  |  %s" % [data.get("name", "?"), elem]
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", c)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_spirit.bind(i))
		avatar_list.add_child(btn)
		avatar_buttons.append(btn)

	if selected_index >= 0 and selected_index < avatar_buttons.size():
		avatar_buttons[selected_index].modulate = Color(1.3, 1.3, 1.3)


func _select_spirit(index: int) -> void:
	if index < 0 or index >= spirits_data.size():
		return

	# 关闭技能编辑弹窗
	_close_skill_edit_panel()

	if is_editing or is_creating:
		_on_cancel()

	selected_index = index
	var data: Dictionary = spirits_data[index]

	for i in range(avatar_buttons.size()):
		avatar_buttons[i].modulate = Color(0.7, 0.7, 0.7) if i != index else Color(1.3, 1.3, 1.3)

	_update_detail_panel(data)


func _update_detail_panel(data: Dictionary) -> void:
	name_display.text = data.get("name", "未命名")

	# 文本
	for field in SPIRIT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			text_edits[key].text = str(data.get(key, ""))

	# 元素
	var elem: String = data.get("element", "")
	var elements := DevDataSync.get_elements()
	for i in range(elements.size()):
		if elements[i] == elem:
			element_option.selected = i
			break

	# 图标色
	icon_color_edit.text = str(data.get("icon_color", "#FFFFFF"))

	# 数值滑块
	for stat in SPIRIT_STATS:
		var key: String = stat.key
		if stat_sliders.has(key):
			var val: float = float(data.get(key, 0))
			stat_sliders[key].value = val
			stat_value_labels[key].text = str(int(val))

	# 技能列表
	_refresh_skill_list(data)


func _refresh_skill_list(spirit_data: Dictionary) -> void:
	for child in skill_list_container.get_children():
		child.queue_free()

	var skill_ids: Array = spirit_data.get("skills", [])
	for skill_id in skill_ids:
		var skill_data := _find_skill(str(skill_id))
		if skill_data.is_empty():
			continue

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 38)

		# 技能色块（图标占位）
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(30, 30)
		var icon_color_str: String = skill_data.get("icon_color", "#FFFFFF")
		if icon_color_str:
			icon.color = Color.from_string(icon_color_str, Color.GRAY)
		else:
			icon.color = Color.GRAY
		row.add_child(icon)

		# 技能名
		var name_lbl := Label.new()
		name_lbl.text = " %s  [%s]" % [skill_data.get("name", "?"), skill_data.get("type", "?")]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.custom_minimum_size = Vector2(200, 28)
		row.add_child(name_lbl)

		# 标签列表
		var tags: Array = skill_data.get("tags", [])
		var tags_text: String = ""
		for tag_id in tags:
			var tag_data := _find_tag(str(tag_id))
			if not tag_data.is_empty():
				tags_text += tag_data.get("name", "") + " "
		var tags_lbl := Label.new()
		tags_lbl.text = tags_text.strip_edges()
		tags_lbl.add_theme_font_size_override("font_size", 12)
		tags_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.5))
		tags_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tags_lbl)

		# 编辑按钮
		var edit_btn := Button.new()
		edit_btn.text = "编辑"
		edit_btn.custom_minimum_size = Vector2(60, 30)
		edit_btn.pressed.connect(_on_edit_skill.bind(str(skill_id)))
		row.add_child(edit_btn)

		skill_list_container.add_child(row)


func _find_skill(skill_id: String) -> Dictionary:
	for s in all_skills:
		if str(s.get("id", "")) == skill_id:
			return s
	return {}


func _find_tag(tag_id: String) -> Dictionary:
	for t in all_tags:
		if str(t.get("id", "")) == tag_id:
			return t
	return {}


func _on_slider_changed(val: float, key: String) -> void:
	if stat_value_labels.has(key):
		stat_value_labels[key].text = str(int(val))


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
	icon_color_edit.editable = editable


func _on_confirm() -> void:
	if is_creating:
		_confirm_create()
		return

	if selected_index < 0:
		return

	var data := _collect_data_from_ui()
	spirits_data[selected_index] = data
	DevDataSync.save_spirits(spirits_data)

	_refresh_list()
	_select_spirit(selected_index)

	is_editing = false
	_set_editable(false)
	btn_edit.text = "数值修改"
	btn_edit.disabled = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true

	print("[DevSpiritPanel] 已保存修改: ", data.get("name", ""))


func _collect_data_from_ui() -> Dictionary:
	var data: Dictionary = {}
	if is_creating:
		data = create_data.duplicate()
	else:
		data = spirits_data[selected_index].duplicate()

	for field in SPIRIT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			data[key] = text_edits[key].text

	for stat in SPIRIT_STATS:
		var key: String = stat.key
		if stat_sliders.has(key):
			data[key] = int(stat_sliders[key].value)

	var elements := DevDataSync.get_elements()
	if element_option.selected >= 0 and element_option.selected < elements.size():
		data["element"] = elements[element_option.selected]

	data["icon_color"] = icon_color_edit.text

	return data


func _on_cancel() -> void:
	is_editing = false
	is_creating = false
	_set_editable(false)
	btn_edit.text = "数值修改"
	btn_edit.disabled = false
	btn_confirm.disabled = true
	btn_confirm.text = "确认修改"
	btn_cancel.disabled = true

	if selected_index >= 0 and selected_index < spirits_data.size():
		_update_detail_panel(spirits_data[selected_index])


func _on_create_new() -> void:
	is_creating = true
	var new_id := DevDataSync.generate_spirit_id(spirits_data)
	create_data = DevDataSync.create_spirit_template(new_id)

	selected_index = -1
	for btn in avatar_buttons:
		btn.modulate = Color(0.7, 0.7, 0.7)

	_update_detail_panel(create_data)
	_refresh_skill_list(create_data)

	_set_editable(true)
	btn_edit.text = "新建中..."
	btn_edit.disabled = true
	btn_confirm.disabled = false
	btn_confirm.text = "确认创建"
	btn_cancel.disabled = false

	name_display.text = "新建元灵"
	name_display.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))


func _confirm_create() -> void:
	var data := _collect_data_from_ui()

	if data.get("name", "").strip_edges() == "":
		print("[DevSpiritPanel] 错误：元灵名字不能为空")
		return

	spirits_data.append(data)
	DevDataSync.save_spirits(spirits_data)

	is_creating = false
	_refresh_list()
	_select_spirit(spirits_data.size() - 1)

	btn_confirm.text = "确认修改"
	print("[DevSpiritPanel] 已创建新元灵: ", data.get("name", ""))


## ==================== 技能编辑/新建 ====================

func _on_create_skill() -> void:
	if selected_index < 0 and not is_creating:
		return
	_open_skill_edit_panel("")


func _on_edit_skill(skill_id: String) -> void:
	_open_skill_edit_panel(skill_id)


func _open_skill_edit_panel(skill_id: String) -> void:
	_close_skill_edit_panel()

	var is_new := (skill_id == "")
	var skill_data: Dictionary = {}

	if is_new:
		var elem: String = ""
		if selected_index >= 0 and selected_index < spirits_data.size():
			elem = spirits_data[selected_index].get("element", "")
		elif is_creating:
			elem = create_data.get("element", "")
		var new_skill_id := DevDataSync.generate_skill_id(all_skills, elem.to_lower())
		skill_data = DevDataSync.create_skill_template(new_skill_id, elem)
	else:
		skill_data = _find_skill(skill_id).duplicate(true)

	# 创建弹窗面板
	skill_edit_panel = Control.new()
	skill_edit_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(skill_edit_panel)

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	skill_edit_panel.add_child(overlay)

	# 弹窗主体
	var popup := Panel.new()
	popup.offset_left = 200
	popup.offset_top = 60
	popup.offset_right = 1240
	popup.offset_bottom = 760
	skill_edit_panel.add_child(popup)

	var popup_scroll := ScrollContainer.new()
	popup_scroll.offset_left = 210
	popup_scroll.offset_top = 70
	popup_scroll.offset_right = 1230
	popup_scroll.offset_bottom = 720
	popup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skill_edit_panel.add_child(popup_scroll)

	var popup_vbox := VBoxContainer.new()
	popup_vbox.custom_minimum_size = Vector2(1000, 0)
	popup_vbox.add_theme_constant_override("separation", 5)
	popup_scroll.add_child(popup_vbox)

	# 标题
	var popup_title := Label.new()
	popup_title.text = "新建技能" if is_new else "编辑技能: %s" % skill_data.get("name", "")
	popup_title.add_theme_font_size_override("font_size", 22)
	popup_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title.custom_minimum_size = Vector2(0, 35)
	popup_vbox.add_child(popup_title)

	# 技能名称
	var name_row := HBoxContainer.new()
	name_row.custom_minimum_size = Vector2(0, 32)
	var name_lbl := Label.new()
	name_lbl.text = "技能名:"
	name_lbl.custom_minimum_size = Vector2(80, 28)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = str(skill_data.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 14)
	name_row.add_child(name_edit)
	popup_vbox.add_child(name_row)

	# 技能描述
	var desc_row := HBoxContainer.new()
	desc_row.custom_minimum_size = Vector2(0, 32)
	var desc_lbl := Label.new()
	desc_lbl.text = "描述:"
	desc_lbl.custom_minimum_size = Vector2(80, 28)
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_row.add_child(desc_lbl)
	var desc_edit := LineEdit.new()
	desc_edit.text = str(skill_data.get("description", ""))
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.add_theme_font_size_override("font_size", 14)
	desc_row.add_child(desc_edit)
	popup_vbox.add_child(desc_row)

	# 技能详细说明
	var detail_row := HBoxContainer.new()
	detail_row.custom_minimum_size = Vector2(0, 32)
	var detail_lbl := Label.new()
	detail_lbl.text = "详细:"
	detail_lbl.custom_minimum_size = Vector2(80, 28)
	detail_lbl.add_theme_font_size_override("font_size", 14)
	detail_row.add_child(detail_lbl)
	var detail_edit := LineEdit.new()
	detail_edit.text = str(skill_data.get("detail", ""))
	detail_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_edit.add_theme_font_size_override("font_size", 14)
	detail_row.add_child(detail_edit)
	popup_vbox.add_child(detail_row)

	# 技能类型选择
	var type_row := HBoxContainer.new()
	type_row.custom_minimum_size = Vector2(0, 32)
	var type_lbl := Label.new()
	type_lbl.text = "类型:"
	type_lbl.custom_minimum_size = Vector2(80, 28)
	type_lbl.add_theme_font_size_override("font_size", 14)
	type_row.add_child(type_lbl)
	var type_option := OptionButton.new()
	type_option.add_item("主动 (active)")
	type_option.add_item("被动 (passive)")
	type_option.selected = 0 if skill_data.get("type", "active") == "active" else 1
	type_row.add_child(type_option)
	popup_vbox.add_child(type_row)

	# 数值滑块
	var numeric_fields := [
		{"key": "unlock_level", "label": "解锁等级", "min": 1, "max": 10, "step": 1},
		{"key": "unlock_cost", "label": "解锁消耗", "min": 0, "max": 100, "step": 1},
		{"key": "energy_cost", "label": "能量消耗", "min": 0, "max": 100, "step": 5},
		{"key": "cooldown", "label": "冷却时间", "min": 0, "max": 60, "step": 0.5},
	]
	var skill_sliders: Dictionary = {}
	var skill_slider_labels: Dictionary = {}

	for nf in numeric_fields:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		var lbl := Label.new()
		lbl.text = nf.label + ":"
		lbl.custom_minimum_size = Vector2(80, 26)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = nf.min
		slider.max_value = nf.max
		slider.step = nf.step
		slider.value = float(skill_data.get(nf.key, 0))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		skill_sliders[nf.key] = slider
		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(50, 26)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 13)
		if nf.key == "cooldown":
			val_lbl.text = "%.1f" % skill_data.get(nf.key, 0)
			slider.value_changed.connect(func(v): val_lbl.text = "%.1f" % v)
		else:
			val_lbl.text = str(int(skill_data.get(nf.key, 0)))
			slider.value_changed.connect(func(v): val_lbl.text = str(int(v)))
		row.add_child(val_lbl)
		skill_slider_labels[nf.key] = val_lbl
		popup_vbox.add_child(row)

	# 图标颜色
	var ic_row := HBoxContainer.new()
	ic_row.custom_minimum_size = Vector2(0, 32)
	var ic_lbl := Label.new()
	ic_lbl.text = "图标色:"
	ic_lbl.custom_minimum_size = Vector2(80, 28)
	ic_lbl.add_theme_font_size_override("font_size", 14)
	ic_row.add_child(ic_lbl)
	var ic_edit := LineEdit.new()
	ic_edit.text = str(skill_data.get("icon_color", "#FFFFFF"))
	ic_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ic_edit.add_theme_font_size_override("font_size", 14)
	ic_row.add_child(ic_edit)
	popup_vbox.add_child(ic_row)

	# 分隔线
	var sep_tags := HSeparator.new()
	sep_tags.custom_minimum_size = Vector2(0, 10)
	popup_vbox.add_child(sep_tags)

	# 标签选择区域
	var tags_title := Label.new()
	tags_title.text = "— 选择技能标签 —"
	tags_title.add_theme_font_size_override("font_size", 16)
	tags_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	tags_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_vbox.add_child(tags_title)

	# 按分类显示标签按钮
	var selected_tags: Array = skill_data.get("tags", []).duplicate(true)
	var tag_params_data: Dictionary = skill_data.get("tag_params", {}).duplicate(true)

	# 标签参数输入区容器（选中标签后动态填充）
	var tag_params_container := VBoxContainer.new()
	tag_params_container.name = "TagParamsContainer"
	tag_params_container.add_theme_constant_override("separation", 4)

	# 标签参数填写区放在标签按钮前面（点击标签后参数在上面展开）
	popup_vbox.add_child(tag_params_container)

	# 按category分组
	var categories: Dictionary = {}
	for tag in all_tags:
		var cat: String = str(tag.get("category", ""))
		if not categories.has(cat):
			categories[cat] = []
		categories[cat].append(tag)

	for cat in categories:
		var cat_label := Label.new()
		cat_label.text = "【%s】" % cat
		cat_label.add_theme_font_size_override("font_size", 14)
		cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
		popup_vbox.add_child(cat_label)

		var tag_grid := GridContainer.new()
		tag_grid.columns = 4
		tag_grid.add_theme_constant_override("h_separation", 6)
		tag_grid.add_theme_constant_override("v_separation", 4)
		popup_vbox.add_child(tag_grid)

		for tag in categories[cat]:
			var tag_id: String = str(tag.get("id", ""))
			var tag_name: String = str(tag.get("name", ""))
			var tag_btn := Button.new()
			tag_btn.text = "%s(%s)" % [tag_name, tag_id]
			tag_btn.add_theme_font_size_override("font_size", 11)
			tag_btn.custom_minimum_size = Vector2(220, 28)

			# 已选中高亮
			if tag_id in selected_tags:
				tag_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))

			# 点击切换选中状态
			tag_btn.pressed.connect(_on_tag_toggle.bind(tag_btn, tag_id, selected_tags, tag_params_container, tag_params_data, all_tags))
			tag_grid.add_child(tag_btn)

	# 初始化已选中标签的参数框
	for tag_id in selected_tags:
		_add_tag_param_fields(tag_id, tag_params_container, tag_params_data, all_tags)

	# 分隔线
	var sep_confirm := HSeparator.new()
	sep_confirm.custom_minimum_size = Vector2(0, 10)
	popup_vbox.add_child(sep_confirm)

	# 右键说明
	var hint := Label.new()
	hint.text = "点击标签按钮切换选中（绿色=已选中），标签参数待标签函数实现后填写"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_vbox.add_child(hint)

	# 确认/取消按钮
	var confirm_row := HBoxContainer.new()
	confirm_row.custom_minimum_size = Vector2(0, 45)
	confirm_row.add_theme_constant_override("separation", 20)

	var confirm_btn := Button.new()
	confirm_btn.text = "确认创建" if is_new else "确认修改"
	confirm_btn.custom_minimum_size = Vector2(160, 40)
	confirm_btn.add_theme_font_size_override("font_size", 16)
	confirm_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	confirm_btn.pressed.connect(_on_skill_confirm.bind(
		skill_data, is_new, name_edit, desc_edit, detail_edit,
		type_option, skill_sliders, ic_edit, selected_tags, tag_params_data
	))
	confirm_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(_close_skill_edit_panel)
	confirm_row.add_child(cancel_btn)

	var spacer_c := Control.new()
	spacer_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row.add_child(spacer_c)
	popup_vbox.add_child(confirm_row)


func _on_tag_toggle(btn: Button, tag_id: String, selected_tags: Array, container: VBoxContainer, tag_params_data: Dictionary, tags_source: Array) -> void:
	if tag_id in selected_tags:
		selected_tags.erase(tag_id)
		btn.add_theme_color_override("font_color", Color.WHITE)
		_remove_tag_param_fields(tag_id, container)
	else:
		selected_tags.append(tag_id)
		btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		_add_tag_param_fields(tag_id, container, tag_params_data, tags_source)


func _add_tag_param_fields(tag_id: String, container: VBoxContainer, tag_params_data: Dictionary, tags_source: Array) -> void:
	"""为选中的标签添加参数填写框"""
	# 查找标签数据
	var tag_data: Dictionary = {}
	for t in tags_source:
		if str(t.get("id", "")) == tag_id:
			tag_data = t
			break
	if tag_data.is_empty():
		print("[DevSpirit] _add_tag_param_fields: 找不到标签数据 id=%s tags_source.size=%d" % [tag_id, tags_source.size()])
		return

	var param_names: Array = tag_data.get("params", [])
	if param_names.is_empty():
		return

	# 已有则跳过
	if container.has_node("ParamSection_" + tag_id):
		return

	print("[DevSpirit] 创建参数填写区: tag=%s params=%s" % [tag_id, param_names])

	# 创建参数区块
	var section := VBoxContainer.new()
	section.name = "ParamSection_" + tag_id
	section.add_theme_constant_override("separation", 2)

	# 标题：标签名
	var header := Label.new()
	header.text = "▼ " + str(tag_data.get("name", tag_id)) + " 参数"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	section.add_child(header)

	# 获取已保存的参数值
	var saved_params: Dictionary = tag_params_data.get(tag_id, {})

	# 参数中文备注映射
	var param_labels: Dictionary = {
		"shape": "形状",
		"width": "矩形宽度",
		"height": "矩形高度",
		"radius": "半径(圆/月牙)",
		"arc_angle": "月牙弧度角(度)",
		"hp": "防御生命值",
		"attack_consume_rate": "攻击消耗速率(/s)",
		"speed_consume_rate": "球速消耗速率(px/s)",
		"max_count": "最多同时存在数",
		"duration": "持续秒数",
		"mouse_ops": "鼠标操作次数",
		"clear_count": "一次清除几个",
		"friction": "摩擦系数(0.3~2.0)",
		"bounciness": "弹性系数(0~1)",
		"value": "数值",
		"multiplier": "倍率",
		"position": "坐标 x,y",
		"size": "尺寸 宽,高",
		"boost_multiplier": "加速倍率",
		"slow_multiplier": "减速倍率",
		"damage_value": "伤害值",
		"damage_pct": "伤害比例(0~1)",
		"turn_speed": "转向速度",
		"return_distance": "返回距离比(0~1)",
		"zone_type": "区域类型",
		"zone_id": "区域ID",
		"target": "目标(self/ally/enemy)",
		"target_id": "目标ID",
		"target_position": "目标坐标 x,y",
		"skill_id": "技能ID",
		"bonus_uses": "增加使用次数",
		"illusion_type": "幻象类型",
		"illusion_id": "幻象ID",
	}

	for param_name in param_names:
		var pname: String = str(param_name)
		var display_name: String = param_labels.get(pname, pname)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)

		var lbl := Label.new()
		lbl.text = display_name + ":"
		lbl.custom_minimum_size = Vector2(160, 24)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(lbl)

		# shape 参数用下拉选择
		if pname == "shape":
			var option := OptionButton.new()
			option.name = "Input_shape"
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.add_theme_font_size_override("font_size", 13)
			option.add_item("矩形(rect)", 0)
			option.add_item("圆形(circle)", 1)
			option.add_item("月牙(crescent)", 2)
			# 已保存的值
			var saved_val = saved_params.get("shape", _get_param_default(tag_id, "shape"))
			match str(saved_val):
				"circle": option.selected = 1
				"crescent": option.selected = 2
				_: option.selected = 0
			row.add_child(option)
		else:
			var input := LineEdit.new()
			input.name = "Input_" + pname
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			input.add_theme_font_size_override("font_size", 13)
			# 填入已保存的值
			if saved_params.has(pname):
				var val = saved_params[pname]
				if val is float:
					input.text = str(snapped(val, 0.01))
				else:
					input.text = str(val)
			else:
				input.text = _get_param_default(tag_id, pname)
			input.placeholder_text = _get_param_hint(tag_id, pname)
			row.add_child(input)

		section.add_child(row)

	container.add_child(section)


func _remove_tag_param_fields(tag_id: String, container: VBoxContainer) -> void:
	"""移除标签的参数填写框"""
	var section = container.get_node_or_null("ParamSection_" + tag_id)
	if section:
		container.remove_child(section)
		section.queue_free()


func _get_param_default(tag_id: String, param_name: String) -> String:
	"""获取参数默认值"""
	var defaults: Dictionary = {
		"field_obs_add": {
			"shape": "rect",
			"width": "80",
			"height": "30",
			"radius": "40",
			"arc_angle": "120",
			"hp": "50",
			"attack_consume_rate": "20",
			"speed_consume_rate": "20",
			"max_count": "3",
			"duration": "15",
			"mouse_ops": "3",
		},
		"field_obs_clear": {
			"clear_count": "2",
			"mouse_ops": "2",
		},
		"field_terra_change": {
			"friction": "1",
			"bounciness": "0",
			"duration": "10",
		},
		"field_zone_boost": {
			"position": "0,0",
			"size": "200,200",
			"boost_multiplier": "1.5",
			"duration": "10",
		},
		"field_zone_slow": {
			"position": "0,0",
			"size": "200,200",
			"slow_multiplier": "0.5",
			"duration": "10",
		},
		"field_zone_danger": {
			"position": "0,0",
			"size": "200,200",
			"damage_value": "10",
			"duration": "10",
		},
		"field_zone_safe": {
			"position": "0,0",
			"size": "200,200",
			"duration": "10",
		},
		"ball_dmg_up_pct": {"value": "50"},
		"ball_dmg_down_pct": {"value": "30"},
		"ball_dmg_up_flat": {"value": "10"},
		"ball_dmg_down_flat": {"value": "5"},
		"ball_speed_up_pct": {"multiplier": "1.8"},
		"ball_speed_down_pct": {"multiplier": "2.0"},
		"ball_speed_up_flat": {"value": "100"},
		"ball_speed_down_flat": {"value": "50"},
		"ball_range_up": {"radius": "80", "damage_pct": "0.5"},
		"ball_range_down": {"multiplier": "0.5"},
		"ball_tracking": {"turn_speed": "3"},
		"ball_boomerang": {"return_distance": "0.5"},
	}
	if defaults.has(tag_id) and defaults[tag_id].has(param_name):
		return defaults[tag_id][param_name]
	return ""


func _get_param_hint(tag_id: String, param_name: String) -> String:
	"""获取参数输入提示"""
	var hints: Dictionary = {
		"shape": "rect / circle / crescent",
		"width": "矩形宽度",
		"height": "矩形高度",
		"radius": "半径(AOE/圆形/月牙)",
		"arc_angle": "月牙弧度角(度)",
		"hp": "防御生命值",
		"attack_consume_rate": "球攻击力消耗速率(/s)",
		"speed_consume_rate": "球速消耗速率(px/s)",
		"max_count": "最多同时存在数",
		"duration": "持续秒数",
		"mouse_ops": "鼠标操作次数",
		"clear_count": "一次清除几个",
		"friction": "摩擦系数(0.3~2.0)",
		"bounciness": "弹性系数(0~1)",
		"value": "数值",
		"multiplier": "倍率",
		"position": "x,y",
		"size": "宽,高",
		"boost_multiplier": "加速倍率",
		"slow_multiplier": "减速倍率",
		"damage_value": "伤害值",
		"damage_pct": "伤害比例(0~1)",
		"turn_speed": "转向速度",
		"return_distance": "返回距离比(0~1)",
	}
	if hints.has(param_name):
		return hints[param_name]
	return ""


func _on_skill_confirm(
	original_data: Dictionary,
	is_new: bool,
	name_edit: LineEdit,
	desc_edit: LineEdit,
	detail_edit: LineEdit,
	type_option: OptionButton,
	skill_sliders: Dictionary,
	ic_edit: LineEdit,
	selected_tags: Array,
	tag_params_data: Dictionary
) -> void:
	# 收集数据
	var skill_data: Dictionary = original_data.duplicate(true)
	skill_data["name"] = name_edit.text
	skill_data["description"] = desc_edit.text
	skill_data["detail"] = detail_edit.text
	skill_data["type"] = "active" if type_option.selected == 0 else "passive"
	skill_data["icon_color"] = ic_edit.text
	skill_data["tags"] = selected_tags.duplicate()

	# 收集标签参数（从UI输入框读取）
	var collected_params: Dictionary = {}
	if skill_edit_panel:
		var popup_scroll = skill_edit_panel.get_child(1)  # ScrollContainer
		if popup_scroll:
			var popup_vbox = popup_scroll.get_child(0)  # VBoxContainer
			if popup_vbox:
				var params_container = popup_vbox.get_node_or_null("TagParamsContainer")
				if params_container:
					for section in params_container.get_children():
						if section.name.begins_with("ParamSection_"):
							var tid: String = section.name.substr(13)  # 去掉 "ParamSection_"
							var section_params: Dictionary = {}
							for child in section.get_children():
								if child is HBoxContainer:
									for sub in child.get_children():
										if sub is OptionButton and sub.name.begins_with("Input_"):
											var pkey_ob: String = sub.name.substr(6)
											var shape_list: Array = ["rect", "circle", "crescent"]
											var ob_idx: int = sub.selected
											if ob_idx >= 0 and ob_idx < shape_list.size():
												section_params[pkey_ob] = shape_list[ob_idx]
										elif sub is LineEdit and sub.name.begins_with("Input_"):
											var pkey: String = sub.name.substr(6)  # 去掉 "Input_"
											var pval: String = sub.text.strip_edges()
											if pval != "":
												# 尝试转数字
												if pval.is_valid_float():
													section_params[pkey] = float(pval)
												else:
													section_params[pkey] = pval
							if section_params.size() > 0:
								collected_params[tid] = section_params

	skill_data["tag_params"] = collected_params

	# 数值
	for key in skill_sliders:
		if key == "cooldown":
			skill_data[key] = skill_sliders[key].value
		else:
			skill_data[key] = int(skill_sliders[key].value)

	# 验证
	if skill_data.get("name", "").strip_edges() == "":
		print("[DevSpiritPanel] 错误：技能名字不能为空")
		return

	if is_new:
		# 添加到技能列表
		all_skills.append(skill_data)
		DevDataSync.save_skills(all_skills)

		# 添加到当前元灵的技能列表
		if selected_index >= 0 and selected_index < spirits_data.size():
			spirits_data[selected_index]["skills"].append(skill_data["id"])
			DevDataSync.save_spirits(spirits_data)
		elif is_creating:
			create_data["skills"].append(skill_data["id"])

		print("[DevSpiritPanel] 已创建技能: ", skill_data.get("name", ""))
	else:
		# 更新已有技能
		var found := false
		for i in range(all_skills.size()):
			if str(all_skills[i].get("id", "")) == str(skill_data.get("id", "")):
				all_skills[i] = skill_data
				found = true
				break
		if found:
			DevDataSync.save_skills(all_skills)
		print("[DevSpiritPanel] 已更新技能: ", skill_data.get("name", ""))

	_close_skill_edit_panel()

	# 刷新技能列表
	if selected_index >= 0 and selected_index < spirits_data.size():
		_refresh_skill_list(spirits_data[selected_index])
	elif is_creating:
		_refresh_skill_list(create_data)


func _close_skill_edit_panel() -> void:
	if skill_edit_panel and is_instance_valid(skill_edit_panel):
		skill_edit_panel.queue_free()
		skill_edit_panel = null


func _on_close() -> void:
	_close_skill_edit_panel()
	closed.emit()
	queue_free()
