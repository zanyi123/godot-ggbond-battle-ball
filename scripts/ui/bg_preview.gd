extends Control

## 动态背景实时预览台（2026-10-30 开源资源检索窗口）
##
## 目的：把「崩铁式动态背景」的五层结构在 Godot 里实跑起来，供主人实时拖参看效果。
##       这是对「Python 离线逐帧渲染」的替代路线验证件（见 美术规划/07 档 §三）。
##
## 五层结构：
##   L1 底图      —— 即梦来图（静）
##   L2 星云      —— bg_nebula_flow.gdshader（域扭曲 + 三频慢滚）
##   L3 星点×3    —— bg_star_scroll.gdshader，三实例不同 scroll_speed（视差）
##   L4 粒子      —— GPUParticles2D + Kenney CC0 软圆贴图
##   L5 光晕呼吸  —— 独立 sin(TIME) 层，幅度极小
##
## 窗口内可直接拖动滑块调参，实时看效果。

const SHADER_NEBULA := "res://scripts/ui/shaders/bg_nebula_flow.gdshader"
const SHADER_STAR := "res://scripts/ui/shaders/bg_star_scroll.gdshader"
const TEX_STARS := "res://assets/ui/backgrounds/particles/star_05.png"
const TEX_SOFT := "res://assets/ui/backgrounds/particles/circle_05.png"
const TEX_GLOW := "res://assets/ui/backgrounds/particles/light_01.png"

var _layer_root: Control
var _nebula_mat: ShaderMaterial
var _star_mats: Array = []
var _dust: GPUParticles2D
var _glow_mat: ShaderMaterial
var _ui: Control
var _fps_label: Label
var _glow_rect_ref: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_ui()


