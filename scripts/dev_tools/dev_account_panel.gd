extends Control
## 开发者工具 - 账号管理面板
## 发物资、背包管理、训练管理、角色解锁
## 测试账号用，方便快速调试

signal closed()

var currency_inputs: Dictionary = {}
var currency_labels: Dictionary = {}
var backpack_list: VBoxContainer
var backpack_scroll: ScrollContainer
var selected_char_option: OptionButton
var char_train_sliders: Dictionary = {}
var char_train_labels: Dictionary = {}
var field_level_edit: LineEdit

const TRAIN_STATS: Array[Dictionary] = [
	{"key": "stamina_bonus", "label": "体力", "max": 100},
	{"key": "defense_bonus", "label": "防御", "max": 50},
	{"key": "speed_bonus", "label": "速度", "max": 50},
	{"key": "attack_bonus", "label": "攻击", "max": 50},
	{"key": "resilience_bonus", "label": "韧性", "max": 30},
	{"key": "ball_speed_bonus", "label": "球速", "max": 100},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_all()


func _build_ui() -> void:
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

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.custom_minimum_size = Vector2(100, 35)
	back_btn.pressed.connect(_on_close)
	top_bar.add_child(back_btn)

	var title := Label.new()
	title.text = "账号管理（测试工具）"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(100, 35)
	top_bar.add_child(spacer)

	# 三栏布局：左(货币+角色) 中(背包) 右(训练)
	# === 左栏 ===
	var left_panel := Panel.new()
	left_panel.offset_top = 60
	left_panel.offset_bottom = 780
	left_panel.offset_left = 20
	left_panel.offset_right = 400
	add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.offset_top = 70
	left_vbox.offset_bottom = 770
	left_vbox.offset_left = 30
	left_vbox.offset_right = 390
	left_vbox.add_theme_constant_override("separation", 8)
	add_child(left_vbox)

	# 货币管理
	var currency_title := Label.new()
	currency_title.text = "— 货币管理 —"
	currency_title.add_theme_font_size_override("font_size", 16)
	currency_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	currency_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_vbox.add_child(currency_title)

	var currency_list: Array = [
		{"key": "fairy_coin", "label": "童话币", "color": Color(1.0, 0.85, 0.3)},
		{"key": "spirit_ore", "label": "元灵矿石", "color": Color(0.7, 0.5, 0.3)},
		{"key": "crystal", "label": "水晶", "color": Color(0.4, 0.8, 1.0)},
	]

	for cur in currency_list:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)

		var lbl := Label.new()
		lbl.text = cur.label + ":"
		lbl.custom_minimum_size = Vector2(70, 24)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", cur.color)
		row.add_child(lbl)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(80, 24)
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.add_theme_color_override("font_color", Color.WHITE)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		currency_labels[cur.key] = val_lbl

		var input := LineEdit.new()
		input.placeholder_text = "数量"
		input.custom_minimum_size = Vector2(70, 26)
		input.add_theme_font_size_override("font_size", 12)
		row.add_child(input)
		currency_inputs[cur.key] = input

		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.custom_minimum_size = Vector2(30, 26)
		add_btn.add_theme_font_size_override("font_size", 12)
		add_btn.pressed.connect(_on_add_currency.bind(cur.key))
		row.add_child(add_btn)

		left_vbox.add_child(row)

	# 一键满货币
	var max_all_btn := Button.new()
	max_all_btn.text = "💰 一键满货币 (99999)"
	max_all_btn.custom_minimum_size = Vector2(0, 32)
	max_all_btn.add_theme_font_size_override("font_size", 13)
	max_all_btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	max_all_btn.pressed.connect(_on_max_all_currency)
	left_vbox.add_child(max_all_btn)

	var sep1 := HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 8)
	left_vbox.add_child(sep1)

	# 角色管理
	var char_title := Label.new()
	char_title.text = "— 角色管理 —"
	char_title.add_theme_font_size_override("font_size", 16)
	char_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_vbox.add_child(char_title)

	var unlock_all_btn := Button.new()
	unlock_all_btn.text = "🔓 解锁全部角色"
	unlock_all_btn.custom_minimum_size = Vector2(0, 32)
	unlock_all_btn.add_theme_font_size_override("font_size", 13)
	unlock_all_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	unlock_all_btn.pressed.connect(_on_unlock_all_chars)
	left_vbox.add_child(unlock_all_btn)

	var dev_mode_row := HBoxContainer.new()
	dev_mode_row.custom_minimum_size = Vector2(0, 28)
	var dev_lbl := Label.new()
	dev_lbl.text = "开发者模式:"
	dev_lbl.custom_minimum_size = Vector2(80, 24)
	dev_lbl.add_theme_font_size_override("font_size", 13)
	dev_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dev_mode_row.add_child(dev_lbl)
	var dev_label_val := Label.new()
	dev_label_val.text = ""
	dev_label_val.add_theme_font_size_override("font_size", 13)
	dev_mode_row.add_child(dev_label_val)
	currency_labels["is_dev_mode"] = dev_label_val
	left_vbox.add_child(dev_mode_row)

	# === 中栏：背包管理 ===
	var mid_panel := Panel.new()
	mid_panel.offset_top = 60
	mid_panel.offset_bottom = 780
	mid_panel.offset_left = 420
	mid_panel.offset_right = 820
	add_child(mid_panel)

	var mid_vbox := VBoxContainer.new()
	mid_vbox.offset_top = 70
	mid_vbox.offset_bottom = 770
	mid_vbox.offset_left = 430
	mid_vbox.offset_right = 810
	mid_vbox.add_theme_constant_override("separation", 6)
	add_child(mid_vbox)

	var bp_title := Label.new()
	bp_title.text = "— 背包管理 —"
	bp_title.add_theme_font_size_override("font_size", 16)
	bp_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	bp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_vbox.add_child(bp_title)

	var bp_info := Label.new()
	bp_info.text = ""
	bp_info.add_theme_font_size_override("font_size", 12)
	bp_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	currency_labels["backpack_info"] = bp_info
	mid_vbox.add_child(bp_info)

	# 快捷添加按钮
	var quick_btn1 := Button.new()
	quick_btn1.text = "📦 添加全套传说装备"
	quick_btn1.custom_minimum_size = Vector2(0, 30)
	quick_btn1.add_theme_font_size_override("font_size", 12)
	quick_btn1.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	quick_btn1.pressed.connect(_on_add_legendary_equip)
	mid_vbox.add_child(quick_btn1)

	var quick_btn2 := Button.new()
	quick_btn2.text = "🍬 添加全部食物 (各10个)"
	quick_btn2.custom_minimum_size = Vector2(0, 30)
	quick_btn2.add_theme_font_size_override("font_size", 12)
	quick_btn2.add_theme_color_override("font_color", Color(0.3, 0.9, 0.6))
	quick_btn2.pressed.connect(_on_add_all_food)
	mid_vbox.add_child(quick_btn2)

	var clear_btn := Button.new()
	clear_btn.text = "🗑️ 清空背包"
	clear_btn.custom_minimum_size = Vector2(0, 28)
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	clear_btn.pressed.connect(_on_clear_backpack)
	mid_vbox.add_child(clear_btn)

	var sep_m := HSeparator.new()
	sep_m.custom_minimum_size = Vector2(0, 6)
	mid_vbox.add_child(sep_m)

	var bp_list_title := Label.new()
	bp_list_title.text = "背包物品："
	bp_list_title.add_theme_font_size_override("font_size", 13)
	bp_list_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	mid_vbox.add_child(bp_list_title)

	backpack_scroll = ScrollContainer.new()
	backpack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backpack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid_vbox.add_child(backpack_scroll)

	backpack_list = VBoxContainer.new()
	backpack_list.custom_minimum_size = Vector2(360, 0)
	backpack_list.add_theme_constant_override("separation", 3)
	backpack_scroll.add_child(backpack_list)

	# === 右栏：训练管理 ===
	var right_panel := Panel.new()
	right_panel.offset_top = 60
	right_panel.offset_bottom = 780
	right_panel.offset_left = 840
	right_panel.offset_right = 1420
	add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.offset_top = 70
	right_vbox.offset_bottom = 770
	right_vbox.offset_left = 850
	right_vbox.offset_right = 1410
	right_vbox.add_theme_constant_override("separation", 6)
	add_child(right_vbox)

	var train_title := Label.new()
	train_title.text = "— 训练管理 —"
	train_title.add_theme_font_size_override("font_size", 16)
	train_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	train_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(train_title)

	# 场地等级
	var field_row := HBoxContainer.new()
	field_row.custom_minimum_size = Vector2(0, 30)
	var field_lbl := Label.new()
	field_lbl.text = "场地等级:"
	field_lbl.custom_minimum_size = Vector2(70, 24)
	field_lbl.add_theme_font_size_override("font_size", 13)
	field_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	field_row.add_child(field_lbl)
	field_level_edit = LineEdit.new()
	field_level_edit.placeholder_text = "1-10"
	field_level_edit.custom_minimum_size = Vector2(80, 26)
	field_level_edit.add_theme_font_size_override("font_size", 12)
	field_row.add_child(field_level_edit)
	var field_set_btn := Button.new()
	field_set_btn.text = "设置"
	field_set_btn.custom_minimum_size = Vector2(50, 26)
	field_set_btn.add_theme_font_size_override("font_size", 12)
	field_set_btn.pressed.connect(_on_set_field_level)
	field_row.add_child(field_set_btn)
	right_vbox.add_child(field_row)

	# 选择角色
	var char_row := HBoxContainer.new()
	char_row.custom_minimum_size = Vector2(0, 30)
	var char_lbl := Label.new()
	char_lbl.text = "选择角色:"
	char_lbl.custom_minimum_size = Vector2(70, 24)
	char_lbl.add_theme_font_size_override("font_size", 13)
	char_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	char_row.add_child(char_lbl)
	selected_char_option = OptionButton.new()
	selected_char_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_char_option.add_theme_font_size_override("font_size", 12)
	selected_char_option.item_selected.connect(_on_char_selected)
	char_row.add_child(selected_char_option)
	right_vbox.add_child(char_row)

	# 训练属性滑块
	for ts in TRAIN_STATS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)

		var lbl := Label.new()
		lbl.text = ts.label + ":"
		lbl.custom_minimum_size = Vector2(50, 22)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(lbl)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = ts.max
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_train_slider_changed.bind(ts.key))
		row.add_child(slider)
		char_train_sliders[ts.key] = slider

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(40, 22)
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		char_train_labels[ts.key] = val_lbl

		right_vbox.add_child(row)

	# 一键满训练
	var max_train_btn := Button.new()
	max_train_btn.text = "💪 当前角色训练全满"
	max_train_btn.custom_minimum_size = Vector2(0, 32)
	max_train_btn.add_theme_font_size_override("font_size", 13)
	max_train_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	max_train_btn.pressed.connect(_on_max_current_train)
	right_vbox.add_child(max_train_btn)

	var all_max_train_btn := Button.new()
	all_max_train_btn.text = "🔥 全部角色训练全满"
	all_max_train_btn.custom_minimum_size = Vector2(0, 32)
	all_max_train_btn.add_theme_font_size_override("font_size", 13)
	all_max_train_btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	all_max_train_btn.pressed.connect(_on_max_all_train)
	right_vbox.add_child(all_max_train_btn)

	# 填充角色下拉
	for c in DataManager.characters:
		var cid: String = c.get("id", "")
		var cname: String = c.get("name", "")
		selected_char_option.add_item(cname + " (" + cid + ")")

	if selected_char_option.item_count > 0:
		selected_char_option.selected = 0


