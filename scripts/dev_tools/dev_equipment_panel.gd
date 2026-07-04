extends Control
## 开发者工具 - 装备管理面板
## 左侧：装备列表（滚动）+ 筛选 + 新建按钮
## 右侧：详情面板（属性滑块+稀有度/部位下拉+图标上传）

signal closed()

const STAT_DEFS: Array[Dictionary] = [
	{"key": "attack_bonus", "label": "攻击加成", "min": 0.0, "max": 50.0, "step": 1.0, "color": Color(0.9, 0.3, 0.3)},
	{"key": "defense_bonus", "label": "防御加成", "min": 0.0, "max": 50.0, "step": 1.0, "color": Color(0.9, 0.75, 0.1)},
	{"key": "speed_bonus", "label": "速度加成", "min": 0.0, "max": 50.0, "step": 1.0, "color": Color(0.2, 0.5, 0.95)},
	{"key": "stamina_bonus", "label": "体力加成", "min": 0.0, "max": 150.0, "step": 5.0, "color": Color(0.9, 0.4, 0.4)},
	{"key": "resilience_bonus", "label": "韧性加成", "min": 0.0, "max": 30.0, "step": 1.0, "color": Color(0.6, 0.6, 0.6)},
	{"key": "ball_speed_bonus", "label": "球速加成", "min": 0.0, "max": 100.0, "step": 5.0, "color": Color(0.6, 0.4, 0.2)},
]

const TEXT_FIELDS: Array[Dictionary] = [
	{"key": "name", "label": "名字", "placeholder": "输入装备名称"},
	{"key": "description", "label": "描述", "placeholder": "输入装备描述"},
]

var items_data: Array = []
var selected_index: int = -1
var is_editing: bool = false
var is_creating: bool = false
var create_data: Dictionary = {}
var filter_subtype: String = "all"
var filter_rarity: String = "all"

