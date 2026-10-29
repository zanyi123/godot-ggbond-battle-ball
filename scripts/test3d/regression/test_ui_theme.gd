## U0-3 · Theme 框件包套件（美术UI线乙线窗口 · 2026-10-28）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_ui_theme.gd
## 覆盖：C1 默认字体/字号 / C2 面板框 / C3 按钮三态+聚焦 / C4 三变体（主/幽灵/危险） /
##       C5 进度条 / C6 字号档变体 / C7 字体自动切换（Noto 在场）/ C8 取色全部源自色板 / C9 reset 幂等
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)


func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)


func _run() -> void:
	print("\n========== U0-3 · Theme 框件包套件（UiTheme） ==========\n")

	# C1 默认字体与字号
	var t: Theme = UiTheme.shared()
	_assert(t != null, "C1a: shared() 构建成功")
	_assert(t.default_font != null, "C1b: 默认字体非空")
	_assert(t.default_font_size == 13, "C1c: 默认字号 13（T3 正文档）")
	_assert(not (t.default_font is SystemFont), "C1d: 字体自动切换——Noto 在场应启用文件字体而非系统回退")

	# C2 面板框（色取自色板）
	var panel_sb: StyleBoxFlat = t.get_stylebox("panel", "Panel")
	_assert(panel_sb != null and panel_sb.bg_color == UiPalette.col("semantic.bg_panel"), "C2a: Panel 底色==色板 bg_panel")
	_assert(panel_sb.border_color == UiPalette.col("semantic.line"), "C2b: Panel 描边==色板 line")
	_assert(t.has_stylebox("panel", "PanelHighlighted") and t.get_type_variation_base("PanelHighlighted") == "Panel", "C2c: PanelHighlighted 变体注册")

	# C3 按钮三态+聚焦
	var bn: StyleBoxFlat = t.get_stylebox("normal", "Button")
	var bh: StyleBoxFlat = t.get_stylebox("hover", "Button")
	var bp: StyleBoxFlat = t.get_stylebox("pressed", "Button")
	_assert(bn != null and bh != null and bp != null, "C3a: 按钮三态框齐全")
	_assert(bn.bg_color != bh.bg_color and bp.bg_color != bh.bg_color, "C3b: 三态底色互异（可感知反馈）")
	_assert(bh.border_color == UiPalette.col("semantic.line_hi") and bh.border_width_left >= 2, "C3c: 悬停=边框点亮+左缘刻度（结构反馈纪律）")
	_assert(bp.border_color == UiPalette.col("semantic.primary"), "C3d: 按下=主色描边")
	_assert(t.has_stylebox("disabled", "Button") and t.has_stylebox("focus", "Button"), "C3e: disabled/focus 在位")
	_assert(t.get_color("font_disabled_color", "Button") == UiPalette.col("semantic.disabled"), "C3f: 禁用字色==色板 disabled")

	# C4 变体
	_assert(t.get_type_variation_base("BtnPrimary") == "Button", "C4a: BtnPrimary 注册为 Button 变体")
	var bpri: StyleBoxFlat = t.get_stylebox("normal", "BtnPrimary")
	_assert(bpri.bg_color == UiPalette.col("semantic.primary"), "C4b: 主按钮底==色板 primary（单金色纪律）")
	_assert(t.get_color("font_color", "BtnPrimary") == UiPalette.col("semantic.on_primary"), "C4c: 主按钮字==on_primary")
	_assert(t.get_type_variation_base("BtnGhost") == "Button", "C4d: BtnGhost 注册")
	var bghost: StyleBoxFlat = t.get_stylebox("normal", "BtnGhost")
	_assert(bghost.bg_color.a < 0.9, "C4e: 幽灵按钮半透明底（低强调）")
	_assert(t.get_type_variation_base("BtnDanger") == "Button", "C4f: BtnDanger 注册")
	_assert(t.get_color("font_color", "BtnDanger") == UiPalette.col("semantic.danger"), "C4g: 危险按钮字==danger")

	# C5 进度条
	var pb_fill: StyleBoxFlat = t.get_stylebox("fill", "ProgressBar")
	_assert(t.has_stylebox("background", "ProgressBar") and pb_fill != null, "C5a: 进度条 background/fill 在位")
	_assert(pb_fill.bg_color == UiPalette.col("semantic.primary"), "C5b: 进度填充==primary")

	# C6 字号档变体（U0-6 §三）
	_assert(t.get_type_variation_base("LblTitle") == "Label" and t.get_font_size("font_size", "LblTitle") == 22, "C6a: LblTitle 22（T1 页题）")
	_assert(t.get_font_size("font_size", "LblSection") == 13, "C6b: LblSection 13（T2 节题）")
	_assert(t.get_font_size("font_size", "LblCaption") == 11, "C6c: LblCaption 11（T4 辅助）")
	_assert(t.get_type_variation_base("LblNum") == "Label" and t.get_font_size("font_size", "LblNum") == 16, "C6d: LblNum 16（N1 数值档）")
	_assert(t.has_font("font", "LblNum"), "C6e: LblNum 挂数字展示字体")

	# C7 字体文件在场（资源完整）
	_assert(FileAccess.file_exists("res://assets/ui/fonts/NotoSansSC-VF.ttf"), "C7a: Noto 可变字体文件在场")
	_assert(FileAccess.file_exists("res://assets/ui/fonts/Rajdhani-Bold.ttf"), "C7b: Rajdhani 数字字体在场")
	_assert(FileAccess.file_exists("res://assets/ui/fonts/OFL.txt"), "C7c: OFL 许可文本在场（分发义务）")

	# C8 取色源自色板抽查（防手滑硬编码）
	_assert(t.get_color("font_color", "Button") == UiPalette.col("semantic.text"), "C8a: 按钮字色==色板 text")
	_assert((t.get_stylebox("normal", "BtnGhost") as StyleBoxFlat).border_color == UiPalette.col("semantic.line"), "C8b: 幽灵按钮描边==色板 line")

	# C9 reset 幂等
	UiTheme.reset()
	var t2: Theme = UiTheme.shared()
	_assert(t2 != null and t2.default_font_size == 13, "C9: reset 后重建一致（幂等）")
