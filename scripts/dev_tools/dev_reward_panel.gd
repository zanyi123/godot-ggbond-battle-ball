extends Control
class_name DevRewardPanel
## 开发者工具 - 奖励设置面板
## 调整比赛奖励数值、连胜加成、奖励开关

signal closed()

var _config: Dictionary = {}
var _spin_boxes: Dictionary = {}  # key -> SpinBox

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_config = RewardSystem.reward_config.duplicate()
	_build_ui()


func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.10, 0.98)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 标题
	var title := Label.new()
	title.text = "奖励设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	title.position = Vector2(0, 15)
	title.size = Vector2(get_viewport_rect().size.x, 40)
	add_child(title)

	# 返回按钮
	var close_btn := Button.new()
	close_btn.text = "✕ 返回"
	close_btn.position = Vector2(20, 15)
	close_btn.size = Vector2(100, 40)
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)

	# 滚动容器
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 70)
	scroll.size = Vector2(get_viewport_rect().size.x - 200, get_viewport_rect().size.y - 140)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# 奖励开关
	var enable_row := HBoxContainer.new()
	enable_row.add_theme_constant_override("separation", 15)
	vbox.add_child(enable_row)

	var enable_label := Label.new()
	enable_label.text = "奖励开关"
	enable_label.add_theme_font_size_override("font_size", 18)
	enable_label.custom_minimum_size = Vector2(200, 30)
	enable_row.add_child(enable_label)

	var enable_check := CheckBox.new()
	enable_check.text = "开启（关闭后比赛不发放奖励）"
	enable_check.button_pressed = _config.get("reward_enabled", false)
	enable_check.toggled.connect(_on_enable_toggled)
	enable_row.add_child(enable_check)

	# 分组配置
	_add_section(vbox, "胜利奖励", "win")
	_add_section(vbox, "败北奖励", "lose")
	_add_section(vbox, "平局奖励", "draw")
	_add_section(vbox, "连胜加成（每连胜一场额外）", "streak")

	# 保存按钮
	var save_btn := Button.new()
	save_btn.text = "保存配置"
	save_btn.custom_minimum_size = Vector2(200, 50)
	save_btn.add_theme_font_size_override("font_size", 20)
	save_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	save_btn.pressed.connect(_on_save)
	vbox.add_child(save_btn)

	# 当前连胜显示
	var streak_label := Label.new()
	streak_label.text = "当前连胜: %d 场" % RewardSystem.get_win_streak()
	streak_label.add_theme_font_size_override("font_size", 16)
	streak_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(streak_label)

	# 重置连胜按钮
	var reset_streak_btn := Button.new()
	reset_streak_btn.text = "重置连胜"
	reset_streak_btn.custom_minimum_size = Vector2(150, 35)
	reset_streak_btn.pressed.connect(_on_reset_streak)
	vbox.add_child(reset_streak_btn)


func _add_section(parent: VBoxContainer, title_text: String, prefix: String) -> void:
	var section_label := Label.new()
	section_label.text = title_text
	section_label.add_theme_font_size_override("font_size", 18)
	section_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	parent.add_child(section_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)

	_add_spin_box(row, prefix, "fairy_coin", "童话币", 0, 99999)
	_add_spin_box(row, prefix, "spirit_ore", "元灵矿石", 0, 9999)
	_add_spin_box(row, prefix, "crystal", "水晶", 0, 999)


func _add_spin_box(parent: HBoxContainer, prefix: String, suffix: String, label_text: String, min_val: int, max_val: int) -> void:
	var key = "%s_%s" % [prefix, suffix]

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = int(_config.get(key, 0))
	spin.custom_minimum_size = Vector2(120, 35)
	spin.suffix = ""
	vbox.add_child(spin)

	_spin_boxes[key] = spin


func _on_enable_toggled(toggled: bool) -> void:
	_config["reward_enabled"] = toggled


func _on_save() -> void:
	# 从 SpinBox 收集值
	for key in _spin_boxes:
		_config[key] = int(_spin_boxes[key].value)
	RewardSystem.update_config(_config)
	print("[DevRewardPanel] 奖励配置已保存")


func _on_reset_streak() -> void:
	RewardSystem.reset_win_streak()
	RewardSystem._save_config()
	print("[DevRewardPanel] 连胜已重置")
	# 刷新显示
	_ready()


func _on_close() -> void:
	closed.emit()
	queue_free()