var avatar_scroll: ScrollContainer
var avatar_list: VBoxContainer
var avatar_buttons: Array[Button] = []
var detail_container: VBoxContainer
var stat_sliders: Dictionary = {}
var stat_value_labels: Dictionary = {}
var text_edits: Dictionary = {}
var rarity_option: OptionButton
var subtype_option: OptionButton
var btn_edit: Button
var btn_confirm: Button
var btn_cancel: Button
var btn_back: Button
var name_display: Label
var sell_price_edit: LineEdit
var icon_path_edit: LineEdit
var icon_preview: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	items_data = DevDataSync.load_items()
	_build_ui()
	_refresh_list()
	if items_data.size() > 0:
		_select_item(0)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.10, 0.98)
	add_child(bg)

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
	title.text = "装备管理"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(100, 35)
	top_bar.add_child(spacer)

	# 左侧面板
	var left_panel := Panel.new()
	left_panel.offset_top = 60
	left_panel.offset_bottom = 780
	left_panel.offset_left = 20
	left_panel.offset_right = 300
	add_child(left_panel)

	var left_title := Label.new()
	left_title.text = "— 装备列表 —"
	left_title.offset_top = 65
	left_title.offset_bottom = 90
	left_title.offset_left = 20
	left_title.offset_right = 300
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_title.add_theme_font_size_override("font_size", 15)
	left_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(left_title)

	# 筛选区
	var filter_box := VBoxContainer.new()
	filter_box.offset_top = 95
	filter_box.offset_bottom = 160
	filter_box.offset_left = 25
	filter_box.offset_right = 295
	filter_box.add_theme_constant_override("separation", 4)
	add_child(filter_box)

	var subtype_row := HBoxContainer.new()
	var st_lbl := Label.new()
	st_lbl.text = "部位:"
	st_lbl.custom_minimum_size = Vector2(45, 24)
	st_lbl.add_theme_font_size_override("font_size", 12)
	st_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	subtype_row.add_child(st_lbl)
	var st_opt := OptionButton.new()
	st_opt.add_item("全部", 0)
	st_opt.add_item("手套", 1)
	st_opt.add_item("球衣", 2)
	st_opt.add_item("球鞋", 3)
	st_opt.selected = 0
	st_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_opt.add_theme_font_size_override("font_size", 12)
	st_opt.item_selected.connect(_on_filter_subtype)
	subtype_row.add_child(st_opt)
	filter_box.add_child(subtype_row)

	var rarity_row := HBoxContainer.new()
	var r_lbl := Label.new()
	r_lbl.text = "稀有度:"
	r_lbl.custom_minimum_size = Vector2(45, 24)
	r_lbl.add_theme_font_size_override("font_size", 12)
	r_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	rarity_row.add_child(r_lbl)
	var r_opt := OptionButton.new()
	r_opt.add_item("全部", 0)
	r_opt.add_item("普通", 1)
	r_opt.add_item("良好", 2)
	r_opt.add_item("稀有", 3)
	r_opt.add_item("史诗", 4)
	r_opt.add_item("传说", 5)
	r_opt.selected = 0
	r_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_opt.add_theme_font_size_override("font_size", 12)
	r_opt.item_selected.connect(_on_filter_rarity)
	rarity_row.add_child(r_opt)
	filter_box.add_child(rarity_row)

	avatar_scroll = ScrollContainer.new()
	avatar_scroll.offset_top = 165
	avatar_scroll.offset_bottom = 720
	avatar_scroll.offset_left = 25
	avatar_scroll.offset_right = 295
	avatar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(avatar_scroll)

	avatar_list = VBoxContainer.new()
	avatar_list.custom_minimum_size = Vector2(260, 0)
	avatar_list.add_theme_constant_override("separation", 4)
	avatar_scroll.add_child(avatar_list)

	var add_btn := Button.new()
	add_btn.text = "+ 新建装备"
	add_btn.offset_top = 730
	add_btn.offset_bottom = 770
	add_btn.offset_left = 30
	add_btn.offset_right = 290
	add_btn.add_theme_font_size_override("font_size", 16)
	add_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	add_btn.pressed.connect(_on_create_new)
	add_child(add_btn)

	# 右侧详情面板
	var right_bg := Panel.new()
	right_bg.offset_top = 60
	right_bg.offset_bottom = 780
	right_bg.offset_left = 320
	right_bg.offset_right = 1420
	add_child(right_bg)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.offset_top = 65
	detail_scroll.offset_bottom = 775
	detail_scroll.offset_left = 330
	detail_scroll.offset_right = 1410
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(detail_scroll)

	detail_container = VBoxContainer.new()
	detail_container.custom_minimum_size = Vector2(1060, 0)
	detail_container.add_theme_constant_override("separation", 4)
	detail_scroll.add_child(detail_container)

	# 名称
	name_display = Label.new()
	name_display.text = ""
	name_display.add_theme_font_size_override("font_size", 26)
	name_display.add_theme_color_override("font_color", Color.WHITE)
	name_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_display.custom_minimum_size = Vector2(0, 40)
	detail_container.add_child(name_display)

	# 图标预览+选择
	var icon_row := HBoxContainer.new()
	icon_row.custom_minimum_size = Vector2(0, 50)
	var icon_lbl := Label.new()
	icon_lbl.text = "图标:"
	icon_lbl.custom_minimum_size = Vector2(80, 40)
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	icon_row.add_child(icon_lbl)
	icon_preview = TextureRect.new()
	icon_preview.custom_minimum_size = Vector2(40, 40)
	icon_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_row.add_child(icon_preview)
	icon_path_edit = LineEdit.new()
	icon_path_edit.placeholder_text = "未上传图片"
	icon_path_edit.editable = false
	icon_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_path_edit.add_theme_font_size_override("font_size", 13)
	icon_row.add_child(icon_path_edit)
	var icon_btn := Button.new()
	icon_btn.text = "选择图片"
	icon_btn.custom_minimum_size = Vector2(90, 32)
	icon_btn.add_theme_font_size_override("font_size", 12)
	icon_btn.disabled = true
	icon_btn.pressed.connect(_on_choose_icon)
	icon_row.add_child(icon_btn)
	var icon_clear := Button.new()
	icon_clear.text = "清除"
	icon_clear.custom_minimum_size = Vector2(60, 32)
	icon_clear.add_theme_font_size_override("font_size", 12)
	icon_clear.disabled = true
	icon_clear.pressed.connect(_on_clear_icon)
	icon_row.add_child(icon_clear)
	detail_container.add_child(icon_row)

	# 文本字段
	for field in TEXT_FIELDS:
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

	# 部位选择
	var st_select_row := HBoxContainer.new()
	st_select_row.custom_minimum_size = Vector2(0, 32)
	var st_sel_lbl := Label.new()
	st_sel_lbl.text = "部位:"
	st_sel_lbl.custom_minimum_size = Vector2(80, 28)
	st_sel_lbl.add_theme_font_size_override("font_size", 14)
	st_sel_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	st_select_row.add_child(st_sel_lbl)
	subtype_option = OptionButton.new()
	subtype_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st in DevDataSync.get_equipment_subtypes():
		subtype_option.add_item(DevDataSync.get_subtype_name(st))
	subtype_option.disabled = true
	st_select_row.add_child(subtype_option)
	detail_container.add_child(st_select_row)

	# 稀有度选择
	var rar_row := HBoxContainer.new()
	rar_row.custom_minimum_size = Vector2(0, 32)
	var rar_lbl := Label.new()
	rar_lbl.text = "稀有度:"
	rar_lbl.custom_minimum_size = Vector2(80, 28)
	rar_lbl.add_theme_font_size_override("font_size", 14)
	rar_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	rar_row.add_child(rar_lbl)
	rarity_option = OptionButton.new()
	rarity_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in DevDataSync.get_rarities():
		rarity_option.add_item(DevDataSync.get_rarity_name(r))
	rarity_option.disabled = true
	rar_row.add_child(rarity_option)
	detail_container.add_child(rar_row)

	# 售价
	var price_row := HBoxContainer.new()
	price_row.custom_minimum_size = Vector2(0, 32)
	var p_lbl := Label.new()
	p_lbl.text = "售价:"
	p_lbl.custom_minimum_size = Vector2(80, 28)
	p_lbl.add_theme_font_size_override("font_size", 14)
	p_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	price_row.add_child(p_lbl)
	sell_price_edit = LineEdit.new()
	sell_price_edit.placeholder_text = "出售价格（童话币）"
	sell_price_edit.editable = false
	sell_price_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_price_edit.add_theme_font_size_override("font_size", 14)
	price_row.add_child(sell_price_edit)
	detail_container.add_child(price_row)

	var sep1 := HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 10)
	detail_container.add_child(sep1)

	var attr_title := Label.new()
	attr_title.text = "— 属性加成 —"
	attr_title.add_theme_font_size_override("font_size", 16)
	attr_title.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	attr_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_container.add_child(attr_title)

	for stat in STAT_DEFS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 35)
		var lbl := Label.new()
		lbl.text = stat.label + ":"
		lbl.custom_minimum_size = Vector2(100, 28)
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

	var display_list: Array = []
	for i in range(items_data.size()):
		var data: Dictionary = items_data[i]
		if str(data.get("type", "")) != "equipment":
			continue
		if filter_subtype != "all" and str(data.get("sub_type", "")) != filter_subtype:
			continue
		if filter_rarity != "all" and str(data.get("rarity", "")) != filter_rarity:
			continue
		display_list.append({"index": i, "data": data})

	for item in display_list:
		var idx: int = item.index
		var data: Dictionary = item.data
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(255, 50)
		var rarity: String = data.get("rarity", "common")
		var c: Color = DevDataSync.get_rarity_color(rarity)
		var sub_name: String = DevDataSync.get_subtype_name(str(data.get("sub_type", "")))
		btn.text = "  %s\n  [%s] %s" % [data.get("name", "?"), sub_name, DevDataSync.get_rarity_name(rarity)]
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", c)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_item.bind(idx))
		avatar_list.add_child(btn)
		avatar_buttons.append(btn)

	if selected_index >= 0 and selected_index < items_data.size():
		var real_btn_idx := -1
		for bi in range(avatar_buttons.size()):
			var d: Dictionary = items_data[selected_index]
			var bi_data: Dictionary = items_data[display_list[bi].index] if bi < display_list.size() else {}
			if bi_data.get("id", "") == d.get("id", ""):
				real_btn_idx = bi
				break
		if real_btn_idx >= 0:
			avatar_buttons[real_btn_idx].modulate = Color(1.3, 1.3, 1.3)