func _refresh_all() -> void:
	_refresh_currency()
	_refresh_backpack()
	_refresh_training()


func _refresh_currency() -> void:
	for key in currency_labels:
		if key == "is_dev_mode":
			var is_dev: bool = PlayerSaveManager.get_data().get("is_dev_mode", false)
			currency_labels[key].text = "开启" if is_dev else "关闭"
			currency_labels[key].add_theme_color_override("font_color", Color(0.3, 0.9, 0.5) if is_dev else Color(0.7, 0.7, 0.7))
		elif key == "backpack_info":
			pass
		else:
			var amt: int = PlayerSaveManager.get_currency(key)
			currency_labels[key].text = str(amt)


func _refresh_backpack() -> void:
	for child in backpack_list.get_children():
		child.queue_free()

	var items: Array = InventoryManager.get_all_items()
	var used: int = InventoryManager.get_used_slots()
	var cap: int = InventoryManager.get_max_slots()
	if currency_labels.has("backpack_info"):
		currency_labels["backpack_info"].text = "容量: %d / %d" % [used, cap]

	if items.size() == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "（空空如也）"
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		backpack_list.add_child(empty_lbl)
		return

	for item in items:
		var item_id: String = item.get("id", "")
		var count: int = item.get("count", 0)
		var def: Dictionary = InventoryManager.get_item_def(item_id)
		if def.is_empty():
			continue

		var name: String = def.get("name", "?")
		var rarity: String = def.get("rarity", "common")
		var itype: String = def.get("type", "")
		var c: Color = DevDataSync.get_rarity_color(rarity)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 28)

		var icon_box := ColorRect.new()
		icon_box.custom_minimum_size = Vector2(24, 24)
		icon_box.color = c
		row.add_child(icon_box)

		var name_lbl := Label.new()
		name_lbl.text = "  " + name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", c)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var count_lbl := Label.new()
		count_lbl.text = "x" + str(count)
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(count_lbl)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.custom_minimum_size = Vector2(24, 24)
		del_btn.add_theme_font_size_override("font_size", 12)
		del_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		del_btn.pressed.connect(_on_remove_item.bind(item_id, count))
		row.add_child(del_btn)

		backpack_list.add_child(row)


