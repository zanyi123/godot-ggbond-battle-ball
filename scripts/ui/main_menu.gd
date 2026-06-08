extends Control
## 主菜单 - 游戏入口

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# 背景
	var bg := ColorRect.new()
	bg.size = Vector2(1440, 810)
	bg.color = Color(0.1, 0.1, 0.2)
	add_child(bg)
	
	# 标题
	var title := Label.new()
	title.text = "猪猪侠之决竞球"
	title.position = Vector2(470, 120)
	title.size = Vector2(500, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.YELLOW)
	add_child(title)
	
	# 开始比赛按钮
	var btn_start := Button.new()
	btn_start.text = "开始比赛"
	btn_start.position = Vector2(545, 320)
	btn_start.size = Vector2(350, 55)
	btn_start.pressed.connect(_on_start_match)
	add_child(btn_start)
	
	# 角色系统按钮
	var btn_chars := Button.new()
	btn_chars.text = "角色系统"
	btn_chars.position = Vector2(545, 395)
	btn_chars.size = Vector2(350, 55)
	btn_chars.pressed.connect(_on_open_characters)
	add_child(btn_chars)
	
	# 元灵系统按钮
	var btn_spirits := Button.new()
	btn_spirits.text = "元灵系统"
	btn_spirits.position = Vector2(545, 470)
	btn_spirits.size = Vector2(350, 55)
	btn_spirits.pressed.connect(_on_open_spirits)
	add_child(btn_spirits)
	
	# 基地按钮
	var btn_base := Button.new()
	btn_base.text = "基地"
	btn_base.position = Vector2(545, 545)
	btn_base.size = Vector2(350, 55)
	btn_base.pressed.connect(_on_open_base)
	add_child(btn_base)

	# 开发者工具按钮
	var btn_dev := Button.new()
	btn_dev.text = "快捷设置（开发者）"
	btn_dev.position = Vector2(545, 620)
	btn_dev.size = Vector2(350, 55)
	btn_dev.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	btn_dev.pressed.connect(_on_open_dev_settings)
	add_child(btn_dev)

	# 交易按钮
	var btn_trade := Button.new()
	btn_trade.text = "交易"
	btn_trade.position = Vector2(545, 695)
	btn_trade.size = Vector2(350, 55)
	btn_trade.pressed.connect(_on_open_trade)
	add_child(btn_trade)


func _on_start_match() -> void:
	# 切换到备战场景（目前直接进入比赛）
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")


func _on_open_characters() -> void:
	var CharacterSystemClass = load("res://scripts/ui/character_system.gd")
	var char_ui: Control = CharacterSystemClass.new()
	add_child(char_ui)


var spirit_ui: Control = null


func _on_open_spirits() -> void:
	# 已打开且可见 → 隐藏
	if spirit_ui and is_instance_valid(spirit_ui) and spirit_ui.visible:
		spirit_ui.visible = false
		return

	# 已打开但隐藏 → 显示
	if spirit_ui and is_instance_valid(spirit_ui):
		spirit_ui.visible = true
		return

	# 首次打开
	var script := load("res://scripts/systems/spirit_system/spirit_ui.gd")
	spirit_ui = Control.new()
	spirit_ui.name = "SpiritUI"
	spirit_ui.set_script(script)
	spirit_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(spirit_ui)

	# 关闭信号：隐藏面板
	if spirit_ui.has_signal("close_requested"):
		spirit_ui.close_requested.connect(func(): spirit_ui.visible = false)

	print("[Main] 元灵系统已打开")


func _on_open_base() -> void:
	print("[Main] 基地 - 待实现")


func _on_open_dev_settings() -> void:
	var DevSettingsClass = load("res://scripts/dev_tools/dev_settings_main.gd")
	var dev_panel: Control = DevSettingsClass.new()
	dev_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dev_panel.closed.connect(dev_panel.queue_free)
	add_child(dev_panel)
	print("[Main] 快捷设置系统已打开")


func _on_open_trade() -> void:
	print("[Main] 交易 - 待实现")