func _select_item(index: int) -> void:
	if index < 0 or index >= items_data.size():
		return
	if is_editing or is_creating:
		_on_cancel()

	selected_index = index
	var data: Dictionary = items_data[index]

	for i in range(avatar_buttons.size()):
		avatar_buttons[i].modulate = Color(0.7, 0.7, 0.7)
		if i == selected_index:
			pass

	_update_detail_panel(data)


func _update_detail_panel(data: Dictionary) -> void:
	name_display.text = str(data.get("name", "未命名"))
	var rarity: String = str(data.get("rarity", "common"))
	name_display.add_theme_color_override("font_color", DevDataSync.get_rarity_color(rarity))

	for field in TEXT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			text_edits[key].text = str(data.get(key, ""))

	# 部位
	var sub_types := DevDataSync.get_equipment_subtypes()
	var cur_subtype: String = str(data.get("sub_type", "glove"))
	for i in range(sub_types.size()):
		if sub_types[i] == cur_subtype:
			subtype_option.selected = i
			break

	# 稀有度
	var rarities := DevDataSync.get_rarities()
	for i in range(rarities.size()):
		if rarities[i] == rarity:
			rarity_option.selected = i
			break

	# 售价
	sell_price_edit.text = str(data.get("sell_price", 0))

	# 图标
	var icon_path: String = str(data.get("icon", ""))
	icon_path_edit.text = icon_path
	if icon_path != "":
		var img := Image.new()
		if img.load(icon_path) == OK:
			icon_preview.texture = ImageTexture.create_from_image(img)
		else:
			icon_preview.texture = null
	else:
		icon_preview.texture = null

	# 属性滑块
	for stat in STAT_DEFS:
		var key: String = stat.key
		if stat_sliders.has(key):
			var stats_dict: Dictionary = data.get("stats", {})
			var val: float = float(stats_dict.get(key, 0))
			stat_sliders[key].value = val
			stat_value_labels[key].text = str(int(val))


