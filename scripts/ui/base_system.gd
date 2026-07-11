extends Control

## 基地主界面
## 依赖：PlayerSaveManager（货币显示）、InventoryManager（背包数据）、TrainingManager（训练数据）

var _current_tab: String = "equipment"
var _currency_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	
	_build_base_ui()


func _build_base_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.size = Vector2(1440, 900)
	bg.color = Color(0.08, 0.1, 0.15)
	add_child(bg)
	
	# 顶部标题栏
	var title_bar := ColorRect.new()
	title_bar.name = "TitleBar"
	title_bar.size = Vector2(1440, 80)
	title_bar.color = Color(0.12, 0.15, 0.22)
	add_child(title_bar)
	
	# 标题
	var title := Label.new()
	title.name = "Title"
	title.text = "基地"
	title.position = Vector2(50, 20)
	title.size = Vector2(200, 40)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	add_child(title)
	
	# 关闭按钮
	var btn_close := Button.new()
	btn_close.name = "BtnClose"
	btn_close.text = "×"
	btn_close.position = Vector2(1390, 20)
	btn_close.size = Vector2(40, 40)
	btn_close.add_theme_font_size_override("font_size", 28)
	btn_close.add_theme_color_override("font_color", Color(0.7, 0.6, 0.6))
	btn_close.pressed.connect(_on_close)
	add_child(btn_close)
	
	# 货币栏
	_build_currency_bar()
	
	# 左侧导航栏
	_build_navigation()
	
	# 右侧内容区背景
	var content_bg := ColorRect.new()
	content_bg.name = "ContentBg"
	content_bg.position = Vector2(220, 80)
	content_bg.size = Vector2(1220, 820)
	content_bg.color = Color(0.06, 0.08, 0.12, 0.98)
	add_child(content_bg)
	
	# 默认显示装备模块
	_show_tab("equipment")


func _build_currency_bar() -> void:
	var start_x := 500
	var spacing := 220
	
	var currencies: Array = [
		{"key": "fairy_coin", "name": "童话币", "color": Color(1.0, 0.9, 0.6)},
		{"key": "spirit_ore", "name": "元灵矿石", "color": Color(0.6, 0.8, 1.0)},
		{"key": "crystal", "name": "水晶", "color": Color(0.8, 0.6, 1.0)}
	]
	
	for i in range(currencies.size()):
		var curr = currencies[i]
		var x := start_x + i * spacing
		
		var label_name := Label.new()
		label_name.name = "CurrencyName_%s" % curr.key
		label_name.text = curr.name
		label_name.position = Vector2(x, 25)
		label_name.size = Vector2(100, 20)
		label_name.add_theme_font_size_override("font_size", 14)
		label_name.add_theme_color_override("font_color", curr.color)
		add_child(label_name)
		
		var label_value := Label.new()
		label_value.name = "CurrencyValue_%s" % curr.key
		label_value.text = "0"
		label_value.position = Vector2(x, 48)
		label_value.size = Vector2(150, 22)
		label_value.add_theme_font_size_override("font_size", 18)
		label_value.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		add_child(label_value)
		
		_currency_labels[curr.key] = label_value
	
	_update_currency_display()


func _update_currency_display() -> void:
	if not PlayerSaveManager:
		return
	
	for key in _currency_labels:
		if _currency_labels.has(key) and is_instance_valid(_currency_labels[key]):
			var value: int = PlayerSaveManager.get_currency(key)
			_currency_labels[key].text = str(value)


func _build_navigation() -> void:
	var nav_bg := ColorRect.new()
	nav_bg.name = "NavBg"
	nav_bg.position = Vector2(0, 80)
	nav_bg.size = Vector2(220, 820)
	nav_bg.color = Color(0.1, 0.12, 0.18, 0.98)
	add_child(nav_bg)
	
	var nav_items: Array = [
		{"id": "equipment", "name": "装备", "icon": "👜"},
		{"id": "training", "name": "训练", "icon": "💪"},
		{"id": "nutrition", "name": "营养", "icon": "🍎"},
		{"id": "shop", "name": "商店", "icon": "🏪"}
	]
	
	var start_y := 100
	var spacing := 75
	
	for i in range(nav_items.size()):
		var item = nav_items[i]
		var y := start_y + i * spacing
		
		var btn := Button.new()
		btn.name = "NavBtn_%s" % item.id
		btn.text = "%s %s" % [item.icon, item.name]
		btn.position = Vector2(20, y)
		btn.size = Vector2(180, 55)
		btn.add_theme_font_size_override("font_size", 18)
		
		if item.id == _current_tab:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		else:
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		
		btn.pressed.connect(func(): _switch_tab(item.id))
		add_child(btn)


