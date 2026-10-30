extends Control

## 协会大厅动态背景 · 蓝白星版（正式用于玩家主菜单）
##
## 2026-10-30 开源资源检索窗口
## 主人令：蓝白星挂【协会大厅】；光疤挂【联机大厅 + 匹配界面】
##         「不要一图多用」
##
## 与预览台（bg_preview_planet_v2.gd）的区别：
##   预览台 = 带滑条的开发工具
##   本类   = **无 UI、参数固定、可直接挂进任何场景**的正式组件
##
## 四层：
##   L1 底图      bg_planet_bluewhite_base.png
##   L2 星云      bg_planet_nebula（蓝白专属色板 #1f2744/#4c5379/#abd9f4）
##   L3 云层流动  bg_planet_cloud（遮罩内明暗流动）
##   L4 晨昏线    bg_planet_terminator（自转感）
##   L5 大气环    bg_atmo_glow（沿地平线补强）
##
## 全部 14 秒无缝循环。
## 用法：new() 后 add_child，或直接实例化 scenes/ui/bg_lobby_planet.tscn

const SH_NEBULA := "res://scripts/ui/shaders/bg_planet_nebula.gdshader"
const SH_CLOUD := "res://scripts/ui/shaders/bg_planet_cloud.gdshader"
const SH_TERM := "res://scripts/ui/shaders/bg_planet_terminator.gdshader"
const SH_ATMO := "res://scripts/ui/shaders/bg_atmo_glow.gdshader"
const TEX_BG := "res://assets/ui/backgrounds/bg_planet_bluewhite_base.png"
const TEX_CLOUD_MASK := "res://assets/ui/backgrounds/bg_planet_bluewhite_cloud_mask.png"

var _neb_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _term_mat: ShaderMaterial
var _atmo_mat: ShaderMaterial


func _ready() -> void:
	name = "BgLobbyPlanet"
	# ★ 2026-10-30 定版做法（Godot 警告给的正解）：
	#   "Nodes with non-equal opposite anchors will have their size overridden after _ready().
	#    If you want to set size, change the anchors or consider using set_deferred()."
	#   → 本节点在 .tscn 里已写 anchor_right/bottom=1.0（PRESET_FULL_RECT 等效），
	#     尺寸由引擎按父节点自动铺满，**不要手设 size**。
	#   子层（L1~L5）同理：设 anchors 后只在必要时 set_deferred("size", ...)。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var vs: Vector2 = get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		vs = Vector2(1440, 900)

	# ── L1 底图
	if ResourceLoader.exists(TEX_BG):
		var bg := TextureRect.new()
		bg.texture = load(TEX_BG)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var bgc := ColorRect.new()
		bgc.color = Color(0.03, 0.05, 0.10)
		bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bgc)

	# ── L2 星云（按实测：x[0.12~0.97] y[0~0.50]）
	var neb := ColorRect.new()
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
	add_child(neb)

	# ── L3 云层流动
	var cloud := ColorRect.new()
	cloud.set_anchors_preset(Control.PRESET_FULL_RECT)
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load(SH_CLOUD)
	_cloud_mat.set_shader_parameter("noise_tex", _make_noise(20261032, 0.0060))
	if ResourceLoader.exists(TEX_CLOUD_MASK):
		_cloud_mat.set_shader_parameter("cloud_mask", load(TEX_CLOUD_MASK))
	_cloud_mat.set_shader_parameter("flow_turns", 3.0)
	_cloud_mat.set_shader_parameter("flow_dir_x", 0.55)
	_cloud_mat.set_shader_parameter("flow_dir_y", -0.20)
	_cloud_mat.set_shader_parameter("warp_amount", 0.018)
	_cloud_mat.set_shader_parameter("light_delta", 0.22)
	_cloud_mat.set_shader_parameter("speed_scale", 1.0)
	cloud.material = _cloud_mat
	add_child(cloud)

	# ── L4 晨昏线
	var term := ColorRect.new()
	term.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	add_child(term)

	# ── L5 大气环（补强）
	var atmo := ColorRect.new()
	atmo.set_anchors_preset(Control.PRESET_FULL_RECT)
	atmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = load(SH_ATMO)
	_atmo_mat.set_shader_parameter("band_width", 0.030)
	_atmo_mat.set_shader_parameter("inner_glow", 0.075)
	_atmo_mat.set_shader_parameter("pulse_amount", 0.26)
	_atmo_mat.set_shader_parameter("pulse_turns", 2.0)
	_atmo_mat.set_shader_parameter("brightness", 0.62)
	atmo.material = _atmo_mat
	add_child(atmo)

	# 面向玩家的背景不挡交互
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 左侧压暗带（2026-10-30）
## U0-6 §六 要求「信息文字永置高对比」，但 LblCaption 用 text_dim 在亮星云上会糊。
## 解法不是改文字色（那是 Theme 的事），而是**在菜单区给背景压暗**。
##
## ★ 2026-10-30 踩坑：首版用两个 ColorRect 各设 anchor_right 做硬边+过渡带，
##   结果出现「三道硬边竖条」（anchor 与父尺寸不同步）。正解=**单个** ColorRect +
##   像素级宽度 + 内置渐变 shader（无第二层、无硬边）。
func add_left_scrim(width_ratio: float = 0.42, alpha: float = 0.58) -> void:
	var vs: Vector2 = size
	if vs.x < 1.0:
		vs = Vector2(1440, 900)
	var c: Color = UiPalette.col("semantic.bg_base")
	var band := ColorRect.new()
	band.name = "LeftScrim"
	band.position = Vector2.ZERO
	band.size = Vector2(vs.x * (width_ratio + 0.18), vs.y)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = Color(c.r, c.g, c.b, 1.0)
	# 渐变遮罩 shader：左侧实、右侧渐隐到 0，无硬边
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/ui/shaders/ui_left_scrim.gdshader")
	mat.set_shader_parameter("solid_ratio", width_ratio / (width_ratio + 0.18))
	mat.set_shader_parameter("max_alpha", alpha)
	mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, 1.0))
	band.material = mat
	add_child(band)


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