func _on_slider_changed(val: float, key: String) -> void:
	if stat_value_labels.has(key):
		stat_value_labels[key].text = str(int(val))


func _on_filter_subtype(idx: int) -> void:
	var map_arr: Array = ["all", "glove", "jersey", "shoes"]
	if idx >= 0 and idx < map_arr.size():
		filter_subtype = map_arr[idx]
	_refresh_list()


func _on_filter_rarity(idx: int) -> void:
	var map_arr: Array = ["all", "common", "good", "rare", "epic", "legendary"]
	if idx >= 0 and idx < map_arr.size():
		filter_rarity = map_arr[idx]
	_refresh_list()


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
	rarity_option.disabled = not editable
	subtype_option.disabled = not editable
	sell_price_edit.editable = editable
	# 图标按钮
	for child in detail_container.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					if sub.text == "选择图片" or sub.text == "清除":
						sub.disabled = not editable


func _on_confirm() -> void:
	if is_creating:
		_confirm_create()
		return
	if selected_index < 0:
		return

	var data := _collect_data_from_ui()
	items_data[selected_index] = data
	DevDataSync.save_items(items_data)

	_refresh_list()
	_select_item(selected_index)

	is_editing = false
	_set_editable(false)
	btn_edit.text = "数值修改"
	btn_edit.disabled = false
	btn_confirm.disabled = true
	btn_cancel.disabled = true

	print("[DevEquipment] 已保存修改: ", data.get("name", ""))


