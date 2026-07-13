extends Control

const ROLE_DISPLAY := {
	"attacker": {"name": "主攻", "color": Color(1.0, 0.45, 0.45)},
	"defender": {"name": "防御", "color": Color(0.45, 0.65, 1.0)},
	"supporter": {"name": "辅助", "color": Color(0.45, 1.0, 0.55)},
}

const EQUIP_SLOT_INFO := {
	"glove": {"name": "手套"},
	"jersey": {"name": "球衣"},
	"shoes": {"name": "球鞋"},
}
const EQUIP_SLOT_ORDER := ["glove", "jersey", "shoes"]

signal match_started(team_a: Array[Dictionary], team_b: Array[Dictionary], player_control_index: int, player_team: String)
signal back_to_menu_requested()

var current_team: String = "a"
var team_a_data: Array[Dictionary] = []
var team_b_data: Array[Dictionary] = []
var player_control_index: int = 0
var player_control_team: String = "a"

var team_a_widgets: Array[Dictionary] = []
var team_b_widgets: Array[Dictionary] = []
var current_team_widgets: Array[Dictionary] = []

var _char_popup: Control = null
var _char_popup_player_index: int = -1
var _char_popup_team: String = ""
var _spirit_popup: Control = null
var _spirit_popup_player_index: int = -1
var _spirit_popup_team: String = ""
var _equip_popup: Control = null
var _equip_popup_player_index: int = -1
var _equip_popup_slot: String = ""
var _equip_popup_team: String = ""
var _food_popup: Control = null
var _food_popup_player_index: int = -1
var _food_popup_team: String = ""


func _ready() -> void:
	print("[DevPrep] _ready 被调用")
	_build_ui()
	_init_team_data()
	_update_all_widgets()
	
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	print("[DevPrep] 界面初始化完成")
	print("[DevPrep] 界面可见性: %s" % str(visible))
	print("[DevPrep] 界面大小: %s" % str(size))
	print("[DevPrep] 界面位置: %s" % str(position))
	print("[DevPrep] DataManager characters: %d" % (DataManager.characters.size() if DataManager else 0))
	print("[DevPrep] DataManager spirits: %d" % (DataManager.spirits.size() if DataManager else 0))
	if InventoryManager:
		print("[DevPrep] InventoryManager backpack: %d items" % InventoryManager.get_backpack_items().size())
	if NutritionManager:
		print("[DevPrep] NutritionManager foods: %d" % NutritionManager.get_all_foods().size())