func _refresh_training() -> void:
	var data: Dictionary = PlayerSaveManager.get_data()
	var training: Dictionary = data.get("training", {})
	var field_level: int = training.get("field_level", 1)
	field_level_edit.text = str(field_level)

	var char_id: String = _get_selected_char_id()
	if char_id == "":
		return

	var char_trains: Dictionary = training.get("character_trains", {})
	var ct: Dictionary = char_trains.get(char_id, {})

	for ts in TRAIN_STATS:
		var key: String = ts.key
		var val: int = ct.get(key, 0)
		if char_train_sliders.has(key):
			char_train_sliders[key].value = val
		if char_train_labels.has(key):
			char_train_labels[key].text = str(val)


func _get_selected_char_id() -> String:
	if selected_char_option == null or selected_char_option.selected < 0:
		return ""
	var chars: Array = DataManager.characters
	if selected_char_option.selected >= 0 and selected_char_option.selected < chars.size():
		return chars[selected_char_option.selected].get("id", "")
	return ""


func _on_add_currency(key: String) -> void:
	var input = currency_inputs.get(key, null)
	if input == null:
		return
	var txt: String = input.text.strip_edges()
	if not txt.is_valid_int():
		print("[DevAccount] 请输入有效数字")
		return
	var amount: int = int(txt)
	if amount == 0:
		return
	if amount > 0:
		PlayerSaveManager.add_currency(key, amount)
	else:
		PlayerSaveManager.spend_currency(key, -amount)
	_refresh_currency()


