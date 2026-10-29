extends Control

## U1 · 暂停菜单（美术UI线乙线窗口 · 2026-10-28）
## 职责：只出面板与信号——继续/重开/设置/退出四键；真正暂停游戏树=实现窗口接线（挂 open/close 即可）
## 信号：resume_requested / restart_requested / settings_requested / quit_requested
## 注意：process_mode=ALWAYS，游戏树暂停时本面板仍可交互

signal resume_requested
signal restart_requested
signal settings_requested
signal quit_requested


func _ready() -> void:
	theme = UiTheme.shared()
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	var c: Color = UiPalette.col("semantic.bg_base")
	dim.color = Color(c.r, c.g, c.b, 0.78)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "PanelHighlighted"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -190
	panel.offset_bottom = 190
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var head := Label.new()
	head.text = "暂停"
	head.theme_type_variation = "LblTitle"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sp0 := Control.new()
	sp0.custom_minimum_size = Vector2(0, 4)
	v.add_child(sp0)

	var defs := [
		["继续比赛", "BtnPrimary", resume_requested],
		["重新开始", "Button", restart_requested],
		["设 置", "Button", settings_requested],
		["退出对局", "BtnDanger", quit_requested],
	]
	for d in defs:
		var b := Button.new()
		b.text = d[0]
		b.theme_type_variation = d[1]
		b.custom_minimum_size = Vector2(300, 44)
		b.pressed.connect(func() -> void:
			close()
			(d[2] as Signal).emit())
		b.mouse_entered.connect(func() -> void: UiMotion.hover_pop(b))
		v.add_child(b)


func open() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, UiMotion.num("tween.fade_in.dur", 0.25))


func close() -> void:
	visible = false
	modulate.a = 1.0


func is_open() -> bool:
	return visible
