extends Control

## U1 · 标题画面+存档位选择（美术UI线乙线窗口 · 2026-10-28）
## 流程：标题（任意键）→ 存档位三选一 → 发 slot_selected（场景跳转归实现窗口）
## 纪律：色=UiPalette/框件=UiTheme/动效=UiMotion，零硬编码色值；存档数据为占位展示，真实读档归实现窗口
## 信号：start_requested（任意键）/ slot_selected(index) / quit_requested

signal start_requested
signal slot_selected(index: int)
signal quit_requested

enum State { TITLE, SLOTS }

## 占位数据（真实读档接口归实现窗口：读 PlayerSaveManager 三槽元信息）
const PLACEHOLDER_SLOTS := [
	{"empty": false, "队名": "归源队", "进度": "星火赛 · 大区预选", "时间": "恒源纪元 3021 · 昨日"},
	{"empty": false, "队名": "新源小队", "进度": "溯源第一课 · 刚通关", "时间": "恒源纪元 3021 · 三日前"},
	{"empty": true, "队名": "—— 空 ——" , "进度": "开始新的选拔", "时间": "——"},
]

var _state: int = State.TITLE
var _slot_root: Control = null
var _title_root: Control = null


func _ready() -> void:
	theme = UiTheme.shared()
	_build_backdrop()
	_build_title()
	_build_slots()
	_build_footer()


func _build_backdrop() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		UiPalette.col("scene.sky_top"),
		UiPalette.col("scene.sky_mid"),
		UiPalette.col("scene.sky_low"),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 64
	gt.height = 256
	var sky := TextureRect.new()
	sky.texture = gt
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(PRESET_FULL_RECT)
	add_child(sky)

	var grad2 := Gradient.new()
	grad2.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad2.colors = PackedColorArray([
		UiPalette.col("scene.scar_core"),
		UiPalette.col("scene.scar_mid"),
		Color(UiPalette.col("scene.scar_outer"), 0.0),
	])
	var gt2 := GradientTexture2D.new()
	gt2.gradient = grad2
	gt2.fill = GradientTexture2D.FILL_RADIAL
	gt2.fill_from = Vector2(0.5, 0.5)
	gt2.fill_to = Vector2(1.0, 0.5)
	gt2.width = 512
	gt2.height = 512
	var scar := TextureRect.new()
	scar.texture = gt2
	scar.stretch_mode = TextureRect.STRETCH_SCALE
	scar.anchor_left = 0.5
	scar.anchor_right = 0.5
	scar.offset_left = -320
	scar.offset_right = 320
	scar.offset_top = -140
	scar.offset_bottom = 220
	add_child(scar)
	UiMotion.breathe(scar)


func _build_title() -> void:
	_title_root = Control.new()
	_title_root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_title_root)

	var title := Label.new()
	title.text = "寻源竞球者"
	title.theme_type_variation = "LblDisplay"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.32
	title.anchor_bottom = 0.32
	title.offset_left = -320
	title.offset_right = 320
	title.offset_top = -34
	title.offset_bottom = 34
	_title_root.add_child(title)

	var quote := Label.new()
	quote.text = "「欲往遗迹者，先证其能」——《溯源令》"
	quote.theme_type_variation = "LblCaption"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.anchor_left = 0.5
	quote.anchor_right = 0.5
	quote.anchor_top = 0.32
	quote.anchor_bottom = 0.32
	quote.offset_left = -280
	quote.offset_right = 280
	quote.offset_top = 44
	quote.offset_bottom = 66
	_title_root.add_child(quote)

	var press := Label.new()
	press.text = "—— 按任意键，开始选拔 ——"
	press.theme_type_variation = "LblSection"
	press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	press.anchor_left = 0.5
	press.anchor_right = 0.5
	press.anchor_top = 0.62
	press.anchor_bottom = 0.62
	press.offset_left = -240
	press.offset_right = 240
	press.offset_top = -12
	press.offset_bottom = 12
	_title_root.add_child(press)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(press, "modulate:a", 0.35, 0.9)
	tw.tween_property(press, "modulate:a", 1.0, 0.9)


func _build_slots() -> void:
	_slot_root = Control.new()
	_slot_root.set_anchors_preset(PRESET_FULL_RECT)
	_slot_root.visible = false
	add_child(_slot_root)

	var head := Label.new()
	head.text = "选择选拔记录"
	head.theme_type_variation = "LblTitle"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.anchor_left = 0.5
	head.anchor_right = 0.5
	head.anchor_top = 0.18
	head.anchor_bottom = 0.18
	head.offset_left = -200
	head.offset_right = 200
	head.offset_top = -16
	head.offset_bottom = 16
	_slot_root.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 0.5
	row.anchor_bottom = 0.5
	row.offset_left = -540
	row.offset_right = 540
	row.offset_top = -120
	row.offset_bottom = 120
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_root.add_child(row)

	for i in PLACEHOLDER_SLOTS.size():
		var data: Dictionary = PLACEHOLDER_SLOTS[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 190)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var slot_no := Label.new()
		slot_no.text = "存档 %d" % (i + 1)
		slot_no.theme_type_variation = "LblCaption"
		v.add_child(slot_no)
		var name_lb := Label.new()
		name_lb.text = str(data.get("队名", "——"))
		name_lb.theme_type_variation = "LblTitle"
		v.add_child(name_lb)
		var prog := Label.new()
		prog.text = str(data.get("进度", "——"))
		prog.theme_type_variation = "LblCaption"
		prog.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(prog)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)
		var time_lb := Label.new()
		time_lb.text = str(data.get("时间", "——"))
		time_lb.theme_type_variation = "LblCaption"
		v.add_child(time_lb)
		var pick := Button.new()
		pick.text = "进入" if not data.get("empty", true) else "开始新选拔"
		if data.get("empty", true):
			pick.theme_type_variation = "BtnGhost"
		else:
			pick.theme_type_variation = "BtnPrimary"
		var idx := i
		pick.pressed.connect(func() -> void: slot_selected.emit(idx))
		v.add_child(pick)
		row.add_child(card)
		UiMotion.slide_in(card, Vector2(0, 30), 0.08 * i)


func _build_footer() -> void:
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(PRESET_BOTTOM_WIDE)
	foot.offset_left = 30
	foot.offset_right = -30
	foot.offset_bottom = -16
	add_child(foot)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var quit := Button.new()
	quit.text = "退出"
	quit.theme_type_variation = "BtnGhost"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	foot.add_child(quit)
	var ver := Label.new()
	ver.text = "PROTOCOL 3021 · v0.1"
	ver.theme_type_variation = "LblCaption"
	foot.add_child(ver)


func _unhandled_input(event: InputEvent) -> void:
	if _state == State.TITLE:
		var pressed := false
		if event is InputEventKey and event.pressed and not event.echo:
			pressed = true
		elif event is InputEventMouseButton and event.pressed:
			pressed = true
		if pressed:
			_state = State.SLOTS
			_title_root.visible = false
			_slot_root.visible = true
			start_requested.emit()
			get_viewport().set_input_as_handled()
	elif _state == State.SLOTS and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_state = State.TITLE
		_slot_root.visible = false
		_title_root.visible = true
		get_viewport().set_input_as_handled()


func current_state() -> int:
	return _state