func _switch_tab(tab_id: String) -> void:
	if tab_id == _current_tab:
		return
	
	_current_tab = tab_id
	
	for btn in get_children():
		if btn.name.begins_with("NavBtn_"):
			var btn_tab_id = btn.name.replace("NavBtn_", "")
			if btn_tab_id == tab_id:
				btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
			else:
				btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	
	_show_tab(tab_id)


func _show_tab(tab_id: String) -> void:
	for child in get_children():
		if child.name.begins_with("TabContent_"):
			child.queue_free()
	
	match tab_id:
		"equipment":
			_show_equipment_tab()
		"training":
			_show_training_tab()
		"nutrition":
			_show_nutrition_tab()
		"shop":
			_show_shop_tab()


func _show_equipment_tab() -> void:
	var content := VBoxContainer.new()
	content.name = "TabContent_Equipment"
	content.position = Vector2(240, 90)
	content.size = Vector2(1180, 810)
	add_child(content)
	
	var title := Label.new()
	title.text = "装备管理"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	content.add_child(title)
	
	var desc := Label.new()
	desc.text = "背包装备列表，点击查看详情"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	content.add_child(desc)
	
	content.add_spacer(10)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	var equip_list: Array = []
	if InventoryManager:
		equip_list = InventoryManager.get_backpack_equipment()
	
	if equip_list.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "背包暂无装备"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		grid.add_child(empty_label)
	else:
		for entry in equip_list:
			var item_id: String = entry.get("item_id", "")
			var item_def: Dictionary = {}
			if InventoryManager:
				item_def = InventoryManager.get_item_def(item_id)
			var card := _create_item_card(item_def, entry.get("count", 1))
			grid.add_child(card)


func _create_item_card(item_def: Dictionary, count: int) -> Control:
	var card := Control.new()
	card.size = Vector2(270, 100)
	card.custom_minimum_size = Vector2(270, 100)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.15, 0.22, 0.98)
	card.add_child(bg)
	
	var icon_path: String = item_def.get("icon", "")
	var item_name: String = item_def.get("name", "未知物品")
	var rarity: String = item_def.get("rarity", "common")
	var item_type: String = item_def.get("type", "")
	var sub_type: String = item_def.get("sub_type", "")
	
	var rarity_color := Color(0.7, 0.7, 0.7)
	if InventoryManager and InventoryManager.has_method("get_rarity_color"):
		rarity_color = InventoryManager.get_rarity_color(rarity)
	
	var final_icon_path: String = ""
	if icon_path != "" and ResourceLoader.exists(icon_path):
		final_icon_path = icon_path
		print("[Base] ✓ 图标路径有效: %s" % icon_path)
	else:
		final_icon_path = _get_fallback_icon_path(item_type, sub_type, rarity)
		print("[Base] ! fallback: %s" % final_icon_path)
	
	if final_icon_path != "":
		var tex = load(final_icon_path)
		if tex is Texture2D:
			var icon_bg := ColorRect.new()
			icon_bg.position = Vector2(8, 8)
			icon_bg.size = Vector2(80, 80)
			icon_bg.color = Color(0.08, 0.1, 0.15)
			icon_bg.z_index = 5
			card.add_child(icon_bg)
			
			var icon_rect := TextureRect.new()
			icon_rect.position = Vector2(8, 8)
			icon_rect.size = Vector2(80, 80)
			icon_rect.texture = tex
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			icon_rect.clip_contents = true
			icon_rect.z_index = 10
			card.add_child(icon_rect)
		else:
			print("[Base] ✗ 加载失败")
	else:
		print("[Base] ✗ 无可用图标路径")
	
	var name_label := Label.new()
	name_label.text = item_name
	name_label.position = Vector2(96, 10)
	name_label.size = Vector2(160, 25)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", rarity_color)
	card.add_child(name_label)
	
	var stats_dict: Dictionary = item_def.get("stats", {})
	var effect_dict: Dictionary = item_def.get("effect", {})
	var stat_text: String = ""
	
	if stats_dict.size() > 0:
		var idx: int = 0
		for key in stats_dict:
			var val = stats_dict[key]
			if stat_text != "":
				stat_text += "\n"
			stat_text += "%s +%s" % [key, str(val)]
			idx += 1
			if idx >= 2:
				break
	
	if effect_dict.size() > 0 and stat_text == "":
		var effect_stat: String = effect_dict.get("stat", "")
		var effect_val = effect_dict.get("value", 0)
		stat_text = "%s +%s" % [effect_stat, str(effect_val)]
	
	if stat_text == "":
		stat_text = "暂无属性"
	
	var stats_label := Label.new()
	stats_label.text = stat_text
	stats_label.position = Vector2(96, 40)
	stats_label.size = Vector2(160, 50)
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card.add_child(stats_label)
	
	if count > 1:
		var count_label := Label.new()
		count_label.text = "x%d" % count
		count_label.position = Vector2(230, 10)
		count_label.size = Vector2(30, 20)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
		card.add_child(count_label)
	
	return card


