class_name UiMotion
extends RefCounted

## U0-5 · UI 动效小库（美术UI线乙线窗口 · 2026-10-28）
## 参数唯一来源：res://data/ui/ui_motion.json（时长/周期/幅度只改 json，本类零改动）
## 纪律：模板只动 transform/modulate/material，不碰游戏属性；UI 层零判定逻辑
## 配套：scripts/ui/shaders/ui_breathe.gdshader · ui_edge_sweep.gdshader

const CFG_PATH := "res://data/ui/ui_motion.json"
const SHADER_BREATHE := "res://scripts/ui/shaders/ui_breathe.gdshader"
const SHADER_EDGE_SWEEP := "res://scripts/ui/shaders/ui_edge_sweep.gdshader"

static var _cfg: Dictionary = {}
static var _loaded: bool = false


## 点路径取数（缺键回退 fallback，不炸）
static func num(dotted: String, fallback: float) -> float:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(CFG_PATH):
			var f := FileAccess.open(CFG_PATH, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					_cfg = parsed
	var cur: Variant = _cfg
	for part in dotted.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return fallback
	return float(cur) if not (cur is float and is_nan(cur)) else fallback


static func cfg_reload() -> void:
	_loaded = false
	_cfg = {}


## 悬停弹起（scale 1.0→1.04；先取中心为轴）
static func hover_pop(c: Control) -> Tween:
	if c == null:
		return null
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * num("tween.hover_pop.scale", 1.04), num("tween.hover_pop.dur", 0.12))
	return tw


## 按下沉（1.0→0.96）
static func press(c: Control) -> Tween:
	if c == null:
		return null
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * num("tween.press.scale", 0.96), num("tween.press.dur", 0.08))
	return tw


## 松开回弹（→1.0）
static func release(c: Control) -> Tween:
	if c == null:
		return null
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, num("tween.press.dur", 0.08))
	return tw


## 滑入+淡入（入场层次；from_offset 为相对终点的起始偏移；delay 用于入场错峰）
static func slide_in(c: Control, from_offset: Vector2, delay := 0.0) -> Tween:
	if c == null:
		return null
	var target := c.position
	c.position = target + from_offset
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", target, num("tween.slide_in.dur", 0.32)).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 1.0, num("tween.fade_in.dur", 0.25)).set_delay(delay)
	return tw


## 淡出（退出转场；不回收节点，由调用方决定）
static func fade_out(c: CanvasItem) -> Tween:
	if c == null:
		return null
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, num("tween.fade_out.dur", 0.2))
	return tw


## 呼吸脉冲（挂 ui_breathe 材质；同屏 ≤1 处）
static func breathe(c: CanvasItem) -> ShaderMaterial:
	if c == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_BREATHE)
	mat.set_shader_parameter("breathe_period", num("shader.breathe_period", 4.0))
	mat.set_shader_parameter("breathe_min", num("shader.breathe_min", 0.72))
	c.material = mat
	return mat


## 底缘流光扫描（挂 ui_edge_sweep 材质；color 传色板色，alpha 由 json 统一管）
static func edge_sweep(c: Control, color: Color) -> ShaderMaterial:
	if c == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_EDGE_SWEEP)
	mat.set_shader_parameter("sweep_period", num("shader.sweep_period", 3.2))
	mat.set_shader_parameter("sweep_width", num("shader.sweep_width", 0.18))
	mat.set_shader_parameter("sweep_color", Color(color.r, color.g, color.b, num("shader.sweep_alpha", 0.5)))
	c.material = mat
	return mat
