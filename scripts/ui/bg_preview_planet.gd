extends Control

## 蓝白星动态背景预览台（2026-10-30 开源资源检索窗口）
##
## 对照光疤版（bg_preview.gd）的同一管线，但「主角」不同：
##   光疤版的主角 = 光核呼吸
##   蓝白星的主角 = **大气环辉光脉动**
##
## 四层结构：
##   L1 底图      —— 即梦来图（静）
##   L2 星云      —— bg_nebula_flow（域扭曲 + 三频慢滚，仅左上星云区）
##   L3 星点×2    —— bg_star_scroll（视差，仅深空区）
##   L4 大气环    —— bg_atmo_glow（沿地平线弧线脉动）
##
## 全部 14 秒无缝循环。

const SHADER_NEBULA := "res://scripts/ui/shaders/bg_nebula_flow.gdshader"
const SHADER_STAR := "res://scripts/ui/shaders/bg_star_scroll.gdshader"
const SHADER_ATMO := "res://scripts/ui/shaders/bg_atmo_glow.gdshader"
const BG_PATH := "res://assets/ui/backgrounds/bg_planet_bluewhite_base.png"

var _layer_root: Control
var _nebula_mat: ShaderMaterial
var _star_mats: Array = []
var _atmo_mat: ShaderMaterial
var _fps_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_ui()


func _build_background() -> void:
	_layer_root = Control.new()
	_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)

	var vs: Vector2 = get_viewport_rect().size

	# ── L1 底图
	var bg := TextureRect.new()
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.position = Vector2.ZERO
	bg.size = vs
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_root.add_child(bg)

	# ── L2 星云（限定左上星云区：x<0.75, y<0.62）
	var neb := ColorRect.new()
	neb.position = Vector2.ZERO
	neb.size = Vector2(vs.x * 0.78, vs.y * 0.64)
	neb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nebula_mat = ShaderMaterial.new()
	_nebula_mat.shader = load(SHADER_NEBULA)
	_nebula_mat.set_shader_parameter("noise_tex", _make_noise())
	_nebula_mat.set_shader_parameter("loop_turns", 2.0)
	_nebula_mat.set_shader_parameter("density", 0.48)
	_nebula_mat.set_shader_parameter("contrast", 1.45)
	_nebula_mat.set_shader_parameter("dist_warp", 0.030)
	_nebula_mat.set_shader_parameter("alpha", 0.55)
	neb.material = _nebula_mat
	_layer_root.add_child(neb)

	# ── L3 星点×2（视差；铺深空区：左上，避开行星本体）
	var star_layers := [
		{"speed": 0.8, "cell": 165.0, "scale": 0.028, "density": 0.26, "br": 0.60, "alpha": 0.55},
		{"speed": 2.2, "cell": 125.0, "scale": 0.048, "density": 0.15, "br": 0.92, "alpha": 0.60},
	]
	var star_area := Vector2(vs.x, vs.y * 0.50)   # 深空只在上半 50%
	for cfg in star_layers:
		var layer := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = load(SHADER_STAR)
		m.set_shader_parameter("scroll_speed", cfg["speed"])
		m.set_shader_parameter("cell_size", cfg["cell"])
		m.set_shader_parameter("star_scale", cfg["scale"])
		m.set_shader_parameter("density", cfg["density"])
		m.set_shader_parameter("brightness", cfg["br"])
		m.set_shader_parameter("layer_size", star_area)
		m.set_shader_parameter("star_color", Color(1.0, 0.98, 0.95))
		layer.material = m
		layer.modulate.a = cfg["alpha"]
		layer.position = Vector2.ZERO
		layer.size = star_area
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_star_mats.append(m)
		_layer_root.add_child(layer)

	# ── L4 大气环辉光（沿地平线弧线脉动）
	var atmo := ColorRect.new()
	atmo.position = Vector2.ZERO
	atmo.size = vs
	atmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = load(SHADER_ATMO)
	_atmo_mat.set_shader_parameter("band_width", 0.030)
	_atmo_mat.set_shader_parameter("inner_glow", 0.075)
	_atmo_mat.set_shader_parameter("pulse_amount", 0.26)
	_atmo_mat.set_shader_parameter("pulse_turns", 2.0)
	_atmo_mat.set_shader_parameter("brightness", 0.62)
	atmo.material = _atmo_mat
	_layer_root.add_child(atmo)


func _make_noise() -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.0030
	fn.fractal_octaves = 5
	fn.fractal_lacunarity = 2.1
	fn.fractal_gain = 0.52
	fn.seed = 20261030
	nt.noise = fn
	nt.width = 1024
	nt.height = 1024
	nt.seamless = true
	nt.generate_mipmaps = true
	return nt


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(330, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.10, 0.82)
	sb.border_color = Color(0.55, 0.85, 1.0, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "蓝白星动态背景 · 实时调参"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "（14 秒无缝循环 · 全部实时 GPU 计算）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(hint)
	vb.add_child(HSeparator.new())

	_slider(vb, "大气环亮度", 0.0, 1.6, 0.62, func(v): _atmo_mat.set_shader_parameter("brightness", v))
	_slider(vb, "大气环脉动", 0.0, 0.8, 0.26, func(v): _atmo_mat.set_shader_parameter("pulse_amount", v))
	_slider(vb, "光带厚度", 0.010, 0.120, 0.030, func(v): _atmo_mat.set_shader_parameter("band_width", v))
	_slider(vb, "内部光晕", 0.0, 0.25, 0.075, func(v): _atmo_mat.set_shader_parameter("inner_glow", v))

	vb.add_child(HSeparator.new())

	_slider(vb, "星云密度", 0.15, 0.85, 0.48, func(v): _nebula_mat.set_shader_parameter("density", v))
	_slider(vb, "星云圈数/14s", 1.0, 5.0, 2.0, func(v): _nebula_mat.set_shader_parameter("loop_turns", maxf(1.0, roundf(v))))
	_slider(vb, "星点密度", 0.02, 0.50, 0.20, func(v):
		for m in _star_mats:
			m.set_shader_parameter("density", v))

	vb.add_child(HSeparator.new())

	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	vb.add_child(_fps_label)

	var note := Label.new()
	note.text = "L1底图 + L2星云 + L3星点×2(视差) + L4大气环\n全部 14 秒无缝循环，无序列帧"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	vb.add_child(note)


func _slider(parent: Node, label_text: String, mn: float, mx: float, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var lb := Label.new()
	lb.text = label_text
	lb.custom_minimum_size = Vector2(92, 0)
	lb.add_theme_font_size_override("font_size", 12)
	row.add_child(lb)

	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = (mx - mn) / 100.0
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(140, 18)
	row.add_child(s)

	var vl := Label.new()
	vl.text = "%.3f" % val
	vl.custom_minimum_size = Vector2(44, 0)
	vl.add_theme_font_size_override("font_size", 11)
	row.add_child(vl)

	s.value_changed.connect(func(v: float) -> void:
		vl.text = "%.3f" % v
		cb.call(v))
	parent.add_child(row)


func _process(_delta: float) -> void:
	if _fps_label:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
