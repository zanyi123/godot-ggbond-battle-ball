extends Control

## 蓝白星动态背景 v2（2026-10-30 重做）
##
## ★ 主人批评 v1：「还是搬的前面的星云，连颜色都不变，没有针对图片特征，
##   星云速度/大气层表面动态云/星球轮廓光暗边缘没设计，大气层就是图片那道亮光没有用」
##
## v2 的五层（每层都针对图片特征）：
##   L1 底图        即梦原图（静）
##   L2 星云        bg_planet_nebula —— **蓝白专属色板**（实测取色：#1f2744/#4c5379/#abd9f4）+ 左上→右下流向
##   L3 云层流动    bg_planet_cloud —— **只在云层遮罩内**做明暗流动（让云真的飘）
##   L4 晨昏线      bg_planet_terminator —— 行星明暗分界**极缓左右移动**（自转感）
##   L5 大气环      bg_atmo_glow —— 保留，补强原图那道冰蓝光（不再"重复画"）
##
## 全部 14 秒无缝循环。

const SH_NEBULA := "res://scripts/ui/shaders/bg_planet_nebula.gdshader"
const SH_CLOUD := "res://scripts/ui/shaders/bg_planet_cloud.gdshader"
const SH_TERM := "res://scripts/ui/shaders/bg_planet_terminator.gdshader"
const SH_ATMO := "res://scripts/ui/shaders/bg_atmo_glow.gdshader"
const BG_PATH := "res://assets/ui/backgrounds/bg_planet_bluewhite_base.png"
const CLOUD_MASK := "res://assets/ui/backgrounds/bg_planet_bluewhite_cloud_mask.png"

var _root: Control
var _neb_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _term_mat: ShaderMaterial
var _atmo_mat: ShaderMaterial
var _fps: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_build_ui()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

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
	_root.add_child(bg)

	# ── L2 星云（蓝白专属色板；按实测分布放置）
	var neb := ColorRect.new()
	# ★ 实测星云集中在 x[0.12~0.97] y[0~0.50]（6x4 分块覆盖 50~80%），
	#   原实现铺成左上 x<0.72 = **铺反了**，且盖住了深空星点。
	neb.position = Vector2(vs.x * 0.10, 0.0)
	neb.size = Vector2(vs.x * 0.90, vs.y * 0.52)
	neb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_neb_mat = ShaderMaterial.new()
	_neb_mat.shader = load(SH_NEBULA)
	_neb_mat.set_shader_parameter("noise_tex", _make_noise(20261031, 0.0028))
	_neb_mat.set_shader_parameter("density", 0.42)
	_neb_mat.set_shader_parameter("contrast", 1.35)
	_neb_mat.set_shader_parameter("loop_turns", 1.0)
	_neb_mat.set_shader_parameter("dist_warp", 0.026)
	_neb_mat.set_shader_parameter("alpha", 0.62)
	_neb_mat.set_shader_parameter("gold_mix", 0.16)
	neb.material = _neb_mat
	_root.add_child(neb)

	# ── L3 云层流动（全屏，但受 cloud_mask 限制只在云上生效）
	var cloud := ColorRect.new()
	cloud.position = Vector2.ZERO
	cloud.size = vs
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load(SH_CLOUD)
	_cloud_mat.set_shader_parameter("noise_tex", _make_noise(20261032, 0.0060))
	if ResourceLoader.exists(CLOUD_MASK):
		_cloud_mat.set_shader_parameter("cloud_mask", load(CLOUD_MASK))
	_cloud_mat.set_shader_parameter("flow_turns", 3.0)
	_cloud_mat.set_shader_parameter("flow_dir_x", 0.55)
	_cloud_mat.set_shader_parameter("flow_dir_y", -0.20)
	_cloud_mat.set_shader_parameter("warp_amount", 0.018)
	_cloud_mat.set_shader_parameter("light_delta", 0.22)
	_cloud_mat.set_shader_parameter("speed_scale", 1.0)
	cloud.material = _cloud_mat
	_root.add_child(cloud)

	# ── L4 晨昏线（行星明暗分界极缓移动）
	var term := ColorRect.new()
	term.position = Vector2.ZERO
	term.size = vs
	term.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term_mat = ShaderMaterial.new()
	_term_mat.shader = load(SH_TERM)
	_term_mat.set_shader_parameter("line_x", 0.82)
	_term_mat.set_shader_parameter("line_width", 0.26)
	_term_mat.set_shader_parameter("shift_amp", 0.045)
	_term_mat.set_shader_parameter("dark_amount", 0.30)
	_term_mat.set_shader_parameter("light_amount", 0.12)
	_term_mat.set_shader_parameter("planet_top", 0.30)
	term.material = _term_mat
	_root.add_child(term)

	# ── L5 大气环（补强原图那道冰蓝光，不另画）
	var atmo := ColorRect.new()
	atmo.position = Vector2.ZERO
	atmo.size = vs
	atmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = load(SH_ATMO)
	_atmo_mat.set_shader_parameter("band_width", 0.030)
	_atmo_mat.set_shader_parameter("inner_glow", 0.075)
	_atmo_mat.set_shader_parameter("pulse_amount", 0.26)
	_atmo_mat.set_shader_parameter("pulse_turns", 2.0)
	_atmo_mat.set_shader_parameter("brightness", 0.62)
	atmo.material = _atmo_mat
	_root.add_child(atmo)