func _get_fallback_icon_path(item_type: String, sub_type: String, rarity: String) -> String:
	var fallback_paths: Array = []
	
	if item_type == "equipment":
		if sub_type == "glove":
			fallback_paths = [
				"res://assets/icons/items/equipment/glove_%s.png" % rarity,
				"res://assets/icons/items/equipment/glove_rare.png"
			]
		elif sub_type == "jersey":
			fallback_paths = [
				"res://assets/icons/items/equipment/jersey_%s.png" % rarity,
				"res://assets/icons/items/equipment/jersey_rare.png"
			]
		elif sub_type == "shoes":
			fallback_paths = [
				"res://assets/icons/items/equipment/shoes_%s.png" % rarity,
				"res://assets/icons/items/equipment/shoes_rare.png"
			]
		else:
			fallback_paths = [
				"res://assets/icons/items/equipment/glove_rare.png"
			]
	elif item_type == "consumable" or sub_type == "food":
		fallback_paths = [
			"res://assets/icons/items/food/food_%s.png" % rarity,
			"res://assets/icons/items/food/food_rare.png"
		]
	else:
		fallback_paths = [
			"res://assets/icons/items/equipment/glove_rare.png",
			"res://assets/icons/items/food/food_rare.png"
		]
	
	for path in fallback_paths:
		if ResourceLoader.exists(path):
			return path
	
	return ""


func _show_training_tab() -> void:
	var content := VBoxContainer.new()
	content.name = "TabContent_Training"
	content.position = Vector2(240, 90)
	content.size = Vector2(1180, 810)
	add_child(content)
	
	var title := Label.new()
	title.text = "训练场地"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	content.add_child(title)
	
	var field_level := 1
	if TrainingManager and TrainingManager.has_method("get_field_level"):
		field_level = TrainingManager.get_field_level()
	
	var level_label := Label.new()
	level_label.text = "当前场地等级: Lv.%d" % field_level
	level_label.add_theme_font_size_override("font_size", 16)
	level_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	content.add_child(level_label)
	
	content.add_spacer(10)
	
	var btn_upgrade := Button.new()
	btn_upgrade.text = "升级场地"
	btn_upgrade.size = Vector2(200, 45)
	btn_upgrade.add_theme_font_size_override("font_size", 16)
	btn_upgrade.pressed.connect(_on_upgrade_field)
	content.add_child(btn_upgrade)
	
	content.add_spacer(10)
	
	var training_title := Label.new()
	training_title.text = "球员训练"
	training_title.add_theme_font_size_override("font_size", 18)
	training_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	content.add_child(training_title)
	
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(grid)
	
	var stats: Array = [
		{"key": "attack", "name": "攻击", "icon": "⚔️"},
		{"key": "defense", "name": "防御", "icon": "🛡️"},
		{"key": "speed", "name": "速度", "icon": "⚡"},
		{"key": "stamina", "name": "体力", "icon": "❤️"},
		{"key": "resilience", "name": "韧性", "icon": "💎"},
		{"key": "ball_speed", "name": "球速", "icon": "⚽"}
	]
	
	for stat in stats:
		var card := _create_training_card(stat.key, stat.name, stat.icon)
		grid.add_child(card)


