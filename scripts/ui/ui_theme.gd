class_name UiTheme
extends RefCounted

## U0-3 · Theme 框件包构建器（风格：科技赛事流，主人批复 1027-1 · 2026-10-28）
## 数据源：色=UiPalette（1027-2 候选A 已锁）；字体=文件在场自动启用（Noto/Rajdhani），缺场回退系统字体栈
## 纪律：本类零游戏逻辑、零硬编码色值（一切取 UiPalette）；面板侧一律 `control.theme = UiTheme.shared()`
## 变体：BtnPrimary/BtnGhost/BtnDanger（Button）· LblTitle/LblSection/LblCaption/LblNum（Label）

const FONT_NOTO_PATH := "res://assets/ui/fonts/NotoSansSC-VF.ttf"
const FONT_NUM_PATH := "res://assets/ui/fonts/Rajdhani-Bold.ttf"

static var _shared: Theme = null


## 全局共享主题（构建一次；换色/换字体后调 reset() 重建）
static func shared() -> Theme:
	if _shared == null:
		_shared = _build()
	return _shared


## 热重建（JSON/字体变更后调用，免重启）
static func reset() -> void:
	_shared = null


# ---------- 字体（文件在场自动切换，零代码换源） ----------

static func font_main() -> Font:
	if FileAccess.file_exists(FONT_NOTO_PATH):
		var f: Font = load(FONT_NOTO_PATH)
		if f != null:
			return f
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "sans-serif"])
	return sys


static func font_num() -> Font:
	if FileAccess.file_exists(FONT_NUM_PATH):
		var f: Font = load(FONT_NUM_PATH)
		if f != null:
			return f
	return font_main()


# ---------- 框件（斜切语言的 v1 近似：小切角半径+左缘刻度，真斜切件归丙线贴图批） ----------