# ── 背景五层 ──────────────────────────────────────────────
func _build_background() -> void:
	_layer_root = Control.new()
	_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)

	# L1 底图（若存在即梦来图则用，否则用深色底）
	var base_rect := ColorRect.new()
	base_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_rect.color = Color(0.035, 0.020, 0.070)
	base_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_root.add_child(base_rect)

	var bg_path := "res://assets/ui/backgrounds/bg_lobby_scar_night_base.png"
	if ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.modulate.a = 0.55   # 压暗，让动效层透出来
		_layer_root.add_child(bg)

	# L2 星云层
	var nebula := ColorRect.new()
	nebula.set_anchors_preset(Control.PRESET_FULL_RECT)
	nebula.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nebula_mat = ShaderMaterial.new()
	_nebula_mat.shader = load(SHADER_NEBULA)
	# ★ 14 秒无缝循环：默认走 2 圈
	_nebula_mat.set_shader_parameter("loop_turns", 2.0)
	_nebula_mat.shader = load(SHADER_NEBULA)
	_nebula_mat.set_shader_parameter("noise_tex", _make_noise())
	nebula.material = _nebula_mat
	_layer_root.add_child(nebula)

	# L3 星点三层（不同速度 = 视差）
	var layers := [
		# ⚠ 2026-10-30 修：原 scale 0.22~0.42 + cell 48~96 导致星点直径 20~40px，且铺满全屏（室内也下雪）
		# 改为：cell 加大（星星稀疏）、scale 大幅缩小（星星细）、alpha 降低；并用 upper 标记只铺窗外
		{"speed": 1.0,  "cell": 150.0, "scale": 0.030, "density": 0.28, "br": 0.55, "alpha": 0.60},
		{"speed": 2.6,  "cell": 120.0, "scale": 0.045, "density": 0.18, "br": 0.80, "alpha": 0.65},
		{"speed": 5.2,  "cell":  95.0, "scale": 0.070, "density": 0.10, "br": 1.10, "alpha": 0.75},
	]
	for cfg in layers:
		var layer := ColorRect.new()
		# 只铺「窗外天空区」：屏幕上半部（窗框地平线实测约在 52% 处）
		# —— 2026-10-30 修：原先 FULL_RECT 导致星星落到室内地板上，看着像下雪
		layer.anchor_left = 0.0
		layer.anchor_top = 0.0
		layer.anchor_right = 1.0
		layer.anchor_bottom = 0.52
		layer.offset_left = 0.0
		layer.offset_top = 0.0
		layer.offset_right = 0.0
		layer.offset_bottom = 0.0
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = load(SHADER_STAR)
		m.set_shader_parameter("scroll_speed", cfg["speed"])
		m.set_shader_parameter("cell_size", cfg["cell"])
		m.set_shader_parameter("star_scale", cfg["scale"])
		# 传入该层实际像素尺寸（shader 里不再写死 1440×900）
		m.set_shader_parameter("layer_size", Vector2(get_viewport_rect().size.x, get_viewport_rect().size.y * 0.52))
		m.set_shader_parameter("density", cfg["density"])
		m.set_shader_parameter("brightness", cfg["br"])
		layer.material = m
		layer.modulate.a = cfg["alpha"]
		_star_mats.append(m)
		# ★ 硬设尺寸（set_anchors_preset 在 add_child 前不生效 —— 2026-10-30 实测坑）
		var vs_now: Vector2 = get_viewport_rect().size
		layer.position = Vector2.ZERO
		layer.size = Vector2(vs_now.x, vs_now.y * 0.52)
		_layer_root.add_child(layer)

	# L4 光尘粒子
	# ⚠ 2026-10-30 首版踩坑：circle_05 是「大团柔边圆」，scale 0.06~0.28 在 1440 屏上
	#    等于直径 86~400px 的粉红棉团压在画面上，非常脏。修法三件套：
	#    ①换小尺寸星点贴图（star_05）②scale 降到 0.01~0.05 ③alpha 大幅降低
	_dust = GPUParticles2D.new()
	# ⚠ 2026-10-30 三次调参仍满屏「下雪」感：根因是 star_05 贴图本身带大光晕 + 屏幕值写死 position
	# 在 resized 前不可靠。本轮先关闭，改用 L3 星点层承担「星」的职责（主入口已够看）。
	# 粒子留待「按视口尺寸弹性发射」方案再开（见 07 档 §三 L4）。
	_dust.amount = 0
	_dust.lifetime = 16.0          # 极长生命 = 极慢运动
	_dust.preprocess = 9.0
	_dust.local_coords = false
	var dust_tex := TEX_STARS if ResourceLoader.exists(TEX_STARS) else TEX_SOFT
	_dust.texture = load(dust_tex)
	_dust.position = get_viewport_rect().size * 0.5
	var pm := ParticleProcessMaterial.new()
	# Godot 4.6 的 ParticleProcessMaterial 无 EMISSION_SHAPE_RECTANGLE，
	# 2D 矩形发射要用 BOX（z 置 0）—— 2026-10-30 实测踩坑
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 发射区限定「窗外天空」：中心上移到屏幕 26% 处，纵向范围只覆盖上半屏
	pm.emission_box_extents = Vector3(get_viewport_rect().size.x * 0.60, get_viewport_rect().size.y * 0.26, 0)
	_dust.position = Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.26)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, 0, 0)
	pm.scale_min = 0.0035          # 极细（0.06 → 0.010 → 0.0035，三次数值收敛）
	pm.scale_max = 0.013
	pm.color = Color(0.92, 0.88, 1.0, 0.18)
	var grad := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.30, Color(1, 0.95, 0.82, 0.34))
	g.add_point(0.70, Color(0.88, 0.76, 1.0, 0.24))
	g.set_color(1, Color(1, 1, 1, 0.0))
	grad.gradient = g
	pm.color_ramp = grad
	_dust.process_material = pm
	# 只让粒子出现在「窗外天空区」（y < 0.52 的屏幕高度），避免满屏下雪的感觉
	_dust.set_meta("sky_only", 0.52)
	_layer_root.add_child(_dust)

	# L5 光晕呼吸（极缓，幅度小）——挂在光疤位置（实测归一化 0.698, 0.330）
	var glow := TextureRect.new()
	glow.texture = load(TEX_GLOW) if ResourceLoader.exists(TEX_GLOW) else null
	glow.set_anchors_preset(Control.PRESET_TOP_LEFT)
	glow.size = Vector2(760, 760)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1.0, 0.72, 0.42, 0.10)
	glow.set_meta("rel_pos", Vector2(0.698, 0.330))
	_layer_root.add_child(glow)
	_glow_rect_ref = glow
	var tw := create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.22, 7.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 0.06, 7.0).set_trans(Tween.TRANS_SINE)


