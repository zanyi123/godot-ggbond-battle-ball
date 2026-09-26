extends CanvasLayer
## 工单10 P2.5 排表确认面板（主人令 2026-09-26）—— 平台窗口
## F6 后先弹出「本次测试排表」：6 槽位 × 携带元灵一览（数据=装载结果实际状态）；
## 点「确认开始比赛」才开赛；右键元灵行 = 查看本次测试的技能明细（名称/操作/能量/CD/标签）。
## headless 自动模式不建本层。

signal confirmed

var bm: Node2D = null
var _slots: Dictionary = {}       # slot -> {char, spirit_id, spirit_name, element, skills, fallback}
var _root: Control = null
var _viewer: PopupPanel = null

const SLOT_ORDER := ["A0", "A1", "A2", "B0", "B1", "B2"]


func setup(battle_manager: Node2D, loadout_stats: Dictionary) -> void:
	bm = battle_manager
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	var slots_data = loadout_stats.get("slots", {})
	if slots_data is Dictionary:
		_slots = slots_data
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "RosterRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 全屏暗幕（遮住底下尚未隐藏的备战面板，同时挡输入）
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(560, 0)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "本次测试排表（工单配置：test_loadouts.json）"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "新技能先经快捷开发系统（元灵管理面板）导入 skills.json，再在此配置引用；确认后才开赛。"
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	for slot in SLOT_ORDER:
		vbox.add_child(_make_row(slot))

	vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "右键点元灵行 = 查看本次测试的技能明细"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 0.9, 0.5, 0.9)
	vbox.add_child(hint)

	var btn := Button.new()
	btn.text = "✅ 确认开始比赛"
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_on_confirm)
	vbox.add_child(btn)


func _make_row(slot: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = "右键查看 %s 的技能明细" % slot

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var info: Dictionary = _slots.get(slot, {})
	var spirit_name := str(info.get("spirit_name", "（兜底装载）"))
	var element := str(info.get("element", ""))
	var skill_list = info.get("skills", [])
	var char_name := str(info.get("char", "?"))
	var is_fallback := bool(info.get("fallback", false))

	var l_slot := Label.new()
	l_slot.text = slot
	l_slot.custom_minimum_size = Vector2(36, 0)
	l_slot.add_theme_font_size_override("font_size", 15)
	hbox.add_child(l_slot)

	var l_char := Label.new()
	l_char.text = char_name
	l_char.custom_minimum_size = Vector2(90, 0)
	l_char.add_theme_font_size_override("font_size", 14)
	hbox.add_child(l_char)

	var l_spirit := Label.new()
	l_spirit.text = spirit_name + (("（%s）" % element) if not element.is_empty() else "")
	l_spirit.add_theme_font_size_override("font_size", 14)
	if is_fallback:
		l_spirit.modulate = Color(1, 0.75, 0.4)  # 兜底装备橙色提示
	hbox.add_child(l_spirit)

	var l_count := Label.new()
	l_count.text = "技能×%d%s" % [skill_list.size(), "（兜底）" if is_fallback else ""]
	l_count.add_theme_font_size_override("font_size", 12)
	l_count.modulate = Color(1, 1, 1, 0.7)
	l_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(l_count)

	row.gui_input.connect(_on_row_gui_input.bind(slot))
	return row


func _on_row_gui_input(event: InputEvent, slot: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_skill_viewer(slot)


# ==================== 右键：技能明细查看器 ====================

func _show_skill_viewer(slot: String) -> void:
	if _viewer != null:
		_viewer.queue_free()
		_viewer = null
	var info: Dictionary = _slots.get(slot, {})
	if info.is_empty():
		return

	_viewer = PopupPanel.new()
	_viewer.title = "%s %s —— 本次测试的技能" % [slot, str(info.get("spirit_name", "?"))]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(460, 0)
	_viewer.add_child(vbox)

	var skill_list: Array = info.get("skills", [])
	if skill_list.is_empty():
		var empty := Label.new()
		empty.text = "（该槽位无技能——请检查 test_loadouts.json）"
		vbox.add_child(empty)
	for sid in skill_list:
		vbox.add_child(_make_skill_line(str(sid)))

	var tip := Label.new()
	tip.text = "（点击面板外部关闭）"
	tip.add_theme_font_size_override("font_size", 11)
	tip.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(tip)

	add_child(_viewer)
	_viewer.popup_centered()


func _make_skill_line(skill_id: String) -> Label:
	var line := Label.new()
	line.add_theme_font_size_override("font_size", 13)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for skill_data in DataManager.skills:
		if str(skill_data.get("id", "")) != skill_id:
			continue
		var tags = skill_data.get("tags", [])
		var tag_names: Array[String] = []
		for t in tags:
			tag_names.append(str(t))
		var op := str(skill_data.get("operator", ""))
		line.text = "· %s（%s）\n    操作:%s | 能量:%s | CD:%s | 标签: %s" % [
			str(skill_data.get("name", skill_id)), skill_id,
			op if not op.is_empty() else "AUTO",
			str(skill_data.get("energy_cost", "?")),
			str(skill_data.get("cooldown", "?")),
			", ".join(tag_names) if not tag_names.is_empty() else "无",
		]
		return line
	line.text = "· ⚠ %s（skills.json 查无——该技能未导入）" % skill_id
	return line


func _on_confirm() -> void:
	confirmed.emit()
	queue_free()