func _init_team_data() -> void:
	for i in range(3):
		team_a_data.append({
			"char_id": "",
			"char_name": "未选择",
			"role": ["attacker", "defender", "supporter"][i],
			"spirit_id": "",
			"spirit_name": "未装备",
			"equipment": {"glove": "", "jersey": "", "shoes": ""},
			"food": "",
			"food_name": "未选择",
		})
		team_b_data.append({
			"char_id": "",
			"char_name": "未选择",
			"role": ["attacker", "defender", "supporter"][i],
			"spirit_id": "",
			"spirit_name": "未装备",
			"equipment": {"glove": "", "jersey": "", "shoes": ""},
			"food": "",
			"food_name": "未选择",
		})


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12, 0.95)
	add_child(bg)

	var title := Label.new()
	title.text = "🔧 开发者测试备战 🔧"
	title.position = Vector2(0, 10)
	title.size = Vector2(1280, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	add_child(title)

	var team_a_btn := Button.new()
	team_a_btn.text = "[队A] 红队"
	team_a_btn.position = Vector2(40, 60)
	team_a_btn.size = Vector2(140, 40)
	team_a_btn.toggle_mode = true
	team_a_btn.button_pressed = true
	team_a_btn.add_theme_font_size_override("font_size", 16)
	team_a_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	team_a_btn.pressed.connect(_on_switch_team.bind("a"))
	add_child(team_a_btn)

	var team_b_btn := Button.new()
	team_b_btn.text = "[队B] 蓝队"
	team_b_btn.position = Vector2(190, 60)
	team_b_btn.size = Vector2(140, 40)
	team_b_btn.toggle_mode = true
	team_b_btn.add_theme_font_size_override("font_size", 16)
	team_b_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 1.0))
	team_b_btn.pressed.connect(_on_switch_team.bind("b"))
	add_child(team_b_btn)

	var switch_hint := Label.new()
	switch_hint.text = "（点击切换编辑队伍）"
	switch_hint.position = Vector2(340, 70)
	switch_hint.add_theme_font_size_override("font_size", 12)
	switch_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_child(switch_hint)

	var team_label := Label.new()
	team_label.name = "team_label"
	team_label.text = "当前编辑: 队A (红队)"
	team_label.position = Vector2(500, 68)
	team_label.add_theme_font_size_override("font_size", 16)
	team_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	add_child(team_label)

	var random_btn := Button.new()
	random_btn.text = "🎲 随机生成两队"
	random_btn.position = Vector2(700, 60)
	random_btn.size = Vector2(160, 40)
	random_btn.add_theme_font_size_override("font_size", 14)
	random_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	random_btn.pressed.connect(_on_random_teams)
	add_child(random_btn)

	var team_a_label := Label.new()
	team_a_label.text = "=== 队A（红队）==="
	team_a_label.position = Vector2(40, 100)
	team_a_label.add_theme_font_size_override("font_size", 16)
	team_a_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	add_child(team_a_label)

	for i in range(3):
		var card := _build_player_card(i, "a")
		card["card"].position = Vector2(40 + i * 400, 130)
		team_a_widgets.append(card)
		add_child(card["card"])

	var team_b_label := Label.new()
	team_b_label.text = "=== 队B（蓝队）==="
	team_b_label.position = Vector2(40, 430)
	team_b_label.add_theme_font_size_override("font_size", 16)
	team_b_label.add_theme_color_override("font_color", Color(0.5, 0.5, 1.0))
	add_child(team_b_label)

	for i in range(3):
		var card := _build_player_card(i, "b")
		card["card"].position = Vector2(40 + i * 400, 460)
		team_b_widgets.append(card)
		add_child(card["card"])

	var control_label := Label.new()
	control_label.text = "玩家操控:"
	control_label.position = Vector2(40, 730)
	control_label.add_theme_font_size_override("font_size", 16)
	control_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	add_child(control_label)

	var team_combo := OptionButton.new()
	team_combo.name = "control_team_combo"
	team_combo.position = Vector2(130, 727)
	team_combo.size = Vector2(100, 30)
	team_combo.add_item("队A")
	team_combo.add_item("队B")
	team_combo.selected = 0
	team_combo.add_theme_font_size_override("font_size", 14)
	team_combo.item_selected.connect(_on_control_team_changed)
	add_child(team_combo)

	var player_combo := OptionButton.new()
	player_combo.name = "control_player_combo"
	player_combo.position = Vector2(240, 727)
	player_combo.size = Vector2(150, 30)
	player_combo.add_item("位置0 (主攻)")
	player_combo.add_item("位置1 (防御)")
	player_combo.add_item("位置2 (辅助)")
	player_combo.selected = 0
	player_combo.add_theme_font_size_override("font_size", 14)
	player_combo.item_selected.connect(_on_control_player_changed)
	add_child(player_combo)

	var start_btn := Button.new()
	start_btn.text = "⚔ 开始测试比赛 ⚔"
	start_btn.position = Vector2(510, 730)
	start_btn.size = Vector2(260, 50)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	start_btn.pressed.connect(_on_start_match)
	add_child(start_btn)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.position = Vector2(1150, 740)
	back_btn.size = Vector2(120, 35)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)