static func _sb(bg: Color, border: Color, border_left := 0, radius := 3, margin := Vector2(14, 9)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	if border_left > 0:
		sb.border_width_left = border_left
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin.x
	sb.content_margin_right = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_bottom = margin.y
	return sb


# ---------- 构建主题 ----------

static func _build() -> Theme:
	var t := Theme.new()
	var c_text: Color = UiPalette.col("semantic.text")
	var c_dim: Color = UiPalette.col("semantic.text_dim")
	var c_line: Color = UiPalette.col("semantic.line")
	var c_line_hi: Color = UiPalette.col("semantic.line_hi")
	var c_panel: Color = UiPalette.col("semantic.bg_panel")
	var c_panel_hi: Color = UiPalette.col("semantic.bg_panel_hi")
	var c_base: Color = UiPalette.col("semantic.bg_base")
	var c_primary: Color = UiPalette.col("semantic.primary")
	var c_on_primary: Color = UiPalette.col("semantic.on_primary")
	var c_danger: Color = UiPalette.col("semantic.danger")
	var c_disabled: Color = UiPalette.col("semantic.disabled")

	t.default_font = font_main()
	t.default_font_size = 13

	# 面板
	t.set_stylebox("panel", "Panel", _sb(c_panel, c_line, 0, 3, Vector2(16, 14)))
	var pnl_hi := _sb(c_panel_hi, c_line_hi, 0, 3, Vector2(16, 14))
	t.set_stylebox("panel", "PanelHighlighted", pnl_hi)
	t.set_type_variation("PanelHighlighted", "Panel")

	# 按钮三态（悬停=左缘刻度+边框点亮；按下=沉底+主色描边）
	var btn_normal := _sb(c_panel, c_line, 2, 3)
	var btn_hover := _sb(c_panel_hi, c_line_hi, 2, 3)
	var btn_pressed := _sb(c_base, c_primary, 2, 3)
	var btn_disabled := _sb(c_panel, c_line, 0, 3)
	var btn_focus := StyleBoxFlat.new()
	btn_focus.draw_center = false
	btn_focus.border_color = c_line_hi
	btn_focus.set_border_width_all(1)
	btn_focus.set_corner_radius_all(3)
	t.set_stylebox("normal", "Button", btn_normal)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", btn_focus)
	t.set_color("font_color", "Button", c_text)
	t.set_color("font_hover_color", "Button", c_text)
	t.set_color("font_pressed_color", "Button", c_primary)
	t.set_color("font_disabled_color", "Button", c_disabled)
	t.set_color("font_focus_color", "Button", c_text)
	t.set_font_size("font_size", "Button", 14)

	# 变体：主按钮（金色实底）
	t.set_type_variation("BtnPrimary", "Button")
	t.set_stylebox("normal", "BtnPrimary", _sb(c_primary, c_primary, 0, 3))
	t.set_stylebox("hover", "BtnPrimary", _sb(c_primary.lightened(0.08), c_primary, 0, 3))
	t.set_stylebox("pressed", "BtnPrimary", _sb(c_primary.darkened(0.12), c_primary, 0, 3))
	t.set_stylebox("disabled", "BtnPrimary", _sb(c_disabled, c_disabled, 0, 3))
	t.set_stylebox("focus", "BtnPrimary", btn_focus)
	t.set_color("font_color", "BtnPrimary", c_on_primary)
	t.set_color("font_hover_color", "BtnPrimary", c_on_primary)
	t.set_color("font_pressed_color", "BtnPrimary", c_on_primary)
	t.set_color("font_disabled_color", "BtnPrimary", c_on_primary)

	# 变体：幽灵按钮（透明底，低强调）
	t.set_type_variation("BtnGhost", "Button")
	t.set_stylebox("normal", "BtnGhost", _sb(Color(c_panel.r, c_panel.g, c_panel.b, 0.55), c_line, 0, 3))
	t.set_stylebox("hover", "BtnGhost", _sb(c_panel_hi, c_line_hi, 0, 3))
	t.set_stylebox("pressed", "BtnGhost", btn_pressed)
	t.set_stylebox("disabled", "BtnGhost", btn_disabled)
	t.set_stylebox("focus", "BtnGhost", btn_focus)

	# 变体：危险按钮（红系文字描边）
	t.set_type_variation("BtnDanger", "Button")
	t.set_stylebox("normal", "BtnDanger", _sb(Color(c_panel.r, c_panel.g, c_panel.b, 0.55), Color(c_danger.r, c_danger.g, c_danger.b, 0.45), 0, 3))
	t.set_stylebox("hover", "BtnDanger", _sb(c_panel_hi, c_danger, 0, 3))
	t.set_stylebox("pressed", "BtnDanger", btn_pressed)
	t.set_stylebox("disabled", "BtnDanger", btn_disabled)
	t.set_stylebox("focus", "BtnDanger", btn_focus)
	t.set_color("font_color", "BtnDanger", c_danger)

	# 进度条（耐久/资源条通用）
	var pb_bg := _sb(c_panel_hi, c_line, 0, 2, Vector2(0, 0))
	var pb_fill := _sb(c_primary, c_primary, 0, 2, Vector2(0, 0))
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	# Label 字号档（U0-6 §三：T1 页题/T2 节题/T4 辅助/N1 数值 + D0 展示档）
	t.set_type_variation("LblDisplay", "Label")
	t.set_font_size("font_size", "LblDisplay", 40)
	t.set_color("font_color", "LblDisplay", c_text)
	t.set_type_variation("LblTitle", "Label")
	t.set_font_size("font_size", "LblTitle", 22)
	t.set_color("font_color", "LblTitle", c_text)
	t.set_type_variation("LblSection", "Label")
	t.set_font_size("font_size", "LblSection", 13)
	t.set_color("font_color", "LblSection", c_text)
	t.set_type_variation("LblCaption", "Label")
	t.set_font_size("font_size", "LblCaption", 11)
	t.set_color("font_color", "LblCaption", c_dim)
	t.set_type_variation("LblNum", "Label")
	t.set_font("font", "LblNum", font_num())
	t.set_font_size("font_size", "LblNum", 16)
	t.set_color("font_color", "LblNum", c_text)

	return t
