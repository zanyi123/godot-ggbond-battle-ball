extends Control

## 联机大厅 / 匹配界面动态背景 · 光疤版
##
## 2026-10-30 开源资源检索窗口
## 主人令：光疤挂【联机大厅】+【匹配界面】；蓝白星挂【协会大厅】
##         「不要一图多用」
##
## 与预览台（bg_preview.gd）的区别：**无滑条、参数固定、可直接挂载**
##
## 五层：
##   L1 底图      bg_lobby_scar_night_base.png（协会大厅窗外光疤）
##   L2 星云      bg_nebula_flow（紫金色板，域扭曲三频慢滚）
##   L3 星点×3    bg_star_scroll（视差，只铺窗外上 52%）
##   L4 光核      bg_lobby_scar_night_core.png（呼吸）
##   L5 光晕      bg_lobby_scar_night_mask.png 驱动
##
## 全部 14 秒无缝循环。

const SH_NEBULA := "res://scripts/ui/shaders/bg_nebula_flow.gdshader"
const SH_STAR := "res://scripts/ui/shaders/bg_star_scroll.gdshader"
const TEX_BG := "res://assets/ui/backgrounds/bg_lobby_scar_night_base.png"
const TEX_CORE := "res://assets/ui/backgrounds/bg_lobby_scar_night_core.png"
const TEX_MASK := "res://assets/ui/backgrounds/bg_lobby_scar_night_mask.png"
const TEX_GLOW := "res://assets/ui/backgrounds/particles/light_01.png"

var _neb_mat: ShaderMaterial
var _star_mats: Array = []
var _core_rect: TextureRect


func _ready() -> void:
	name = "BgNetScar"
	# ★ 2026-10-30 定版做法（Godot 警告给的正解）：
	#   联机 UI 是运行时 new() 出来的，父节点此刻可能还是 0 尺寸，
	#   所以本节点用 anchors 铺满 + **set_deferred 设尺寸**（Godot 建议写法），
	#   既避开 "size overridden after _ready()" 警告，又能拿到真实尺寸。
	var vs: Vector2 = get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		vs = Vector2(1440, 900)   # headless 兜底
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", vs)
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
		bg.modulate.a = 0.92   # 联机场景需要压住底下的主菜单画面；动态由 L2~L5 层提供
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var bgc := ColorRect.new()
		bgc.color = Color(0.035, 0.02, 0.07)
		bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bgc)

	# ── L2 星云（紫金，光疤版专属）
	var neb := ColorRect.new()
	neb.set_anchors_preset(Control.PRESET_FULL_RECT)
	neb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_neb_mat = ShaderMaterial.new()
	_neb_mat.shader = load(SH_NEBULA)
	_neb_mat.set_shader_parameter("noise_tex", _make_noise(20261029, 0.0032))
	_neb_mat.set_shader_parameter("loop_turns", 2.0)
	_neb_mat.set_shader_parameter("density", 0.55)
	_neb_mat.set_shader_parameter("contrast", 1.6)
	_neb_mat.set_shader_parameter("dist_warp", 0.035)
	_neb_mat.set_shader_parameter("alpha", 0.82)
	neb.material = _neb_mat
	add_child(neb)

	# ── L3 星点×3（视差；只铺窗外上 52%）
	var star_area := Vector2(vs.x, vs.y * 0.52)
	var layers := [
		{"speed": 1.0, "cell": 150.0, "scale": 0.030, "density": 0.28, "br": 0.55, "alpha": 0.60},
		{"speed": 2.6, "cell": 120.0, "scale": 0.045, "density": 0.18, "br": 0.80, "alpha": 0.65},
		{"speed": 5.2, "cell": 95.0, "scale": 0.070, "density": 0.10, "br": 1.10, "alpha": 0.75},
	]
	for cfg in layers:
		var layer := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = load(SH_STAR)
		m.set_shader_parameter("scroll_speed", cfg["speed"])
		m.set_shader_parameter("cell_size", cfg["cell"])
		m.set_shader_parameter("star_scale", cfg["scale"])
		m.set_shader_parameter("density", cfg["density"])
		m.set_shader_parameter("brightness", cfg["br"])
		m.set_shader_parameter("layer_size", star_area)
		layer.material = m
		layer.modulate.a = cfg["alpha"]
		layer.position = Vector2.ZERO
		layer.size = star_area
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_star_mats.append(m)
		add_child(layer)

	# ── L4 光核（14 秒呼吸）
	if ResourceLoader.exists(TEX_CORE):
		_core_rect = TextureRect.new()
		_core_rect.texture = load(TEX_CORE)
		_core_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_core_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_core_rect.modulate = Color(1.0, 0.95, 0.85, 0.55)
		_core_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_core_rect)
		# 14 秒整周期呼吸（两段各 7 秒 = 14 秒闭环）
		var tw := create_tween().set_loops()
		tw.tween_property(_core_rect, "modulate:a", 0.78, 7.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_core_rect, "modulate:a", 0.45, 7.0).set_trans(Tween.TRANS_SINE)

	# ── L5 光晕
	if ResourceLoader.exists(TEX_GLOW):
		var glow := TextureRect.new()
		glow.texture = load(TEX_GLOW)
		glow.size = Vector2(760, 760)
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.position = Vector2(vs.x * 0.698, vs.y * 0.330) - glow.size * 0.5
		glow.modulate = Color(1.0, 0.72, 0.42, 0.10)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		var tw2 := create_tween().set_loops()
		tw2.tween_property(glow, "modulate:a", 0.22, 7.0).set_trans(Tween.TRANS_SINE)
		tw2.tween_property(glow, "modulate:a", 0.06, 7.0).set_trans(Tween.TRANS_SINE)


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