func _build_player_card(index: int, team: String) -> Dictionary:
	var card := Panel.new()
	card.size = Vector2(360, 280)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.15, 0.15, 0.25)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.3, 0.3, 0.5)
	card.add_theme_stylebox_override("panel", card_style)

	var team_color = Color(1.0, 0.5, 0.5) if team == "a" else Color(0.5, 0.5, 1.0)
	var team_badge := Label.new()
	team_badge.text = "队%s" % team.to_upper()
	team_badge.position = Vector2(10, 5)
	team_badge.add_theme_font_size_override("font_size", 12)
	team_badge.add_theme_color_override("font_color", team_color)
	card.add_child(team_badge)

	var pos_label := Label.new()
	pos_label.text = "位置%d" % index
	pos_label.position = Vector2(50, 5)
	pos_label.add_theme_font_size_override("font_size", 12)
	pos_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(pos_label)

	var role_btn := Button.new()
	role_btn.name = "role_btn"
	role_btn.text = "主攻"
	role_btn.position = Vector2(100, 3)
	role_btn.size = Vector2(70, 22)
	role_btn.add_theme_font_size_override("font_size", 12)
	role_btn.add_theme_color_override("font_color", ROLE_DISPLAY["attacker"]["color"])
	role_btn.pressed.connect(_on_role_clicked.bind(index, team))
	card.add_child(role_btn)

	var char_title := Label.new()
	char_title.text = "球员:"
	char_title.position = Vector2(10, 35)
	char_title.add_theme_font_size_override("font_size", 12)
	char_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(char_title)

	var char_btn := Button.new()
	char_btn.name = "char_btn"
	char_btn.text = "点击选择球员"
	char_btn.position = Vector2(60, 30)
	char_btn.size = Vector2(200, 28)
	char_btn.add_theme_font_size_override("font_size", 13)
	char_btn.pressed.connect(_on_char_select.bind(index, team))
	card.add_child(char_btn)

	var spirit_title := Label.new()
	spirit_title.text = "元灵:"
	spirit_title.position = Vector2(10, 68)
	spirit_title.add_theme_font_size_override("font_size", 12)
	spirit_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(spirit_title)

	var spirit_btn := Button.new()
	spirit_btn.name = "spirit_btn"
	spirit_btn.text = "点击选择元灵"
	spirit_btn.position = Vector2(60, 63)
	spirit_btn.size = Vector2(200, 28)
	spirit_btn.add_theme_font_size_override("font_size", 13)
	spirit_btn.pressed.connect(_on_spirit_select.bind(index, team))
	card.add_child(spirit_btn)

	var equip_title := Label.new()
	equip_title.text = "装备:"
	equip_title.position = Vector2(10, 101)
	equip_title.add_theme_font_size_override("font_size", 12)
	equip_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(equip_title)

	var equip_btns: Array[Button] = []
	var equip_x := 60
	for slot in EQUIP_SLOT_ORDER:
		var btn := Button.new()
		btn.name = "equip_%s_btn" % slot
		btn.text = EQUIP_SLOT_INFO[slot]["name"] + ": 未装备"
		btn.position = Vector2(equip_x, 96)
		btn.size = Vector2(90, 24)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_equip_select.bind(index, team, slot))
		card.add_child(btn)
		equip_btns.append(btn)
		equip_x += 100

	var food_title := Label.new()
	food_title.text = "食物:"
	food_title.position = Vector2(10, 134)
	food_title.add_theme_font_size_override("font_size", 12)
	food_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(food_title)

	var food_btn := Button.new()
	food_btn.name = "food_btn"
	food_btn.text = "点击选择食物"
	food_btn.position = Vector2(60, 129)
	food_btn.size = Vector2(200, 28)
	food_btn.add_theme_font_size_override("font_size", 13)
	food_btn.pressed.connect(_on_food_select.bind(index, team))
	card.add_child(food_btn)

	var stats_label := Label.new()
	stats_label.name = "stats_label"
	stats_label.text = "属性: --"
	stats_label.position = Vector2(10, 165)
	stats_label.size = Vector2(340, 80)
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(stats_label)

	var is_control_label := Label.new()
	is_control_label.name = "is_control_label"
	is_control_label.text = ""
	is_control_label.position = Vector2(280, 3)
	is_control_label.add_theme_font_size_override("font_size", 12)
	is_control_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	card.add_child(is_control_label)

	return {
		"card": card,
		"role_btn": role_btn,
		"char_btn": char_btn,
		"spirit_btn": spirit_btn,
		"equip_btns": equip_btns,
		"food_btn": food_btn,
		"stats_label": stats_label,
		"is_control_label": is_control_label,
	}


