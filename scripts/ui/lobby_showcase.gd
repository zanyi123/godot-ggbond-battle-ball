extends Control

## U0-7 · 协会大厅样张实机化 v1（美术UI线乙线窗口 · 2026-10-28 · 主人目检定板用）
## 目检入口：项目根 `run_lobby_showcase.bat`（或 Godot 打开本场景直接 F5）
## 纪律：色=UiPalette（1027-2 已锁）、框件=UiTheme（1027-1 科技赛事流）、动效=UiMotion——本脚本零硬编码色值
## 范围：v3 网页样张的大厅视图（星空/光疤/蓝白星/左列菜单/主按钮/货币栏/元素条/底栏）；
##       新闻跑马灯/残骸环/竖排装饰字归样张 v2 增量；挂接归实现窗口（本场景独立，不进游戏流程）

const MENU_ITEMS := [
	["快速比赛", "QUICK MATCH", true],
	["联机对战", "NETWORK", false],
	["球员档案", "ARCHIVE", false],
	["源兽图鉴", "CODEX", false],
	["环恒源据点", "BASE", false],
	["源材交易所", "EXCHANGE", false],
	["设置", "SETTINGS", false],
]


func _ready() -> void:
	theme = UiTheme.shared()
	_build_sky()
	_build_stars()
	_build_scar()
	_build_planet()
	_build_scrim()
	_build_topbar()
	_build_menu()
	_build_element_row()
	_build_footer()


# ---------- 环境层 ----------

func _build_sky() -> void:
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


func _build_stars() -> void:
	var stars := StarField.new()
	stars.set_anchors_preset(PRESET_FULL_RECT)
	add_child(stars)


class StarField extends Control:
	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261028
		for i in 120:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y * 0.82)
			draw_circle(p, rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.2, 0.85)))


