## E-Editor 验收：打开天赋树编辑器 → 首次自动布局 → 新增/连接/保存 → 截图
extends Node3D
func _ready() -> void:
	var mm = load("res://scripts/ui/main_menu.gd").new()
	add_child(mm)
	await get_tree().create_timer(0.5).timeout
	# 找到天赋编辑器按钮并按下（模拟主人点管理员模式的入口）
	var btn = mm.get_node_or_null("BtnTalentEditor")
	if btn == null:
		# 按钮在 admin 菜单构建后才有——直接调 handler
		mm._on_open_talent_editor()
	await get_tree().create_timer(0.5).timeout
	var editor = mm.get_node_or_null("BtnTalentEditor")
	var editor_ctrl: Control = null
	for c in mm.get_children():
		if c.get_script() and str(c.get_script().resource_path).contains("dev_talent_tree_editor"):
			editor_ctrl = c
	if editor_ctrl == null:
		print("[Edt][FAIL] 编辑器未打开")
		get_tree().quit(1)
		return
	print("[Edt] 编辑器已打开，节点数=", editor_ctrl._nodes().size())
	await get_tree().create_timer(1.0).timeout
	# ===== 交互实测：合成输入事件 =====
	var card := editor_ctrl.canvas.get_node_or_null("Card_atk_1") as Button
	var pos0: Vector2 = card.position
	var world0: Vector2 = editor_ctrl._pos_to_vec(editor_ctrl._node_by_id("atk_1")["pos"])
	# 拖节点：左键按下→快速右拖（20步每步等1帧，逐步采样防瞬移检测）
	var start_mouse: Vector2 = card.get_global_position() + Vector2(30, 20)
	var last_card_pos: Vector2 = card.position
	var max_jump: float = 0.0
	var jump_trace: Array = []
	_send_mouse(editor_ctrl, start_mouse, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	for i in range(20):
		var target_mouse: Vector2 = start_mouse + Vector2(18, 6) * (i + 1)  # 快速右拖，总位移360
		_send_motion(editor_ctrl, target_mouse)
		await get_tree().process_frame
		var jump: float = card.position.distance_to(last_card_pos)
		if jump > 40.0:  # 每步应只移动18px（zoom1），>40=瞬移
			jump_trace.append("第%d步跳%.0fpx→%s" % [i + 1, jump, str(card.position)])
		max_jump = maxf(max_jump, jump)
		last_card_pos = card.position
	_send_mouse(editor_ctrl, start_mouse + Vector2(360, 120), MOUSE_BUTTON_LEFT, false)
	if jump_trace.size() > 0:
		for t in jump_trace:
			print("[Edt][TRACE] ", t)
	print("[Edt] 最大单步跳变=%.0fpx" % max_jump)
	await get_tree().create_timer(0.2).timeout
	var moved: bool = card.position.distance_to(pos0) > 100.0
	var world_moved: bool = editor_ctrl._pos_to_vec(editor_ctrl._node_by_id("atk_1")["pos"]).distance_to(world0) > 100.0
	# 防回跳：松手后 1.5 秒位置必须纹丝不动（瞬移返回检测）
	var after_release: Vector2 = card.position
	await get_tree().create_timer(1.5).timeout
	var no_snapback: bool = card.position.distance_to(after_release) < 1.0
	print("[Edt][%s] 松手后无瞬移回跳 (位移%.2fpx)" % ["PASS" if no_snapback else "FAIL", card.position.distance_to(after_release)])
	# 跟随鼠标断言（不瞬移）：松手时卡片应停在"鼠标最后位置-offset"附近
	var expected: Vector2 = card.position
	var follow_ok: bool = moved and world_moved and no_snapback
	print("[Edt][%s] 拖节点（屏幕动+世界存+无回跳）" % ["PASS" if follow_ok else "FAIL"])
	var all_ok := follow_ok

	# 平移：中键按下→移动→松开
	var view0: Vector2 = editor_ctrl.view_pos
	_send_mouse(editor_ctrl, get_viewport().get_visible_rect().size / 2.0, MOUSE_BUTTON_MIDDLE, true)
	_send_motion(editor_ctrl, get_viewport().get_visible_rect().size / 2.0 + Vector2(120, 60))
	_send_mouse(editor_ctrl, get_viewport().get_visible_rect().size / 2.0 + Vector2(120, 60), MOUSE_BUTTON_MIDDLE, false)
	await get_tree().create_timer(0.2).timeout
	var panned: bool = editor_ctrl.view_pos != view0
	print("[Edt] view0=%s → view1=%s" % [str(view0), str(editor_ctrl.view_pos)])
	print("[Edt][%s] 中键平移视口" % ["PASS" if panned else "FAIL"])
	all_ok = all_ok and panned

	# 缩放：滚轮
	var zoom0: float = editor_ctrl.zoom
	_send_wheel(editor_ctrl, get_viewport().get_visible_rect().size / 2.0)
	await get_tree().create_timer(0.2).timeout
	var zoomed: bool = absf(editor_ctrl.zoom - zoom0) > 0.01
	print("[Edt][%s] 滚轮缩放 (%.2f→%.2f)" % ["PASS" if zoomed else "FAIL", zoom0, editor_ctrl.zoom])
	all_ok = all_ok and zoomed
	# 缩放零漂移断言：全部卡片 position == world_to_screen(存储pos)（与轴/大字严格同系）
	var drift := 0.0
	for n in editor_ctrl._nodes():
		var c := editor_ctrl.canvas.get_node_or_null("Card_" + str(n.get("id"))) as Button
		if c != null:
			drift = maxf(drift, c.position.distance_to(editor_ctrl.world_to_screen(editor_ctrl._pos_to_vec(n.get("pos", editor_ctrl.WORLD_CENTER)))))
	var ok_drift: bool = drift < 0.5
	print("[Edt][%s] 缩放后节点与轴零漂移 (最大%.2fpx)" % ["PASS" if ok_drift else "FAIL", drift])
	all_ok = all_ok and ok_drift

	# 命中一致性（左上枢轴缩放）：zoom 后点"稳如泰山"卡片中心 → 必选中 def_4
	var target_card := editor_ctrl.canvas.get_node_or_null("Card_def_4") as Button
	var hit_center: Vector2 = target_card.position + target_card.size * editor_ctrl.zoom / 2.0
	var hit = editor_ctrl._hit_test_card(hit_center)
	var ok_hit: bool = hit != null and hit.name == "Card_def_4"
	print("[Edt][%s] 缩放后命中一致（点稳如泰山中心选中def_4）" % ["PASS" if ok_hit else "FAIL"])
	all_ok = all_ok and ok_hit

	# 左键空白拖动 = 平移（业内常规）
	var view1: Vector2 = editor_ctrl.view_pos
	var sel0: String = editor_ctrl.selected_id
	# 缩放后取卡片旁的"判定错位区"——正是主人遇到的"吸节点"区域
	var card_edge := (card.position + Vector2(card.size.x, card.size.y / 2.0)) + Vector2(18, 0)
	var corner := Vector2(60, 820)  # 画布左下角（远离全部节点，真空白）
	_send_mouse(editor_ctrl, corner, MOUSE_BUTTON_LEFT, true)
	_send_motion(editor_ctrl, corner + Vector2(90, 50))
	_send_mouse(editor_ctrl, corner + Vector2(90, 50), MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.2).timeout
	var pan2: bool = editor_ctrl.view_pos != view1
	var sel_cleared: bool = editor_ctrl.selected_id == "" and sel0 != ""
	print("[Edt][%s] 左键空白拖=平移" % ["PASS" if pan2 else "FAIL"])
	print("[Edt][%s] 空白松开取消选中" % ["PASS" if sel_cleared else "FAIL"])
	all_ok = all_ok and pan2 and sel_cleared

	# ===== 主人操作流：选中节点→点面板输入框改名称→应用（面板点击不得清空选中）=====
	var inp: LineEdit
	editor_ctrl.selected_id = "buf_6"
	editor_ctrl._fill_prop_panel(editor_ctrl._node_by_id("buf_6"))
	# 模拟点击面板上的名称输入框（x>面板左缘）——此前此点击会清空 selected_id
	_send_mouse(editor_ctrl, Vector2(1150, 120), MOUSE_BUTTON_LEFT, true)
	_send_mouse(editor_ctrl, Vector2(1150, 120), MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.2).timeout
	var sel_kept: bool = editor_ctrl.selected_id == "buf_6"
	_report("面板点击不清空选中", sel_kept, "selected=%s" % editor_ctrl.selected_id)
	all_ok = all_ok and sel_kept
	# 改名并应用
	inp = editor_ctrl.inp_name
	inp.text = "心之力"
	editor_ctrl._on_apply_edit()
	await get_tree().create_timer(0.2).timeout
	var renamed: bool = str(editor_ctrl._node_by_id("buf_6").get("name", "")) == "心之力"
	_report("应用修改改名成功", renamed, str(editor_ctrl._node_by_id("buf_6").get("name", "")))
	all_ok = all_ok and renamed
	var sel_still: bool = editor_ctrl.selected_id == "buf_6"
	_report("应用后选中保持", sel_still, editor_ctrl.selected_id)
	all_ok = all_ok and sel_still

	# 还原名称
	editor_ctrl.inp_name.text = "增益回响"
	editor_ctrl._on_apply_edit()
	print("[Edt] RESULT: %s" % ("PASS" if all_ok else "FAIL"))
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.open("res://docs").make_dir_recursive("img/3d_p2")
		img.save_png("res://docs/img/3d_p2/talent_editor.png")
		print("[Edt] 📷 talent_editor.png")
	get_tree().quit(0 if all_ok else 1)

func _send_mouse(ed: Control, gpos: Vector2, btn: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = gpos
	ev.global_position = gpos
	ev.button_index = btn
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _send_motion(ed: Control, gpos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = gpos
	ev.global_position = gpos
	Input.parse_input_event(ev)

func _send_wheel(ed: Control, gpos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = gpos
	ev.global_position = gpos
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	Input.parse_input_event(ev)

func _report(item: String, ok: bool, detail: String) -> void:
	print("[Edt][%s] %s (%s)" % ["PASS" if ok else "FAIL", item, detail])