func _on_switch_team(team: String) -> void:
	current_team = team
	current_team_widgets = team_a_widgets if team == "a" else team_b_widgets

	for i in range(3):
		var card_a = team_a_widgets[i]["card"]
		var card_b = team_b_widgets[i]["card"]
		
		var style_a := StyleBoxFlat.new()
		style_a.bg_color = Color(0.15, 0.15, 0.25)
		style_a.set_border_width_all(2)
		style_a.border_color = Color(1.0, 0.5, 0.5) if team == "a" else Color(0.3, 0.3, 0.5)
		card_a.add_theme_stylebox_override("panel", style_a)
		
		var style_b := StyleBoxFlat.new()
		style_b.bg_color = Color(0.15, 0.15, 0.25)
		style_b.set_border_width_all(2)
		style_b.border_color = Color(0.5, 0.5, 1.0) if team == "b" else Color(0.3, 0.3, 0.5)
		card_b.add_theme_stylebox_override("panel", style_b)

	var label = get_node_or_null("team_label")
	if label:
		label.text = "当前编辑: 队%s (%s队)" % [team.to_upper(), "红" if team == "a" else "蓝"]


func _on_role_clicked(index: int, team: String) -> void:
	var team_data = team_a_data if team == "a" else team_b_data
	var roles = ["attacker", "defender", "supporter"]
	var current_idx = roles.find(team_data[index]["role"])
	var next_idx = (current_idx + 1) % 3
	team_data[index]["role"] = roles[next_idx]

	var widgets = team_a_widgets if team == "a" else team_b_widgets
	var role_info = ROLE_DISPLAY[roles[next_idx]]
	widgets[index]["role_btn"].text = role_info["name"]
	widgets[index]["role_btn"].add_theme_color_override("font_color", role_info["color"])


func _on_char_select(index: int, team: String) -> void:
	_char_popup_player_index = index
	_char_popup_team = team
	_show_char_popup()


func _show_char_popup() -> void:
	if _char_popup and is_instance_valid(_char_popup):
		_char_popup.queue_free()

	_char_popup = Control.new()
	_char_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_char_popup)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.gui_input.connect(_on_char_popup_bg_click)
	_char_popup.add_child(overlay)

	var panel := Panel.new()
	panel.offset_left = 250
	panel.offset_top = 100
	panel.offset_right = 1030
	panel.offset_bottom = 680
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	_char_popup.add_child(panel)

	var title := Label.new()
	title.text = "选择球员"
	title.position = Vector2(260, 110)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_char_popup.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.position = Vector2(940, 108)
	back_btn.size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	back_btn.pressed.connect(_close_char_popup)
	_char_popup.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.offset_left = 260
	scroll.offset_top = 150
	scroll.offset_right = 1020
	scroll.offset_bottom = 650
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(vbox)

	print("[DevPrep] 打开球员选择弹窗, DataManager=%s, characters=%d" % [str(DataManager), DataManager.characters.size() if DataManager else 0])

	if DataManager and DataManager.characters:
		for char_data in DataManager.characters:
			var char_id = char_data.get("id", "")
			var char_name = char_data.get("name", "")
			var speed = char_data.get("speed", 0)
			var attack = char_data.get("attack", 0)
			var defense = char_data.get("defense", 0)

			var btn := Button.new()
			btn.text = "%s (速度:%d 攻击:%d 防御:%d)" % [char_name, speed, attack, defense]
			btn.size = Vector2(720, 35)
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_char_selected.bind(char_id, char_name))
			vbox.add_child(btn)
			print("[DevPrep] 添加球员按钮: %s" % char_name)
	else:
		print("[DevPrep] DataManager或characters为空!")


func _on_char_popup_bg_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_char_popup()


func _close_char_popup() -> void:
	if _char_popup and is_instance_valid(_char_popup):
		_char_popup.queue_free()
	_char_popup = null