func _on_max_all_currency() -> void:
	PlayerSaveManager.set_currency("fairy_coin", 99999)
	PlayerSaveManager.set_currency("spirit_ore", 9999)
	PlayerSaveManager.set_currency("crystal", 9999)
	_refresh_currency()
	print("[DevAccount] 一键满货币完成")


func _on_unlock_all_chars() -> void:
	for c in DataManager.characters:
		var cid: String = c.get("id", "")
		if cid != "":
			PlayerSaveManager.unlock_character(cid)
	print("[DevAccount] 已解锁全部角色")


func _on_add_legendary_equip() -> void:
	var legendary_ids: Array = [
		"eq_glove_legendary_01",
		"eq_jersey_legendary_01",
		"eq_shoes_legendary_01",
	]
	for eid in legendary_ids:
		InventoryManager.add_item(eid, 1)
	_refresh_backpack()
	print("[DevAccount] 已添加全套传说装备")


func _on_add_all_food() -> void:
	var all_items: Array = DevDataSync.load_items()
	for item in all_items:
		if str(item.get("type", "")) == "consumable" and str(item.get("sub_type", "")) == "food":
			InventoryManager.add_item(str(item.get("id", "")), 10)
	_refresh_backpack()
	print("[DevAccount] 已添加全部食物")


func _on_clear_backpack() -> void:
	InventoryManager.clear_all()
	_refresh_backpack()
	print("[DevAccount] 背包已清空")


func _on_remove_item(item_id: String, count: int) -> void:
	InventoryManager.remove_item(item_id, count)
	_refresh_backpack()


func _on_char_selected(_idx: int) -> void:
	_refresh_training()


func _on_train_slider_changed(val: float, key: String) -> void:
	if char_train_labels.has(key):
		char_train_labels[key].text = str(int(val))

	var char_id: String = _get_selected_char_id()
	if char_id == "":
		return
	PlayerSaveManager.set_training_bonus(char_id, key, int(val))


func _on_set_field_level() -> void:
	var txt: String = field_level_edit.text.strip_edges()
	if not txt.is_valid_int():
		return
	var lvl: int = int(txt)
	if lvl < 1:
		lvl = 1
	if lvl > 10:
		lvl = 10
	PlayerSaveManager.set_field_level(lvl)
	field_level_edit.text = str(lvl)
	print("[DevAccount] 场地等级设置为: ", lvl)


func _on_max_current_train() -> void:
	var char_id: String = _get_selected_char_id()
	if char_id == "":
		return
	for ts in TRAIN_STATS:
		PlayerSaveManager.set_training_bonus(char_id, ts.key, int(ts.max))
	_refresh_training()
	print("[DevAccount] 当前角色训练已全满")


func _on_max_all_train() -> void:
	for c in DataManager.characters:
		var cid: String = c.get("id", "")
		if cid == "":
			continue
		for ts in TRAIN_STATS:
			PlayerSaveManager.set_training_bonus(cid, ts.key, int(ts.max))
	_refresh_training()
	print("[DevAccount] 全部角色训练已全满")


func _on_close() -> void:
	closed.emit()
	queue_free()