func _make_noise(seed_val: int, freq: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 5
	fn.fractal_lacunarity = 2.1
	fn.fractal_gain = 0.52
	fn.seed = seed_val
	nt.noise = fn
	nt.width = 1024
	nt.height = 1024
	nt.seamless = true
	nt.generate_mipmaps = true
	return nt


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(336, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.10, 0.84)
	sb.border_color = Color(0.42, 0.52, 0.75, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "蓝白星 v2 · 特征化动态"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.42, 0.52, 0.75).lerp(Color.WHITE, 0.35))
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "（星云专属色板 / 云层流动 / 晨昏线 / 大气环）"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(hint)
	vb.add_child(HSeparator.new())

	var sec := Label.new(); sec.text = "— 星云（蓝白专属色板）"
	sec.add_theme_font_size_override("font_size", 11)
	sec.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	vb.add_child(sec)
	_s(vb, "星云浓度", 0.10, 0.85, 0.42, func(v): _neb_mat.set_shader_parameter("density", v))
	_s(vb, "星云圈数/14s", 1.0, 4.0, 1.0, func(v): _neb_mat.set_shader_parameter("loop_turns", maxf(1.0, roundf(v))))
	_s(vb, "金色点缀", 0.0, 0.5, 0.16, func(v): _neb_mat.set_shader_parameter("gold_mix", v))

	vb.add_child(HSeparator.new())
	var sec2 := Label.new(); sec2.text = "— 云层流动"
	sec2.add_theme_font_size_override("font_size", 11)
	sec2.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	vb.add_child(sec2)
	_s(vb, "云层强度", 0.0, 1.0, 0.22, func(v): _cloud_mat.set_shader_parameter("light_delta", v))
	_s(vb, "云层圈数/14s", 1.0, 8.0, 3.0, func(v): _cloud_mat.set_shader_parameter("flow_turns", maxf(1.0, roundf(v))))
	_s(vb, "云层速度", 0.0, 2.0, 1.0, func(v): _cloud_mat.set_shader_parameter("speed_scale", v))

	vb.add_child(HSeparator.new())
	var sec3 := Label.new(); sec3.text = "— 晨昏线（自转感）"
	sec3.add_theme_font_size_override("font_size", 11)
	sec3.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	vb.add_child(sec3)
	_s(vb, "暗面强度", 0.0, 0.8, 0.30, func(v): _term_mat.set_shader_parameter("dark_amount", v))
	_s(vb, "亮面提亮", 0.0, 0.5, 0.12, func(v): _term_mat.set_shader_parameter("light_amount", v))
	_s(vb, "移动幅度", 0.0, 0.20, 0.045, func(v): _term_mat.set_shader_parameter("shift_amp", v))

	vb.add_child(HSeparator.new())
	var sec4 := Label.new(); sec4.text = "— 大气环"
	sec4.add_theme_font_size_override("font_size", 11)
	sec4.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vb.add_child(sec4)
	_s(vb, "大气环亮度", 0.0, 1.6, 0.62, func(v): _atmo_mat.set_shader_parameter("brightness", v))
	_s(vb, "大气环脉动", 0.0, 0.8, 0.26, func(v): _atmo_mat.set_shader_parameter("pulse_amount", v))

	vb.add_child(HSeparator.new())
	_fps = Label.new()
	_fps.add_theme_font_size_override("font_size", 12)
	_fps.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	vb.add_child(_fps)


func _s(parent: Node, label_text: String, mn: float, mx: float, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var lb := Label.new()
	lb.text = label_text
	lb.custom_minimum_size = Vector2(98, 0)
	lb.add_theme_font_size_override("font_size", 11)
	row.add_child(lb)
	var sl := HSlider.new()
	sl.min_value = mn; sl.max_value = mx
	sl.step = (mx - mn) / 100.0
	sl.value = val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(136, 16)
	row.add_child(sl)
	var vl := Label.new()
	vl.text = "%.3f" % val
	vl.custom_minimum_size = Vector2(42, 0)
	vl.add_theme_font_size_override("font_size", 10)
	row.add_child(vl)
	sl.value_changed.connect(func(v: float) -> void:
		vl.text = "%.3f" % v
		cb.call(v))
	parent.add_child(row)


func _process(_d: float) -> void:
	if _fps:
		_fps.text = "FPS: %d" % Engine.get_frames_per_second()