func _make_noise() -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.0032
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


# ── 调参面板 ─────────────────────────────────────────────
func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(330, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.10, 0.82)
	sb.border_color = Color(0.91, 0.71, 0.29, 0.65)
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
	title.text = "动态背景预览台 · 实时调参"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.91, 0.71, 0.29))
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "（拖动滑块实时看效果，改完告诉我更喜欢哪组）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(hint)
	vb.add_child(HSeparator.new())

	# 星云参数
	_slider(vb, "星云密度", 0.20, 0.90, 0.55, func(v): _nebula_mat.set_shader_parameter("density", v))
	_slider(vb, "星云对比", 0.8, 3.5, 1.6, func(v): _nebula_mat.set_shader_parameter("contrast", v))
	# ★ 14 秒循环：滑块映射到「14 秒内走几圈」的**整数**（1~5），保证闭环
	_slider(vb, "流动圈数/14s", 1.0, 5.0, 2.0, func(v): _nebula_mat.set_shader_parameter("loop_turns", maxf(1.0, roundf(v))))
	_slider(vb, "域扭曲", 0.0, 0.10, 0.035, func(v): _nebula_mat.set_shader_parameter("dist_warp", v))

	vb.add_child(HSeparator.new())

	# 星点参数
	_slider(vb, "星点密度", 0.02, 0.50, 0.20, func(v):
		for m in _star_mats:
			m.set_shader_parameter("density", v))
	_slider(vb, "视差强度", 0.0, 3.0, 1.0, func(v):
		for i in _star_mats.size():
			_star_mats[i].set_shader_parameter("scroll_speed", [1.0, 2.6, 5.2][i] * v))
	_slider(vb, "闪烁幅度", 0.0, 1.0, 0.45, func(v):
		for m in _star_mats:
			m.set_shader_parameter("twinkle_amount", v))

	vb.add_child(HSeparator.new())

	# 性能读数
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	vb.add_child(_fps_label)

	var note := Label.new()
	note.text = "L1底图 + L2星云 + L3星点×3(视差) + L4光尘 + L5光晕\n全部实时 GPU 计算，无序列帧"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	vb.add_child(note)


func _slider(parent: Node, label_text: String, mn: float, mx: float, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var lb := Label.new()
	lb.text = label_text
	lb.custom_minimum_size = Vector2(86, 0)
	lb.add_theme_font_size_override("font_size", 12)
	row.add_child(lb)

	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = (mx - mn) / 100.0
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(150, 18)
	row.add_child(s)

	var vl := Label.new()
	vl.text = "%.3f" % val
	vl.custom_minimum_size = Vector2(46, 0)
	vl.add_theme_font_size_override("font_size", 11)
	row.add_child(vl)

	s.value_changed.connect(func(v: float) -> void:
		vl.text = "%.3f" % v
		cb.call(v))
	parent.add_child(row)


func _process(_delta: float) -> void:
	if _fps_label:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# 光晕跟随窗口尺寸，锚在光疤归一化位置 (0.698, 0.330)
	if _glow_rect_ref and _glow_rect_ref.get_meta("rel_pos") is Vector2:
		var rp: Vector2 = _glow_rect_ref.get_meta("rel_pos")
		var vs := size
		_glow_rect_ref.position = Vector2(vs.x * rp.x, vs.y * rp.y) - _glow_rect_ref.size * 0.5