func _create_training_card(stat_key: String, stat_name: String, icon: String) -> ColorRect:
	var card := ColorRect.new()
	card.size = Vector2(380, 100)
	card.color = Color(0.12, 0.15, 0.22, 0.98)
	
	var label_name := Label.new()
	label_name.text = "%s %s" % [icon, stat_name]
	label_name.position = Vector2(20, 10)
	label_name.size = Vector2(340, 25)
	label_name.add_theme_font_size_override("font_size", 18)
	label_name.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	card.add_child(label_name)
	
	var label_value := Label.new()
	label_value.text = "当前: 0 / 上限: 0"
	label_value.position = Vector2(20, 40)
	label_value.size = Vector2(340, 20)
	label_value.add_theme_font_size_override("font_size", 14)
	label_value.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card.add_child(label_value)
	
	var btn_train := Button.new()
	btn_train.text = "训练 (+2)"
	btn_train.position = Vector2(260, 60)
	btn_train.size = Vector2(100, 30)
	btn_train.add_theme_font_size_override("font_size", 14)
	btn_train.pressed.connect(func(): print("[Base] 训练 %s" % stat_key))
	card.add_child(btn_train)
	
	return card


func _show_nutrition_tab() -> void:
	var content := VBoxContainer.new()
	content.name = "TabContent_Nutrition"
	content.position = Vector2(240, 90)
	content.size = Vector2(1180, 810)
	add_child(content)
	
	var title := Label.new()
	title.text = "营养系统"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	content.add_child(title)
	
	var desc := Label.new()
	desc.text = "赛前食用食物，全队获得属性加成（整场比赛有效）"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	content.add_child(desc)
	
	content.add_spacer(10)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	
	var food_list: Array = []
	if InventoryManager:
		food_list = InventoryManager.get_backpack_consumables()
	
	if food_list.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "背包暂无食物"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		grid.add_child(empty_label)
	else:
		for entry in food_list:
			var item_id: String = entry.get("item_id", "")
			var item_def: Dictionary = {}
			if InventoryManager:
				item_def = InventoryManager.get_item_def(item_id)
			
			if item_def.is_empty() and NutritionManager:
				if NutritionManager.has_method("get_food"):
					var food_data: Dictionary = NutritionManager.get_food(item_id)
					if food_data:
						item_def = food_data
			
			var card := _create_item_card(item_def, entry.get("count", 1))
			grid.add_child(card)


func _show_shop_tab() -> void:
	var content := VBoxContainer.new()
	content.name = "TabContent_Shop"
	content.position = Vector2(240, 90)
	content.size = Vector2(1180, 810)
	add_child(content)
	
	var title := Label.new()
	title.text = "商店"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	content.add_child(title)
	
	var desc := Label.new()
	desc.text = "购买装备和食物（暂未开放）"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	content.add_child(desc)
	
	content.add_spacer(10)
	
	var label_coming := Label.new()
	label_coming.text = "🛒 商店功能开发中..."
	label_coming.position = Vector2(400, 300)
	label_coming.size = Vector2(400, 40)
	label_coming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_coming.add_theme_font_size_override("font_size", 24)
	label_coming.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	content.add_child(label_coming)


func _on_close() -> void:
	emit_signal("closed")
	queue_free()


func _on_open_inventory() -> void:
	print("[Base] 打开背包")


func _on_upgrade_field() -> void:
	if TrainingManager and TrainingManager.has_method("upgrade_field"):
		var success = TrainingManager.upgrade_field()
		if success:
			_update_currency_display()
			_switch_tab("training")
			print("[Base] 场地升级成功")
		else:
			print("[Base] 场地升级失败")
	else:
		print("[Base] TrainingManager 未找到")


func _on_go_to_preparation() -> void:
	print("[Base] 前往备战界面")
	_on_close()
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")


func _on_view_food() -> void:
	print("[Base] 查看食物 - 请使用'前往备战界面选食物'按钮")


signal closed
