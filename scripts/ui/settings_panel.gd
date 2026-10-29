extends Control

## U1 · 设置页（美术UI线乙线窗口 · 2026-10-28 · 长停留规范首批适用）
## 职责：只出面板与信号——音量/画质/窗口滑杆与选项；持久化与生效=实现窗口接 setting_changed
## 信号：setting_changed(key, value) / close_requested
## 键位表为占位显示，正式键位以操控域《键位占用表》为准（甲线对接中）

signal setting_changed(key: String, value: Variant)
signal close_requested

const KEYBIND_PLACEHOLDER := [
	["移动", "W A S D / 点按地面"],
	["投球 / 瞄准", "鼠标左键（按住瞄准）"],
	["释放技能", "1 · 2 · 3"],
	["切换球员", "Tab"],
	["暂停", "Esc"],
]


func _ready() -> void:
	theme = UiTheme.shared()
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	var c: Color = UiPalette.col("semantic.bg_base")
	dim.color = Color(c.r, c.g, c.b, 0.82)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "PanelHighlighted"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -280
	panel.offset_bottom = 280
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := Label.new()
	head.text = "设置"
	head.theme_type_variation = "LblTitle"
	v.add_child(head)

	# —— 音频（U0-6 §四：数值走 N1 数值档）——
	v.add_child(_section("音频"))
	v.add_child(_slider_row("volume_master", "主音量", 80))
	v.add_child(_slider_row("volume_music", "音乐音量", 70))
	v.add_child(_slider_row("volume_sfx", "音效音量", 80))

	# —— 画面 ——
	v.add_child(_section("画面"))
	var quality := OptionButton.new()
	quality.add_item("低")
	quality.add_item("中")
	quality.add_item("高")
	quality.select(1)
	quality.item_selected.connect(func(idx: int) -> void: setting_changed.emit("quality", idx))
	v.add_child(_row("画质", quality))
	var window_mode := OptionButton.new()
	window_mode.add_item("窗口")
	window_mode.add_item("全屏")
	window_mode.select(0)
	window_mode.item_selected.connect(func(idx: int) -> void: setting_changed.emit("window_mode", idx))
	v.add_child(_row("窗口模式", window_mode))

	# —— 键位（占位显示）——
	v.add_child(_section("键位"))
	for kb in KEYBIND_PLACEHOLDER:
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = str(kb[0])
		k.theme_type_variation = "LblCaption"
		k.custom_minimum_size = Vector2(150, 0)
		row.add_child(k)
		var val := Label.new()
		val.text = str(kb[1])
		val.theme_type_variation = "LblCaption"
		row.add_child(val)
		v.add_child(row)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)

	var back := Button.new()
	back.text = "返 回"
	back.theme_type_variation = "BtnGhost"
	back.pressed.connect(func() -> void:
		visible = false
		close_requested.emit())
	v.add_child(back)


func _section(title: String) -> Label:
	var lb := Label.new()
	lb.text = title
	lb.theme_type_variation = "LblSection"
	return lb


func _row(name: String, ctrl: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lb := Label.new()
	lb.text = name
	lb.custom_minimum_size = Vector2(120, 0)
	row.add_child(lb)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	return row


func _slider_row(key: String, name: String, default_val: int) -> HBoxContainer:
	var row := _row(name, _make_slider(key, default_val))
	return row


func _make_slider(key: String, default_val: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = default_val
	slider.custom_minimum_size = Vector2(360, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var num := Label.new()
	num.text = str(default_val)
	num.theme_type_variation = "LblNum"
	num.custom_minimum_size = Vector2(34, 0)
	slider.value_changed.connect(func(val: float) -> void:
		num.text = str(roundi(val))
		setting_changed.emit(key, val))
	box.add_child(slider)
	box.add_child(num)
	return box


func open() -> void:
	visible = true


func close() -> void:
	visible = false