func _on_char_selected(char_id: String, char_name: String) -> void:
	var team_data = team_a_data if _char_popup_team == "a" else team_b_data
	var widgets = team_a_widgets if _char_popup_team == "a" else team_b_widgets

	team_data[_char_popup_player_index]["char_id"] = char_id
	team_data[_char_popup_player_index]["char_name"] = char_name

	widgets[_char_popup_player_index]["char_btn"].text = char_name
	_update_player_stats(_char_popup_player_index, _char_popup_team)
	_close_char_popup()


func _update_player_stats(index: int, team: String) -> void:
	var team_data = team_a_data if team == "a" else team_b_data
	var widgets = team_a_widgets if team == "a" else team_b_widgets
	var char_id = team_data[index]["char_id"]

	if char_id == "":
		widgets[index]["stats_label"].text = "属性: --"
		return

	var char_data = DataManager.get_character_by_id(char_id)
	if char_data.is_empty():
		widgets[index]["stats_label"].text = "属性: --"
		return

	var text = "属性:\n"
	text += "  速度: %d\n" % char_data.get("speed", 0)
	text += "  攻击: %d\n" % char_data.get("attack", 0)
	text += "  防御: %d\n" % char_data.get("defense", 0)
	text += "  体力: %d\n" % char_data.get("stamina", 0)
	text += "  韧性: %d\n" % char_data.get("resilience", 0)
	text += "  球速: %d" % char_data.get("ball_speed", 0)
	widgets[index]["stats_label"].text = text


func _on_spirit_select(index: int, team: String) -> void:
	_spirit_popup_player_index = index
	_spirit_popup_team = team
	_show_spirit_popup()


func _show_spirit_popup() -> void:
	if _spirit_popup and is_instance_valid(_spirit_popup):
		_spirit_popup.queue_free()

	_spirit_popup = Control.new()
	_spirit_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_spirit_popup)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.gui_input.connect(_on_spirit_popup_bg_click)
	_spirit_popup.add_child(overlay)

	var panel := Panel.new()
	panel.offset_left = 250
	panel.offset_top = 100
	panel.offset_right = 1030
	panel.offset_bottom = 680
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	_spirit_popup.add_child(panel)

	var title := Label.new()
	title.text = "选择元灵"
	title.position = Vector2(260, 110)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_spirit_popup.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.position = Vector2(940, 108)
	back_btn.size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	back_btn.pressed.connect(_close_spirit_popup)
	_spirit_popup.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.offset_left = 260
	scroll.offset_top = 150
	scroll.offset_right = 1020
	scroll.offset_bottom = 650
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spirit_popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(vbox)

	if DataManager and DataManager.spirits:
		for spirit in DataManager.spirits:
			var spirit_id = spirit.get("id", "")
			var spirit_name = spirit.get("name", "")
			var element = spirit.get("element", "")

			var btn := Button.new()
			btn.text = "%s (元素: %s)" % [spirit_name, element]
			btn.size = Vector2(720, 35)
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_spirit_selected.bind(spirit_id, spirit_name))
			vbox.add_child(btn)


func _on_spirit_popup_bg_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_spirit_popup()


func _close_spirit_popup() -> void:
	if _spirit_popup and is_instance_valid(_spirit_popup):
		_spirit_popup.queue_free()
	_spirit_popup = null


func _on_spirit_selected(spirit_id: String, spirit_name: String) -> void:
	var team_data = team_a_data if _spirit_popup_team == "a" else team_b_data
	var widgets = team_a_widgets if _spirit_popup_team == "a" else team_b_widgets

	team_data[_spirit_popup_player_index]["spirit_id"] = spirit_id
	team_data[_spirit_popup_player_index]["spirit_name"] = spirit_name

	widgets[_spirit_popup_player_index]["spirit_btn"].text = spirit_name
	_close_spirit_popup()


func _on_equip_select(index: int, team: String, slot: String) -> void:
	_equip_popup_player_index = index
	_equip_popup_team = team
	_equip_popup_slot = slot
	_show_equip_popup()


