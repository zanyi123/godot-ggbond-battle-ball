extends Control
class_name DevSettingsMain
## 快捷设置系统 - 开发者工具主入口
## 选择"球员管理"或"元灵管理"进入对应子系统

signal closed()

var _current_panel: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# 全屏背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.10, 0.97)
	add_child(bg)

	# 标题栏
	var title_bar := HBoxContainer.new()
	title_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_bar.offset_bottom = 0
	title_bar.offset_top = 0
	title_bar.offset_left = 0
	title_bar.offset_right = 0
	title_bar.offset_top = 15
	title_bar.offset_bottom = 60
	add_child(title_bar)

	var title := Label.new()
	title.text = "快捷设置系统（开发者工具）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(50, 40)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_on_close)
	title_bar.add_child(close_btn)

	# 选择区域
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(720, 405)
	center.offset_left = -200
	center.offset_top = -150
	center.offset_right = 200
	center.offset_bottom = 150
	center.add_theme_constant_override("separation", 20)
	add_child(center)

	var btn_account := Button.new()
	btn_account.text = "账号管理（测试工具）"
	btn_account.custom_minimum_size = Vector2(400, 55)
	btn_account.add_theme_font_size_override("font_size", 20)
	btn_account.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	btn_account.pressed.connect(_open_account_panel)
	center.add_child(btn_account)

	var btn_player := Button.new()
	btn_player.text = "球员管理"
	btn_player.custom_minimum_size = Vector2(400, 55)
	btn_player.add_theme_font_size_override("font_size", 20)
	btn_player.pressed.connect(_open_player_panel)
	center.add_child(btn_player)

	var btn_spirit := Button.new()
	btn_spirit.text = "元灵管理"
	btn_spirit.custom_minimum_size = Vector2(400, 55)
	btn_spirit.add_theme_font_size_override("font_size", 20)
	btn_spirit.pressed.connect(_open_spirit_panel)
	center.add_child(btn_spirit)

	var btn_equip := Button.new()
	btn_equip.text = "装备管理"
	btn_equip.custom_minimum_size = Vector2(400, 55)
	btn_equip.add_theme_font_size_override("font_size", 20)
	btn_equip.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	btn_equip.pressed.connect(_open_equipment_panel)
	center.add_child(btn_equip)

	var btn_food := Button.new()
	btn_food.text = "食物管理"
	btn_food.custom_minimum_size = Vector2(400, 55)
	btn_food.add_theme_font_size_override("font_size", 20)
	btn_food.add_theme_color_override("font_color", Color(0.3, 0.9, 0.6))
	btn_food.pressed.connect(_open_food_panel)
	center.add_child(btn_food)

	var btn_growth := Button.new()
	btn_growth.text = "成长曲线规划"
	btn_growth.custom_minimum_size = Vector2(400, 55)
	btn_growth.add_theme_font_size_override("font_size", 20)
	btn_growth.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	btn_growth.pressed.connect(_open_growth_panel)
	center.add_child(btn_growth)

	var btn_reward := Button.new()
	btn_reward.text = "奖励设置"
	btn_reward.custom_minimum_size = Vector2(400, 55)
	btn_reward.add_theme_font_size_override("font_size", 20)
	btn_reward.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	btn_reward.pressed.connect(_open_reward_panel)
	center.add_child(btn_reward)


func _open_account_panel() -> void:
	_clear_current_panel()
	var DevAccountPanelClass = load("res://scripts/dev_tools/dev_account_panel.gd")
	var panel: Control = DevAccountPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_player_panel() -> void:
	_clear_current_panel()
	var DevPlayerPanelClass = load("res://scripts/dev_tools/dev_player_panel.gd")
	var panel: Control = DevPlayerPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_spirit_panel() -> void:
	_clear_current_panel()
	var DevSpiritPanelClass = load("res://scripts/dev_tools/dev_spirit_panel.gd")
	var panel: Control = DevSpiritPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_equipment_panel() -> void:
	_clear_current_panel()
	var DevEquipmentPanelClass = load("res://scripts/dev_tools/dev_equipment_panel.gd")
	var panel: Control = DevEquipmentPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_food_panel() -> void:
	_clear_current_panel()
	var DevFoodPanelClass = load("res://scripts/dev_tools/dev_food_panel.gd")
	var panel: Control = DevFoodPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_growth_panel() -> void:
	_clear_current_panel()
	var DevGrowthPanelClass = load("res://scripts/dev_tools/dev_growth_panel.gd")
	var panel: Control = DevGrowthPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_reward_panel() -> void:
	_clear_current_panel()
	var DevRewardPanelClass = load("res://scripts/dev_tools/dev_reward_panel.gd")
	var panel: Control = DevRewardPanelClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _clear_current_panel() -> void:
	if _current_panel and is_instance_valid(_current_panel):
		_current_panel.queue_free()
		_current_panel = null


func _on_sub_panel_closed() -> void:
	_clear_current_panel()


func _on_close() -> void:
	closed.emit()
	queue_free()
