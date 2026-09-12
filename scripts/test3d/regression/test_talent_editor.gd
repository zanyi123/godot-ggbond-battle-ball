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
	# 拖节点：左键按下→移动→松开
	_send_mouse(editor_ctrl, card.get_global_position() + Vector2(30, 20), MOUSE_BUTTON_LEFT, true)
	for i in range(5):
		_send_motion(editor_ctrl, card.get_global_position() + Vector2(30, 20) + Vector2(40, 25) * (i + 1))
		await get_tree().process_frame
	_send_mouse(editor_ctrl, card.get_global_position() + Vector2(30, 20) + Vector2(200, 125), MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.2).timeout
	var moved: bool = card.position.distance_to(pos0) > 100.0
	var world_moved: bool = editor_ctrl._pos_to_vec(editor_ctrl._node_by_id("atk_1")["pos"]).distance_to(world0) > 100.0
	# 跟随鼠标断言（不瞬移）：松手时卡片应停在"鼠标最后位置-offset"附近
	var expected: Vector2 = card.position
	var follow_ok: bool = moved and world_moved
	print("[Edt][%s] 拖节点（屏幕动+世界存）" % ["PASS" if follow_ok else "FAIL"])
	var all_ok := follow_ok

	# 平移：中键按下→移动→松开
	var view0: Vector2 = editor_ctrl.view_pos
	_send_mouse(editor_ctrl, get_viewport().get_visible_rect().size / 2.0, MOUSE_BUTTON_MIDDLE, true)
	_send_motion(editor_ctrl, get_viewport().get_visible_rect().size / 2.0 + Vector2(120, 60))
	_send_mouse(editor_ctrl, get_viewport().get_visible_rect().size / 2.0 + Vector2(120, 60), MOUSE_BUTTON_MIDDLE, false)
	await get_tree().create_timer(0.2).timeout
	var panned: bool = editor_ctrl.view_pos != view0
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

	# 左键空白拖动 = 平移（业内常规）
	var view1: Vector2 = editor_ctrl.view_pos
	var sel0: String = editor_ctrl.selected_id
	# 缩放后取卡片旁的"判定错位区"——正是主人遇到的"吸节点"区域
	var card_edge := (card.position + Vector2(card.size.x, card.size.y / 2.0)) + Vector2(18, 0)
	var corner := card_edge
	_send_mouse(editor_ctrl, corner, MOUSE_BUTTON_LEFT, true)
	_send_motion(editor_ctrl, corner + Vector2(90, 50))
	_send_mouse(editor_ctrl, corner + Vector2(90, 50), MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.2).timeout
	var pan2: bool = editor_ctrl.view_pos != view1
	var sel_cleared: bool = editor_ctrl.selected_id == "" and sel0 != ""
	print("[Edt][%s] 左键空白拖=平移" % ["PASS" if pan2 else "FAIL"])
	print("[Edt][%s] 空白松开取消选中" % ["PASS" if sel_cleared else "FAIL"])
	all_ok = all_ok and pan2 and sel_cleared

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