func _show_equip_popup() -> void:
	if _equip_popup and is_instance_valid(_equip_popup):
		_equip_popup.queue_free()

	_equip_popup = Control.new()
	_equip_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_equip_popup)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.gui_input.connect(_on_equip_popup_bg_click)
	_equip_popup.add_child(overlay)

	var panel := Panel.new()
	panel.offset_left = 250
	panel.offset_top = 100
	panel.offset_right = 1030
	panel.offset_bottom = 680
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	_equip_popup.add_child(panel)

	var title := Label.new()
	title.text = "选择%s" % EQUIP_SLOT_INFO[_equip_popup_slot]["name"]
	title.position = Vector2(260, 110)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_equip_popup.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.position = Vector2(940, 108)
	back_btn.size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	back_btn.pressed.connect(_close_equip_popup)
	_equip_popup.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.offset_left = 260
	scroll.offset_top = 150
	scroll.offset_right = 1020
	scroll.offset_bottom = 650
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_equip_popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(vbox)

	if InventoryManager:
		var items = InventoryManager.get_backpack_by_slot(_equip_popup_slot)
		for item in items:
			var item_id = item.get("item_id", "")
			var item_data = InventoryManager.get_item_def(item_id)
			if item_data.is_empty():
				continue

			var name = item_data.get("name", "")
			var rarity = item_data.get("rarity", "")
			var bonuses = item_data.get("stats", {})

			var bonus_text = ""
			for key in bonuses:
				bonus_text += "%s+%d " % [key, bonuses[key]]

			var btn := Button.new()
			btn.text = "%s (%s) %s" % [name, rarity, bonus_text]
			btn.size = Vector2(720, 35)
			btn.add_theme_font_size_override("font_size", 13)
			btn.pressed.connect(_on_equip_selected.bind(item_id, name))
			vbox.add_child(btn)

	var none_btn := Button.new()
	none_btn.text = "不装备"
	none_btn.size = Vector2(720, 35)
	none_btn.add_theme_font_size_override("font_size", 14)
	none_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	none_btn.pressed.connect(_on_equip_selected.bind("", "未装备"))
	vbox.add_child(none_btn)


func _on_equip_popup_bg_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_equip_popup()


func _close_equip_popup() -> void:
	if _equip_popup and is_instance_valid(_equip_popup):
		_equip_popup.queue_free()
	_equip_popup = null


func _on_equip_selected(item_id: String, item_name: String) -> void:
	var team_data = team_a_data if _equip_popup_team == "a" else team_b_data
	var widgets = team_a_widgets if _equip_popup_team == "a" else team_b_widgets

	team_data[_equip_popup_player_index]["equipment"][_equip_popup_slot] = item_id

	var slot_idx = EQUIP_SLOT_ORDER.find(_equip_popup_slot)
	if slot_idx >= 0 and slot_idx < widgets[_equip_popup_player_index]["equip_btns"].size():
		widgets[_equip_popup_player_index]["equip_btns"][slot_idx].text = "%s: %s" % [EQUIP_SLOT_INFO[_equip_popup_slot]["name"], item_name]

	_update_player_stats(_equip_popup_player_index, _equip_popup_team)
	_close_equip_popup()


func _on_food_select(index: int, team: String) -> void:
	_food_popup_player_index = index
	_food_popup_team = team
	_show_food_popup()