func _collect_data_from_ui() -> Dictionary:
	var data: Dictionary = {}
	if is_creating:
		data = create_data.duplicate(true)
	else:
		data = items_data[selected_index].duplicate(true)

	for field in TEXT_FIELDS:
		var key: String = field.key
		if text_edits.has(key):
			data[key] = text_edits[key].text

	var sub_types := DevDataSync.get_equipment_subtypes()
	if subtype_option.selected >= 0 and subtype_option.selected < sub_types.size():
		data["sub_type"] = sub_types[subtype_option.selected]

	var rarities := DevDataSync.get_rarities()
	if rarity_option.selected >= 0 and rarity_option.selected < rarities.size():
		data["rarity"] = rarities[rarity_option.selected]

	var price_str: String = sell_price_edit.text.strip_edges()
	if price_str.is_valid_int():
		data["sell_price"] = int(price_str)

	# 图标
	var icon_src := icon_path_edit.text.strip_edges()
	var old_icon: String = str(data.get("icon", ""))
	if icon_src == "":
		data["icon"] = ""
	elif icon_src != old_icon:
		var saved := DevDataSync.save_item_icon(icon_src, str(data.get("id", "")), "equipment")
		if saved != "":
			data["icon"] = saved
		else:
			data["icon"] = old_icon

	# 属性
	var stats_dict: Dictionary = data.get("stats", {})
	for stat in STAT_DEFS:
		var key: String = stat.key
		if stat_sliders.has(key):
			stats_dict[key] = int(stat_sliders[key].value)
	data["stats"] = stats_dict

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

	if selected_index >= 0 and selected_index < items_data.size():
		_update_detail_panel(items_data[selected_index])
	else:
		_clear_detail_panel()


func _clear_detail_panel() -> void:
	name_display.text = "请选择装备"
	for key in text_edits:
		text_edits[key].text = ""
	for key in stat_sliders:
		stat_sliders[key].value = 0
		stat_sliders[key].editable = false
	sell_price_edit.text = ""
	icon_path_edit.text = ""
	icon_preview.texture = null


func _on_create_new() -> void:
	is_creating = true
	var new_id := DevDataSync.generate_equipment_id(items_data, "glove")
	create_data = DevDataSync.create_equipment_template(new_id, "glove")

	selected_index = -1
	for btn in avatar_buttons:
		btn.modulate = Color(0.7, 0.7, 0.7)

	_update_detail_panel(create_data)

	_set_editable(true)
	btn_edit.text = "新建中..."
	btn_edit.disabled = true
	btn_confirm.disabled = false
	btn_confirm.text = "确认创建"
	btn_cancel.disabled = false

	name_display.text = "新建装备"
	name_display.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))


func _confirm_create() -> void:
	var data := _collect_data_from_ui()
	if data.get("name", "").strip_edges() == "":
		print("[DevEquipment] 错误：装备名字不能为空")
		return

	items_data.append(data)
	DevDataSync.save_items(items_data)

	is_creating = false
	_refresh_list()
	var new_idx := items_data.size() - 1
	selected_index = new_idx
	_select_item(new_idx)

	btn_confirm.text = "确认修改"
	print("[DevEquipment] 已创建新装备: ", data.get("name", ""))


func _on_choose_icon() -> void:
	print("[DevEquipment] 选择图标")
	var icon_dialog := FileDialog.new()
	icon_dialog.access = FileDialog.ACCESS_FILESYSTEM
	icon_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	icon_dialog.filters = PackedStringArray(["*.png ; PNG 图片", "*.jpg ; JPG 图片", "*.jpeg ; JPEG 图片", "*.webp ; WebP 图片"])
	icon_dialog.title = "选择装备图标"
	icon_dialog.file_selected.connect(_on_icon_selected)
	add_child(icon_dialog)
	icon_dialog.popup_centered(Vector2(800, 600))


func _on_icon_selected(path: String) -> void:
	icon_path_edit.text = path
	var img := Image.new()
	if img.load(path) == OK:
		icon_preview.texture = ImageTexture.create_from_image(img)


func _on_clear_icon() -> void:
	icon_path_edit.text = ""
	icon_preview.texture = null


func _on_close() -> void:
	closed.emit()
	queue_free()