func _build_scar() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.32, 0.62, 1.0])
	grad.colors = PackedColorArray([
		UiPalette.col("scene.scar_core"),
		UiPalette.col("scene.scar_mid"),
		UiPalette.col("scene.scar_outer"),
		Color(UiPalette.col("scene.scar_outer"), 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 512
	gt.height = 512
	var scar := TextureRect.new()
	scar.texture = gt
	scar.stretch_mode = TextureRect.STRETCH_SCALE
	scar.anchor_left = 0.5
	scar.anchor_right = 0.5
	scar.offset_left = -400
	scar.offset_right = 400
	scar.offset_top = -170
	scar.offset_bottom = 350
	add_child(scar)
	UiMotion.breathe(scar)

	var ring := ScarRing.new()
	ring.set_anchors_preset(PRESET_FULL_RECT)
	add_child(ring)


class ScarRing extends Control:
	func _draw() -> void:
		var center := Vector2(size.x * 0.5, size.y * 0.16)
		var radius: float = minf(size.x * 0.24, 340.0)
		draw_set_transform(center, -0.06, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, UiPalette.col("scene.scar_ring"), 2.0, true)
		draw_arc(Vector2.ZERO, radius * 1.28, 0.0, TAU, 64, Color(UiPalette.col("scene.scar_ring"), 0.45), 1.0, true)


func _build_planet() -> void:
	var planet := PlanetView.new()
	planet.set_anchors_preset(PRESET_FULL_RECT)
	add_child(planet)


class PlanetView extends Control:
	func _draw() -> void:
		var r: float = minf(size.x * 0.42, 560.0)
		var center := Vector2(size.x * 0.76, size.y + r * 0.58)
		draw_circle(center, r, UiPalette.col("scene.planet_deep"))
		draw_circle(center + Vector2(-r * 0.18, -r * 0.22), r * 0.94, UiPalette.col("scene.planet_mid"))
		draw_circle(center + Vector2(-r * 0.3, -r * 0.34), r * 0.55, Color(UiPalette.col("scene.planet_hi"), 0.55))
		draw_set_transform(center, 0.0, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, r * 0.99, PI, TAU, 72, UiPalette.col("scene.planet_rim"), 3.0, true)


func _build_scrim() -> void:
	var c_bg: Color = UiPalette.col("semantic.bg_base")
	var scrim := ColorRect.new()
	scrim.color = Color(c_bg.r, c_bg.g, c_bg.b, 0.86)
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	add_child(scrim)
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.34, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(c_bg, 0.95),
		Color(c_bg, 0.72),
		Color(c_bg, 0.12),
		Color(c_bg, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 8
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(fade)


# ---------- UI 层 ----------

func _build_topbar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(PRESET_TOP_WIDE)
	bar.offset_left = 30
	bar.offset_right = -30
	bar.offset_top = 18
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	var brand := VBoxContainer.new()
	var title := Label.new()
	title.text = "寻源竞球者"
	title.theme_type_variation = "LblTitle"
	var hall := Label.new()
	hall.text = "协会大厅 · HALL OF ORIGIN"
	hall.theme_type_variation = "LblCaption"
	brand.add_child(title)
	brand.add_child(hall)
	bar.add_child(brand)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_add_chip(bar, "源石", "12,580")
	_add_chip(bar, "源晶", "46")
	_add_chip(bar, "溯晶", "8")
	_add_chip(bar, "归源队 · 星火赛Ⅲ", "")


func _add_chip(bar: HBoxContainer, label: String, num: String) -> void:
	var chip := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	chip.add_child(row)
	var lb := Label.new()
	lb.text = label
	lb.theme_type_variation = "LblCaption"
	row.add_child(lb)
	if num != "":
		var n := Label.new()
		n.text = num
		n.theme_type_variation = "LblNum"
		row.add_child(n)
	bar.add_child(chip)


func _build_menu() -> void:
	var nav := VBoxContainer.new()
	nav.anchor_top = 0.5
	nav.anchor_bottom = 0.5
	nav.offset_left = 52
	nav.offset_top = -180
	nav.offset_bottom = 180
	nav.offset_right = 380
	nav.add_theme_constant_override("separation", 9)
	add_child(nav)

	var eyebrow := Label.new()
	eyebrow.text = "协会大厅 · 功能入口"
	eyebrow.theme_type_variation = "LblSection"
	nav.add_child(eyebrow)
	var eyebrow_sp := Control.new()
	eyebrow_sp.custom_minimum_size = Vector2(0, 6)
	nav.add_child(eyebrow_sp)

	for i in MENU_ITEMS.size():
		var item: Array = MENU_ITEMS[i]
		var btn := Button.new()
		btn.text = item[0]
		if item[2]:
			btn.theme_type_variation = "BtnPrimary"
			btn.custom_minimum_size = Vector2(320, 56)
			UiMotion.edge_sweep(btn, UiPalette.col("semantic.primary_hi"))
		else:
			btn.custom_minimum_size = Vector2(320, 42)
		_wire(btn)
		nav.add_child(btn)
		UiMotion.slide_in(btn, Vector2(-36, 0), 0.08 * i)


func _wire(btn: Button) -> void:
	btn.mouse_entered.connect(func() -> void: UiMotion.hover_pop(btn))
	btn.button_down.connect(func() -> void: UiMotion.press(btn))
	btn.button_up.connect(func() -> void: UiMotion.release(btn))


func _build_element_row() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -30
	row.offset_bottom = -64
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for ek in ["金刚", "梦幻", "草木", "大地", "冰雪", "雷火"]:
		var c: Color = UiPalette.element_color(ek)
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c, 0.10)
		sb.border_color = Color(c, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", sb)
		var lb := Label.new()
		lb.text = UiPalette.element_display(ek)
		lb.theme_type_variation = "LblCaption"
		lb.add_theme_color_override("font_color", c)
		chip.add_child(lb)
		row.add_child(chip)


func _build_footer() -> void:
	var foot := HBoxContainer.new()
	foot.set_anchors_preset(PRESET_BOTTOM_WIDE)
	foot.offset_left = 30
	foot.offset_right = -30
	foot.offset_bottom = -16
	foot.add_theme_constant_override("separation", 16)
	add_child(foot)
	var quote := Label.new()
	quote.text = "「欲往遗迹者，先证其能」——《溯源令》"
	quote.theme_type_variation = "LblCaption"
	foot.add_child(quote)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var ver := Label.new()
	ver.text = "PROTOCOL 3021 · v0.1"
	ver.theme_type_variation = "LblCaption"
	foot.add_child(ver)
	UiMotion.slide_in(foot, Vector2(0, 14))