func _show_food_popup() -> void:
	if _food_popup and is_instance_valid(_food_popup):
		_food_popup.queue_free()

	_food_popup = Control.new()
	_food_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_food_popup)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.gui_input.connect(_on_food_popup_bg_click)
	_food_popup.add_child(overlay)

	var panel := Panel.new()
	panel.offset_left = 250
	panel.offset_top = 100
	panel.offset_right = 1030
	panel.offset_bottom = 680
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25)
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	_food_popup.add_child(panel)

	var title := Label.new()
	title.text = "选择食物"
	title.position = Vector2(260, 110)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_food_popup.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.position = Vector2(940, 108)
	back_btn.size = Vector2(80, 32)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	back_btn.pressed.connect(_close_food_popup)
	_food_popup.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.offset_left = 260
	scroll.offset_top = 150
	scroll.offset_right = 1020
	scroll.offset_bottom = 650
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_food_popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(vbox)

	if NutritionManager:
		var all_food = NutritionManager.get_all_foods()
		for food_data in all_food:
			var food_id = food_data.get("id", "")
			var food_name = food_data.get("name", "")
			if food_id == "":
				continue

			var effect = food_data.get("effect", {})
			var bonus_text = ""
			if effect.has("stat") and effect.has("value"):
				bonus_text = "%s+%d" % [effect["stat"], effect["value"]]

			var btn := Button.new()
			btn.text = "%s %s" % [food_name, bonus_text]
			btn.size = Vector2(720, 35)
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_food_selected.bind(food_id, food_name))
			vbox.add_child(btn)

	var none_btn := Button.new()
	none_btn.text = "不使用食物"
	none_btn.size = Vector2(720, 35)
	none_btn.add_theme_font_size_override("font_size", 14)
	none_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	none_btn.pressed.connect(_on_food_selected.bind("", "未选择"))
	vbox.add_child(none_btn)


func _on_food_popup_bg_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_food_popup()


func _close_food_popup() -> void:
	if _food_popup and is_instance_valid(_food_popup):
		_food_popup.queue_free()
	_food_popup = null


func _on_food_selected(food_id: String, food_name: String) -> void:
	var team_data = team_a_data if _food_popup_team == "a" else team_b_data
	var widgets = team_a_widgets if _food_popup_team == "a" else team_b_widgets

	team_data[_food_popup_player_index]["food"] = food_id
	team_data[_food_popup_player_index]["food_name"] = food_name

	widgets[_food_popup_player_index]["food_btn"].text = food_name
	_close_food_popup()


func _on_random_teams() -> void:
	if not DataManager or DataManager.characters.size() < 6:
		return

	var chars = DataManager.characters.duplicate()
	chars.shuffle()

	var spirits = []
	if DataManager.spirits.size() > 0:
		spirits = DataManager.spirits.duplicate()

	var gloves = []
	var jerseys = []
	var shoes = []
	if InventoryManager:
		for item in InventoryManager.get_backpack_by_slot("glove"):
			var iid = item.get("item_id", "")
			var def = InventoryManager.get_item_def(iid)
			if not def.is_empty():
				gloves.append({"id": iid, "name": def.get("name", "")})
		for item in InventoryManager.get_backpack_by_slot("jersey"):
			var iid = item.get("item_id", "")
			var def = InventoryManager.get_item_def(iid)
			if not def.is_empty():
				jerseys.append({"id": iid, "name": def.get("name", "")})
		for item in InventoryManager.get_backpack_by_slot("shoes"):
			var iid = item.get("item_id", "")
			var def = InventoryManager.get_item_def(iid)
			if not def.is_empty():
				shoes.append({"id": iid, "name": def.get("name", "")})

	var foods = []
	if NutritionManager:
		var all_food = NutritionManager.get_all_foods()
		for food_data in all_food:
			var fid = food_data.get("id", "")
			if fid != "":
				foods.append({"id": fid, "name": food_data.get("name", "")})

	for i in range(3):
		var char_info = chars[i]
		var spirit = spirits[i % spirits.size()] if spirits.size() > 0 else {}

		team_a_data[i]["char_id"] = char_info.get("id", "")
		team_a_data[i]["char_name"] = char_info.get("name", "")
		team_a_data[i]["spirit_id"] = spirit.get("id", "")
		team_a_data[i]["spirit_name"] = spirit.get("name", "未装备")

		if gloves.size() > 0:
			var glove = gloves[i % gloves.size()]
			team_a_data[i]["equipment"]["glove"] = glove["id"]
		if jerseys.size() > 0:
			var jersey = jerseys[i % jerseys.size()]
			team_a_data[i]["equipment"]["jersey"] = jersey["id"]
		if shoes.size() > 0:
			var shoe = shoes[i % shoes.size()]
			team_a_data[i]["equipment"]["shoes"] = shoe["id"]

		if foods.size() > 0:
			var food = foods[i % foods.size()]
			team_a_data[i]["food"] = food["id"]
			team_a_data[i]["food_name"] = food["name"]

		var char_b = chars[i + 3]
		var spirit_b = spirits[(i + 3) % spirits.size()] if spirits.size() > 0 else {}

		team_b_data[i]["char_id"] = char_b.get("id", "")
		team_b_data[i]["char_name"] = char_b.get("name", "")
		team_b_data[i]["spirit_id"] = spirit_b.get("id", "")
		team_b_data[i]["spirit_name"] = spirit_b.get("name", "未装备")

		if gloves.size() > 0:
			var glove_b = gloves[(i + 3) % gloves.size()]
			team_b_data[i]["equipment"]["glove"] = glove_b["id"]
		if jerseys.size() > 0:
			var jersey_b = jerseys[(i + 3) % jerseys.size()]
			team_b_data[i]["equipment"]["jersey"] = jersey_b["id"]
		if shoes.size() > 0:
			var shoe_b = shoes[(i + 3) % shoes.size()]
			team_b_data[i]["equipment"]["shoes"] = shoe_b["id"]

		if foods.size() > 0:
			var food_b = foods[(i + 3) % foods.size()]
			team_b_data[i]["food"] = food_b["id"]
			team_b_data[i]["food_name"] = food_b["name"]

	_update_all_widgets()


