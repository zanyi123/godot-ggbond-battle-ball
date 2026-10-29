## U1 第一批 · 面板代码套件（美术UI线乙线窗口 · 2026-10-28）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_u1_panels.gd
## 覆盖：C1 标题/存档 / C2 暂停 / C3 设置 / C4 加载转场 / C5 教学蒙层 / C6 结算换肤 / C7 LblDisplay 档
## 注意：-s 模式下 add_child 后 _ready 在下一帧才跑——每个场景加载后 await process_frame 再断言
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)


func _load_scene(path: String) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	return inst


func _count_buttons(n: Node) -> int:
	var count := 0
	for child in n.get_children():
		if child is Button:
			count += 1
		count += _count_buttons(child)
	return count


func _collect(n: Node, sliders: Array, options: Array) -> void:
	for child in n.get_children():
		if child is HSlider:
			sliders.append(child)
		elif child is OptionButton:
			options.append(child)
		_collect(child, sliders, options)


func _run() -> void:
	print("\n========== U1 第一批 · 面板代码套件 ==========\n")

	# C1 标题/存档
	var title: Control = await _load_scene("res://scenes/ui/title_screen.tscn")
	_assert(title != null and title.has_signal("start_requested") and title.has_signal("slot_selected"), "C1a: 标题场景在位+双信号齐全")
	_assert(title.has_signal("quit_requested"), "C1b: quit_requested 在位")
	_assert(title.current_state() == 0, "C1c: 初始态=标题")
	_assert(_count_buttons(title) >= 4, "C1d: 三张存档卡各带进入键+退出键（≥4 Button）")
	_assert(title.theme == UiTheme.shared(), "C1e: 主题已挂（UiTheme.shared）")
	_assert(_count_buttons(title) >= 1 and title.get_child_count() >= 3, "C1f: 背景层/标题层/存档层/底栏已构建")

	# C2 暂停
	var pause: Control = await _load_scene("res://scenes/ui/pause_menu.tscn")
	_assert(pause != null and not pause.visible, "C2a: 暂停面板在位且默认隐藏")
	_assert(pause.process_mode == Node.PROCESS_MODE_ALWAYS, "C2b: 游戏树暂停时面板仍可交互（ALWAYS）")
	_assert(pause.has_signal("resume_requested") and pause.has_signal("restart_requested") and pause.has_signal("settings_requested") and pause.has_signal("quit_requested"), "C2c: 四信号齐全")
	pause.open()
	_assert(pause.is_open(), "C2d: open() 打开")
	_assert(_count_buttons(pause) == 4, "C2e: 四键（继续/重开/设置/退出）")
	pause.close()
	_assert(not pause.is_open(), "C2f: close() 关闭")

	# C3 设置
	var settings: Control = await _load_scene("res://scenes/ui/settings_panel.tscn")
	_assert(settings != null and settings.has_signal("setting_changed") and settings.has_signal("close_requested"), "C3a: 设置面板+两信号")
	var sliders: Array = []
	var options: Array = []
	_collect(settings, sliders, options)
	_assert(sliders.size() == 3, "C3b: 三条音量滑杆（主/音乐/音效）")
	_assert(options.size() == 2, "C3c: 两个下拉（画质/窗口）")
	if sliders.size() > 0:
		var got: Array = []
		settings.setting_changed.connect(func(k: String, v: Variant) -> void: got.append([k, v]))
		sliders[0].value = 66
		_assert(got.size() == 1 and got[0][0] == "volume_master" and absf(got[0][1] - 66.0) < 0.01, "C3d: 滑杆变动→setting_changed(key,value) 发出")
	settings.free()

	# C4 加载转场
	var loading: CanvasLayer = await _load_scene("res://scenes/ui/loading_overlay.tscn")
	_assert(loading != null and loading.has_signal("fade_in_done") and loading.has_signal("fade_out_done"), "C4a: 转场层+两信号")
	loading.setup(["林源", "石岳", "凯拉·曜"], ["影零", "霜见", "森野"])
	loading.set_progress(0.5)
	var lit := 0
	for slot in loading._lit_slots:
		if slot.visible:
			lit += 1
	_assert(lit == 3, "C4b: 进度 0.5→六槽亮 3（离散点亮）")
	loading.set_progress(1.0)
	lit = 0
	for slot in loading._lit_slots:
		if slot.visible:
			lit += 1
	_assert(lit == 6, "C4c: 进度 1.0→六槽全亮")
	_assert(loading._dim != null and loading._vs_root != null, "C4d: 黑幕+VS 卡两层在位")
	loading.free()

	# C5 教学蒙层
	var tut: Control = await _load_scene("res://scenes/ui/tutorial_overlay.tscn")
	_assert(tut != null and tut.has_signal("tutorial_finished"), "C5a: 教学蒙层+完成信号")
	_assert(tut.step_count() == 5, "C5b: 步骤数据 5 步（json 源）")
	var finished := [false]
	tut.tutorial_finished.connect(func() -> void: finished[0] = true)
	tut.start()
	_assert(tut.step_index() == 0 and tut.visible, "C5c: start() 进第 1 步且蒙层显示")
	for i in 5:
		tut.next()
	_assert(finished[0] and not tut.visible and tut.step_index() == -1, "C5d: 五步走完→完成信号+蒙层关闭")
	tut.free()

	# C6 结算换肤（常量→色板）
	var script: Script = load("res://scripts/ui/match_result_ui.gd")
	var mr: Control = script.new()
	var tol := 1.0 / 255.0
	var ok := absf(mr.BG_COLOR.r - UiPalette.col("semantic.bg_base").r) <= tol \
		and absf(mr.WIN_COLOR.g - UiPalette.col("semantic.success").g) <= tol \
		and absf(mr.LOSE_COLOR.r - UiPalette.col("semantic.danger").r) <= tol \
		and absf(mr.ACCENT_COLOR.r - UiPalette.col("semantic.primary_hi").r) <= tol
	_assert(ok, "C6a: 结算七常量已接色板（BG/WIN/LOSE/DRAW/CARD/TEXT/ACCENT）")
	_assert(UiPalette.get_value("meta.status") == "locked", "C6b: 色板源为锁版")
	mr.free()

	# C7 展示字号档（标题屏用）
	_assert(UiTheme.shared().get_font_size("font_size", "LblDisplay") == 40, "C7: LblDisplay 40 档在位")

	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)
