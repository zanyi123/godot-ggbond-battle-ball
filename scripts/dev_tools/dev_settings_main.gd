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
	center.offset_top = -80
	center.offset_right = 200
	center.offset_bottom = 80
	center.add_theme_constant_override("separation", 25)
	add_child(center)

	var btn_player := Button.new()
	btn_player.text = "球员管理"
	btn_player.custom_minimum_size = Vector2(400, 60)
	btn_player.add_theme_font_size_override("font_size", 22)
	btn_player.pressed.connect(_open_player_panel)
	center.add_child(btn_player)

	var btn_spirit := Button.new()
	btn_spirit.text = "元灵管理"
	btn_spirit.custom_minimum_size = Vector2(400, 60)
	btn_spirit.add_theme_font_size_override("font_size", 22)
	btn_spirit.pressed.connect(_open_spirit_panel)
	center.add_child(btn_spirit)


func _open_player_panel() -> void:
	_clear_current_panel()
	var panel: Control = load("res://scripts/dev_tools/dev_player_panel.gd").new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.closed.connect(_on_sub_panel_closed)
	add_child(panel)
	_current_panel = panel


func _open_spirit_panel() -> void:
	_clear_current_panel()
	var panel: Control = load("res://scripts/dev_tools/dev_spirit_panel.gd").new()
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