func _update_all_widgets() -> void:
	for i in range(3):
		for team in ["a", "b"]:
			var widgets = team_a_widgets if team == "a" else team_b_widgets
			var data = team_a_data if team == "a" else team_b_data

			var role_info = ROLE_DISPLAY[data[i]["role"]]
			widgets[i]["role_btn"].text = role_info["name"]
			widgets[i]["role_btn"].add_theme_color_override("font_color", role_info["color"])

			widgets[i]["char_btn"].text = data[i]["char_name"]
			widgets[i]["spirit_btn"].text = data[i]["spirit_name"]

			for j in range(EQUIP_SLOT_ORDER.size()):
				var slot = EQUIP_SLOT_ORDER[j]
				var item_id = data[i]["equipment"][slot]
				var item_name = "未装备"
				if item_id != "":
					var item_data = InventoryManager.get_item_def(item_id)
					if not item_data.is_empty():
						item_name = item_data.get("name", "未装备")
				widgets[i]["equip_btns"][j].text = "%s: %s" % [EQUIP_SLOT_INFO[slot]["name"], item_name]

			widgets[i]["food_btn"].text = data[i]["food_name"]
			_update_player_stats(i, team)


func _on_control_team_changed(index: int) -> void:
	player_control_team = "a" if index == 0 else "b"
	_update_control_display()


func _on_control_player_changed(index: int) -> void:
	player_control_index = index
	_update_control_display()


func _update_control_display() -> void:
	for i in range(3):
		for team in ["a", "b"]:
			var widgets = team_a_widgets if team == "a" else team_b_widgets
			var is_control = team == player_control_team and i == player_control_index
			widgets[i]["is_control_label"].text = "👤玩家操控" if is_control else ""


func _on_start_match() -> void:
	var has_team_a = false
	var has_team_b = false

	for data in team_a_data:
		if data["char_id"] != "":
			has_team_a = true
			break

	for data in team_b_data:
		if data["char_id"] != "":
			has_team_b = true
			break

	if not has_team_a or not has_team_b:
		var msg = Label.new()
		msg.text = "请至少为两队各选择一名球员!"
		msg.position = Vector2(500, 700)
		msg.add_theme_font_size_override("font_size", 16)
		msg.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		add_child(msg)
		get_tree().create_timer(2.0).timeout.connect(msg.queue_free)
		return

	match_started.emit(team_a_data, team_b_data, player_control_index, player_control_team)
	visible = false


func _on_back() -> void:
	back_to_menu_requested.emit()
	visible = false