extends CanvasLayer

## U1 · 单机加载转场 UI 层（美术UI线乙线窗口 · 2026-10-28）
## 式样（1027-4 已批）：复用联机 VS 卡式样，对手侧剪影——甲线 7 件真图直接引用（assets/ui/frames/）
## 职责：只出转场视觉与进度显示；场景切换/真实进度信号=实现窗口（移交单01 T3）
## API：setup(ally_names, enemy_names) / set_progress(0.0~1.0) / fade_in() / fade_out()
## 信号：fade_in_done / fade_out_done

signal fade_in_done
signal fade_out_done

const TEX_BG := "res://assets/ui/frames/net_vs_bg_split.png"
const TEX_FRAME_ALLY := "res://assets/ui/frames/net_vs_cardframe_ally.png"
const TEX_FRAME_ENEMY := "res://assets/ui/frames/net_vs_cardframe_enemy.png"
const TEX_SILHOUETTE := "res://assets/ui/frames/net_vs_portrait_silhouette.png"
const TEX_EMBLEM := "res://assets/ui/frames/net_vs_emblem.png"
const TEX_PROGRESS := "res://assets/ui/frames/net_vs_progress.png"
const TEX_SLOT_LIT := "res://assets/ui/frames/net_vs_progress_slot_lit.png"
const SLOT_COUNT := 6

var _dim: ColorRect
var _vs_root: Control
var _lit_slots: Array = []
var _ally_names: Array = []
var _enemy_names: Array = []


func _ready() -> void:
	layer = 100
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	var c: Color = UiPalette.col("semantic.bg_base")
	_dim.color = c
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.modulate.a = 0.0
	add_child(_dim)

	_vs_root = Control.new()
	_vs_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vs_root.modulate.a = 0.0
	_vs_root.visible = false
	add_child(_vs_root)

	var bg := TextureRect.new()
	bg.texture = load(TEX_BG)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vs_root.add_child(bg)

	var scrim := ColorRect.new()
	scrim.color = Color(c.r, c.g, c.b, 0.45)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vs_root.add_child(scrim)

	var head := Label.new()
	head.text = "对 局 加 载"
	head.theme_type_variation = "LblTitle"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.anchor_left = 0.5
	head.anchor_right = 0.5
	head.anchor_top = 0.06
	head.anchor_bottom = 0.06
	head.offset_left = -200
	head.offset_right = 200
	head.offset_top = -16
	head.offset_bottom = 16
	_vs_root.add_child(head)

	# 左右卡列（ally=真框+剪影；enemy=敌方框+剪影，1027-4 式样）
	var col_specs := [
		{"anchor_x": 0.24, "tex": TEX_FRAME_ALLY, "names": _ally_names},
		{"anchor_x": 0.76, "tex": TEX_FRAME_ENEMY, "names": _enemy_names},
	]
	for spec in col_specs:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.anchor_left = spec["anchor_x"]
		col.anchor_right = spec["anchor_x"]
		col.anchor_top = 0.14
		col.anchor_bottom = 0.74
		col.offset_left = -135
		col.offset_right = 135
		_vs_root.add_child(col)
		var names: Array = spec["names"]
		for i in 3:
			var frame := TextureRect.new()
			frame.texture = load(spec["tex"])
			frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			frame.custom_minimum_size = Vector2(170, 180)
			var sil := TextureRect.new()
			sil.texture = load(TEX_SILHOUETTE)
			sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sil.set_anchors_preset(Control.PRESET_FULL_RECT)
			sil.offset_left = 18
			sil.offset_right = -18
			sil.offset_top = 14
			sil.offset_bottom = -14
			frame.add_child(sil)
			col.add_child(frame)
			var nm := Label.new()
			nm.text = names[i] if i < names.size() else "——"
			nm.theme_type_variation = "LblCaption"
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(nm)

	var emblem := TextureRect.new()
	emblem.texture = load(TEX_EMBLEM)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.anchor_left = 0.5
	emblem.anchor_right = 0.5
	emblem.anchor_top = 0.14
	emblem.anchor_bottom = 0.14
	emblem.offset_left = -110
	emblem.offset_right = 110
	emblem.offset_top = 60
	emblem.offset_bottom = 230
	_vs_root.add_child(emblem)
	UiMotion.breathe(emblem)

	# 六槽加载条（进度点亮）
	var bar := TextureRect.new()
	bar.texture = load(TEX_PROGRESS)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.8
	bar.anchor_bottom = 0.8
	bar.offset_left = -240
	bar.offset_right = 240
	bar.offset_top = -22
	bar.offset_bottom = 22
	_vs_root.add_child(bar)
	for i in SLOT_COUNT:
		var slot := TextureRect.new()
		slot.texture = load(TEX_SLOT_LIT)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_SCALE
		slot.visible = false
		bar.add_child(slot)
		_lit_slots.append(slot)


## 槽位在进度条内均匀分布（条宽 480px 缩放坐标系，贴图 960x88 → 显示 480x44）
func _layout_slots() -> void:
	var bar_width := 480.0
	var slot_w := 58.0
	var slot_h := 26.0
	var gap := (bar_width - slot_w * SLOT_COUNT) / (SLOT_COUNT + 1.0)
	for i in _lit_slots.size():
		var slot: TextureRect = _lit_slots[i]
		slot.offset_left = gap + i * (slot_w + gap)
		slot.offset_right = slot.offset_left + slot_w
		slot.offset_top = (44.0 - slot_h) * 0.5
		slot.offset_bottom = slot.offset_top + slot_h


## 进度 0.0~1.0 → 亮槽 0~6（离散点亮=手环六槽母题）
func set_progress(p: float) -> void:
	_layout_slots()
	var lit: int = clampi(roundi(clampf(p, 0.0, 1.0) * SLOT_COUNT), 0, SLOT_COUNT)
	for i in _lit_slots.size():
		_lit_slots[i].visible = i < lit


## 载入双方名单（各 3 人；空缺显示「——」）
func setup(ally_names: Array, enemy_names: Array) -> void:
	_ally_names = ally_names
	_enemy_names = enemy_names
	for col in _vs_root.get_children():
		if col is VBoxContainer:
			var idx := 0
			for child in col.get_children():
				if child is Label:
					var names: Array = _ally_names if col.anchor_left < 0.5 else _enemy_names
					child.text = names[idx] if idx < names.size() else "——"
					idx += 1


func fade_in() -> void:
	_vs_root.visible = true
	set_progress(0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.22)
	tw.tween_property(_vs_root, "modulate:a", 1.0, 0.3)
	tw.chain().tween_callback(func() -> void: fade_in_done.emit())


func fade_out() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.28)
	tw.tween_property(_vs_root, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(func() -> void:
		_vs_root.visible = false
		fade_out_done.emit())
