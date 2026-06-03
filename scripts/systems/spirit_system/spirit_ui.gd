extends Control
## 元灵技能系统 UI 面板（独立运行）
## 左侧：元灵头像列表（4个一行，可滚动）
## 右侧：选中元灵详情 + 技能库

# === 数据 ===
var spirits_data: Array = []
var skills_data: Array = []
var selected_spirit: Dictionary = {}
var selected_spirit_index: int = -1

# 测试货币
var spirit_ore: int = 20
var spirit_crystal: int = 30

# === UI 引用 ===
var spirit_scroll: ScrollContainer
var spirit_grid: GridContainer
var detail_avatar: Panel
var detail_name: Label
var detail_desc: Label
var level_label: Label
var active_skill_slots: Array[Panel] = []
var passive_skill_slot: Panel
var skill_library_container: VBoxContainer
var ore_label: Label
var crystal_label: Label

# 弹窗中技能详情的右键回调用
var _popup_slots: Array[Panel] = []

signal close_requested


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1440, 810)
	_load_data()
	_build_ui()
	if spirits_data.size() > 0:
		_select_spirit(0)


func _load_data() -> void:
	var file := FileAccess.open("res://data/spirits/spirits.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		json.parse(file.get_as_text())
		spirits_data = json.data["spirits"]
		file.close()

	file = FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		json.parse(file.get_as_text())
		skills_data = json.data["skills"]
		file.close()

	# 测试数据：每个元灵默认解锁第一个技能
	for s in spirits_data:
		if not s.has("unlocked_skills"):
			s["unlocked_skills"] = [s["skills"][0]]
		if not s.has("equipped_actives"):
			s["equipped_actives"] = [s["skills"][0], "", ""]
		if not s.has("equipped_passive"):
			s["equipped_passive"] = ""
	print("[SpiritUI] 加载 %d 元灵, %d 技能" % [spirits_data.size(), skills_data.size()])


# ============================================================
# 构建 UI
# ============================================================

func _build_ui() -> void:
	# 全屏背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.12, 0.95)
	add_child(bg)

	# 标题
	var title := Label.new()
	title.text = "元灵技能系统"
	title.position = Vector2(600, 10)
	title.size = Vector2(240, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.GOLD)
	add_child(title)

	# 货币
	var cur_bar := HBoxContainer.new()
	cur_bar.position = Vector2(1100, 12)
	add_child(cur_bar)

	ore_label = Label.new()
	ore_label.text = "矿石:%d" % spirit_ore
	ore_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
	ore_label.add_theme_font_size_override("font_size", 14)
	cur_bar.add_child(ore_label)

	var sep := Label.new()
	sep.text = "   "
	cur_bar.add_child(sep)

	crystal_label = Label.new()
	crystal_label.text = "水晶:%d" % spirit_crystal
	crystal_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	crystal_label.add_theme_font_size_override("font_size", 14)
	cur_bar.add_child(crystal_label)

	# 关闭
	var close_btn := Button.new()
	close_btn.text = "关闭[X]"
	close_btn.position = Vector2(1340, 10)
	close_btn.size = Vector2(80, 30)
	close_btn.pressed.connect(func(): close_requested.emit())
	add_child(close_btn)

	# 竖直分割线
	var divider := ColorRect.new()
	divider.position = Vector2(360, 48)
	divider.size = Vector2(2, 740)
	divider.color = Color(0.4, 0.4, 0.5)
	add_child(divider)

	_build_left_panel()
	_build_right_panel()


# === 左侧面板 ===

func _build_left_panel() -> void:
	var left_bg := Panel.new()
	left_bg.position = Vector2(10, 50)
	left_bg.size = Vector2(345, 735)
	add_child(left_bg)
	_set_panel_color(left_bg, Color(0.08, 0.08, 0.15, 0.9), 8)

	var left_title := Label.new()
	left_title.text = "元灵列表"
	left_title.position = Vector2(130, 55)
	left_title.add_theme_font_size_override("font_size", 16)
	left_title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	add_child(left_title)

	# 滚动容器
	spirit_scroll = ScrollContainer.new()
	spirit_scroll.position = Vector2(20, 80)
	spirit_scroll.size = Vector2(325, 695)
	spirit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(spirit_scroll)

	spirit_grid = GridContainer.new()
	spirit_grid.columns = 4
	spirit_grid.add_theme_constant_override("h_separation", 8)
	spirit_grid.add_theme_constant_override("v_separation", 12)
	spirit_scroll.add_child(spirit_grid)

	for i in range(spirits_data.size()):
		spirit_grid.add_child(_create_spirit_icon(spirits_data[i], i))


func _create_spirit_icon(spirit: Dictionary, index: int) -> VBoxContainer:
	"""创建单个元灵圆形头像（用 VBoxContainer 保证 GridContainer 正确排列）"""
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	# 强制最小尺寸让 GridContainer 正确排版
	vbox.custom_minimum_size = Vector2(72, 95)

	# 圆形头像（Panel + 圆角）
	var icon_color := Color.from_string(spirit.get("icon_color", "#FFFFFF"), Color.WHITE)
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.size = Vector2(64, 64)
	avatar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_set_panel_color(avatar, icon_color, 30)
	avatar.gui_input.connect(_on_icon_input.bind(index))
	vbox.add_child(avatar)

	# 等级
	var lvl := Label.new()
	lvl.text = "Lv%d" % spirit.get("level", 1)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.add_theme_font_size_override("font_size", 10)
	lvl.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(lvl)

	# 名称
	var name_label := Label.new()
	name_label.text = spirit["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(name_label)

	return vbox


func _on_icon_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_spirit(index)


# === 右侧面板 ===

func _build_right_panel() -> void:
	# 右侧背景
	var right_bg := Panel.new()
	right_bg.position = Vector2(370, 50)
	right_bg.size = Vector2(1060, 735)
	add_child(right_bg)
	_set_panel_color(right_bg, Color(0.08, 0.08, 0.18, 0.8), 8)

	# --- 头像（圆形） ---
	detail_avatar = Panel.new()
	detail_avatar.position = Vector2(395, 68)
	detail_avatar.size = Vector2(80, 80)
	_set_panel_color(detail_avatar, Color.GOLD, 38)
	add_child(detail_avatar)

	# --- 名称 ---
	detail_name = Label.new()
	detail_name.position = Vector2(490, 68)
	detail_name.size = Vector2(400, 28)
	detail_name.add_theme_font_size_override("font_size", 20)
	detail_name.add_theme_color_override("font_color", Color.WHITE)
	add_child(detail_name)

	# --- 等级 ---
	level_label = Label.new()
	level_label.position = Vector2(490, 98)
	level_label.size = Vector2(200, 22)
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(level_label)

	# --- 描述 ---
	detail_desc = Label.new()
	detail_desc.position = Vector2(490, 122)
	detail_desc.size = Vector2(550, 22)
	detail_desc.add_theme_font_size_override("font_size", 12)
	detail_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(detail_desc)

	# --- 上场技能标签 ---
	var skill_title := Label.new()
	skill_title.text = "上场技能"
	skill_title.position = Vector2(395, 160)
	skill_title.add_theme_font_size_override("font_size", 14)
	skill_title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	add_child(skill_title)

	# 3个主动技能槽（方形）
	var slot_x: float = 395.0
	for i in range(3):
		var slot := Panel.new()
		slot.position = Vector2(slot_x + i * 72, 183)
		slot.size = Vector2(64, 64)
		slot.custom_minimum_size = Vector2(64, 64)
		_set_panel_color(slot, Color(0.15, 0.15, 0.25), 4)
		# 主动标签
		var tag := Label.new()
		tag.text = "主动%d" % (i + 1)
		tag.position = Vector2(14, 48)
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		slot.add_child(tag)
		active_skill_slots.append(slot)
		add_child(slot)

	# 被动技能槽
	passive_skill_slot = Panel.new()
	passive_skill_slot.position = Vector2(slot_x + 216, 183)
	passive_skill_slot.size = Vector2(64, 64)
	passive_skill_slot.custom_minimum_size = Vector2(64, 64)
	_set_panel_color(passive_skill_slot, Color(0.15, 0.12, 0.2), 4)
	var ptag := Label.new()
	ptag.text = "被动"
	ptag.position = Vector2(18, 48)
	ptag.add_theme_font_size_override("font_size", 10)
	ptag.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	passive_skill_slot.add_child(ptag)
	add_child(passive_skill_slot)

	# --- 3个按钮 ---
	var btn_y: float = 260
	var btn_edit := Button.new()
	btn_edit.text = "修改上场技能"
	btn_edit.position = Vector2(395, btn_y)
	btn_edit.size = Vector2(130, 32)
	btn_edit.add_theme_font_size_override("font_size", 13)
	btn_edit.pressed.connect(_on_edit_skills)
	add_child(btn_edit)

	var btn_confirm := Button.new()
	btn_confirm.text = "确认"
	btn_confirm.position = Vector2(535, btn_y)
	btn_confirm.size = Vector2(80, 32)
	btn_confirm.add_theme_font_size_override("font_size", 13)
	btn_confirm.pressed.connect(_on_confirm)
	add_child(btn_confirm)

	var btn_upgrade := Button.new()
	btn_upgrade.text = "升级元灵"
	btn_upgrade.position = Vector2(625, btn_y)
	btn_upgrade.size = Vector2(110, 32)
	btn_upgrade.add_theme_font_size_override("font_size", 13)
	btn_upgrade.pressed.connect(_on_upgrade_spirit)
	add_child(btn_upgrade)

	# --- 分隔线 ---
	var sepline := ColorRect.new()
	sepline.position = Vector2(395, 305)
	sepline.size = Vector2(1000, 1)
	sepline.color = Color(0.4, 0.4, 0.5)
	add_child(sepline)

	# --- 技能库标题 ---
	var lib_title := Label.new()
	lib_title.text = "技能库"
	lib_title.position = Vector2(395, 312)
	lib_title.add_theme_font_size_override("font_size", 16)
	lib_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	add_child(lib_title)

	# --- 技能库滚动区域 ---
	var lib_scroll := ScrollContainer.new()
	lib_scroll.position = Vector2(395, 338)
	lib_scroll.size = Vector2(1000, 440)
	lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(lib_scroll)

	skill_library_container = VBoxContainer.new()
	skill_library_container.add_theme_constant_override("separation", 6)
	lib_scroll.add_child(skill_library_container)


# ============================================================
# 选中元灵 / 刷新
# ============================================================

func _select_spirit(index: int) -> void:
	if index < 0 or index >= spirits_data.size():
		return
	selected_spirit_index = index
	selected_spirit = spirits_data[index]

	var icon_color := Color.from_string(selected_spirit.get("icon_color", "#FFFFFF"), Color.WHITE)
	_set_panel_color(detail_avatar, icon_color, 38)
	detail_name.text = "%s（%s）" % [selected_spirit["name"], selected_spirit["element"]]
	level_label.text = "等级 %d / %d" % [selected_spirit.get("level", 1), selected_spirit.get("max_level", 10)]
	detail_desc.text = selected_spirit.get("description", "")

	_update_equipped_slots()
	_update_skill_library()
	print("[SpiritUI] 选中: %s(%s)" % [selected_spirit["name"], selected_spirit["element"]])


func _update_equipped_slots() -> void:
	var equipped_actives: Array = selected_spirit.get("equipped_actives", ["", "", ""])
	var equipped_passive: String = selected_spirit.get("equipped_passive", "")

	for i in range(3):
		_clear_panel(active_skill_slots[i])
		_set_panel_color(active_skill_slots[i], Color(0.15, 0.15, 0.25), 4)
		if i < equipped_actives.size() and equipped_actives[i] != "":
			var skill = _get_skill_by_id(equipped_actives[i])
			if skill.size() > 0:
				_fill_skill_slot(active_skill_slots[i], skill)
		# 恢复标签
		var tag := Label.new()
		tag.text = "主动%d" % (i + 1)
		tag.position = Vector2(14, 48)
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		active_skill_slots[i].add_child(tag)

	_clear_panel(passive_skill_slot)
	_set_panel_color(passive_skill_slot, Color(0.15, 0.12, 0.2), 4)
	if equipped_passive != "":
		var skill = _get_skill_by_id(equipped_passive)
		if skill.size() > 0:
			_fill_skill_slot(passive_skill_slot, skill)
	var ptag := Label.new()
	ptag.text = "被动"
	ptag.position = Vector2(18, 48)
	ptag.add_theme_font_size_override("font_size", 10)
	ptag.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	passive_skill_slot.add_child(ptag)


func _fill_skill_slot(slot: Panel, skill: Dictionary) -> void:
	"""填充技能槽位（方形图标+名称缩写）"""
	var icon_color := Color.from_string(skill.get("icon_color", "#888"), Color.GRAY)
	_set_panel_color(slot, icon_color, 4)

	var abbr := Label.new()
	abbr.text = skill["name"].left(2)
	abbr.position = Vector2(8, 20)
	abbr.add_theme_font_size_override("font_size", 16)
	abbr.add_theme_color_override("font_color", Color.WHITE)
	slot.add_child(abbr)

	# 右键查看技能详情
	slot.gui_input.connect(_on_slot_right_click.bind(skill))


func _on_slot_right_click(event: InputEvent, skill: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_skill_popup(skill, true, "")


func _update_skill_library() -> void:
	for child in skill_library_container.get_children():
		child.queue_free()

	var spirit_skills: Array = selected_spirit.get("skills", [])
	var unlocked: Array = selected_spirit.get("unlocked_skills", [])

	for skill_id in spirit_skills:
		var skill = _get_skill_by_id(skill_id)
		if skill.size() == 0:
			continue
		var is_unlocked: bool = skill_id in unlocked
		skill_library_container.add_child(_create_library_entry(skill, is_unlocked, skill_id))


func _create_library_entry(skill: Dictionary, is_unlocked: bool, skill_id: String) -> Control:
	"""技能库中的一行（Control容器，叠加覆盖按钮）"""
	var row := Control.new()
	row.custom_minimum_size = Vector2(950, 65)
	row.size = Vector2(950, 65)

	# 方形图标
	var icon_color := Color.from_string(skill.get("icon_color", "#888"), Color.GRAY)
	var icon := Panel.new()
	icon.position = Vector2(0, 5)
	icon.size = Vector2(52, 52)
	icon.custom_minimum_size = Vector2(52, 52)
	if is_unlocked:
		_set_panel_color(icon, icon_color, 6)
	else:
		_set_panel_color(icon, Color(0.2, 0.2, 0.2), 6)
	row.add_child(icon)

	# 锁
	if not is_unlocked:
		var lock := Label.new()
		lock.text = "🔒"
		lock.position = Vector2(16, 14)
		lock.add_theme_font_size_override("font_size", 18)
		icon.add_child(lock)

	# 右侧信息
	var info_x: float = 62.0

	var name_label := Label.new()
	name_label.text = "%s  [%s]" % [skill["name"], skill["type"]]
	name_label.position = Vector2(info_x, 5)
	name_label.size = Vector2(880, 18)
	name_label.add_theme_font_size_override("font_size", 13)
	if is_unlocked:
		name_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = skill.get("description", "")
	desc_label.position = Vector2(info_x, 24)
	desc_label.size = Vector2(880, 18)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(desc_label)

	if not is_unlocked:
		var cost_label := Label.new()
		cost_label.text = "解锁: %d 元灵水晶" % skill.get("unlock_cost", 0)
		cost_label.position = Vector2(info_x, 43)
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
		row.add_child(cost_label)

	# 覆盖整行的透明按钮（最上层，接收右键）
	var click := Button.new()
	click.flat = true
	click.position = Vector2(0, 0)
	click.size = Vector2(950, 65)
	click.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	click.gui_input.connect(_on_entry_input.bind(skill, is_unlocked, skill_id))
	row.add_child(click)

	return row


func _on_entry_input(event: InputEvent, skill: Dictionary, is_unlocked: bool, skill_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_skill_popup(skill, is_unlocked, skill_id)


# ============================================================
# 技能详情弹窗
# ============================================================

func _show_skill_popup(skill: Dictionary, is_unlocked: bool, skill_id: String) -> void:
	var old = get_node_or_null("SkillPopup")
	if old:
		old.queue_free()

	var popup := Panel.new()
	popup.name = "SkillPopup"
	popup.position = Vector2(460, 280)
	popup.size = Vector2(520, 340)
	_set_panel_color(popup, Color(0.1, 0.1, 0.22, 0.98), 10)
	add_child(popup)

	# 技能名
	var title := Label.new()
	title.text = skill["name"]
	title.position = Vector2(20, 15)
	title.size = Vector2(480, 28)
	title.add_theme_font_size_override("font_size", 18)
	var name_color := Color.from_string(skill.get("icon_color", "#FFF"), Color.WHITE)
	title.add_theme_color_override("font_color", name_color)
	popup.add_child(title)

	# 类型+元素
	var type_label := Label.new()
	type_label.text = "[%s]  元素: %s" % [skill["type"], skill.get("element", "?")]
	type_label.position = Vector2(20, 45)
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	popup.add_child(type_label)

	# 描述
	var desc := Label.new()
	desc.text = skill.get("description", "")
	desc.position = Vector2(20, 68)
	desc.size = Vector2(480, 40)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color.WHITE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	popup.add_child(desc)

	# 详细效果
	var detail := Label.new()
	detail.text = skill.get("detail", "")
	detail.position = Vector2(20, 112)
	detail.size = Vector2(480, 120)
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	popup.add_child(detail)

	if not is_unlocked:
		var unlock_btn := Button.new()
		var cost: int = skill.get("unlock_cost", 0)
		unlock_btn.text = "解锁（%d 元灵水晶）" % cost
		unlock_btn.position = Vector2(150, 240)
		unlock_btn.size = Vector2(220, 36)
		unlock_btn.add_theme_font_size_override("font_size", 14)
		unlock_btn.disabled = (spirit_crystal < cost)
		unlock_btn.pressed.connect(_on_unlock_skill.bind(skill_id, cost))
		popup.add_child(unlock_btn)

		if spirit_crystal < cost:
			var warn := Label.new()
			warn.text = "水晶不足！"
			warn.position = Vector2(210, 282)
			warn.add_theme_color_override("font_color", Color.RED)
			warn.add_theme_font_size_override("font_size", 12)
			popup.add_child(warn)
	else:
		var owned := Label.new()
		owned.text = "✅ 已解锁"
		owned.position = Vector2(220, 245)
		owned.add_theme_color_override("font_color", Color.GREEN)
		owned.add_theme_font_size_override("font_size", 14)
		popup.add_child(owned)

	# 关闭
	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(220, 295)
	close.size = Vector2(80, 28)
	close.pressed.connect(func(): popup.queue_free())
	popup.add_child(close)


# ============================================================
# 按钮回调
# ============================================================

func _on_unlock_skill(skill_id: String, cost: int) -> void:
	if spirit_crystal < cost or selected_spirit_index < 0:
		return
	spirit_crystal -= cost
	crystal_label.text = "水晶:%d" % spirit_crystal

	var unlocked: Array = selected_spirit.get("unlocked_skills", [])
	if not skill_id in unlocked:
		unlocked.append(skill_id)
		selected_spirit["unlocked_skills"] = unlocked

	_update_skill_library()
	var popup = get_node_or_null("SkillPopup")
	if popup:
		popup.queue_free()
	print("[SpiritUI] 解锁: %s (消耗%d水晶)" % [skill_id, cost])


func _on_edit_skills() -> void:
	print("[SpiritUI] 修改上场技能 - 待实现")


func _on_confirm() -> void:
	print("[SpiritUI] 确认配置: %s" % selected_spirit.get("name", "?"))


func _on_upgrade_spirit() -> void:
	if selected_spirit_index < 0:
		return
	var level: int = selected_spirit.get("level", 1)
	var max_level: int = selected_spirit.get("max_level", 10)
	if level >= max_level:
		print("[SpiritUI] 已满级!")
		return
	var cost: int = level * 2
	if spirit_ore < cost:
		print("[SpiritUI] 矿石不足! 需要%d" % cost)
		return
	spirit_ore -= cost
	selected_spirit["level"] = level + 1
	ore_label.text = "矿石:%d" % spirit_ore
	level_label.text = "等级 %d / %d" % [selected_spirit["level"], max_level]
	print("[SpiritUI] %s 升级 Lv%d (消耗%d矿石)" % [selected_spirit["name"], selected_spirit["level"], cost])


func _on_close() -> void:
	visible = false


# ============================================================
# 辅助
# ============================================================

func _get_skill_by_id(skill_id: String) -> Dictionary:
	for s in skills_data:
		if s["id"] == skill_id:
			return s
	return {}


func _clear_panel(panel: Panel) -> void:
	for child in panel.get_children():
		child.queue_free()
	# 断开所有信号连接（防止重复连接）
	var connections = panel.gui_input.get_connections()
	for conn in connections:
		panel.gui_input.disconnect(conn["callable"])


func _set_panel_color(panel: Panel, color: Color, radius: int) -> void:
	"""设置 Panel 的背景色和圆角"""
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", style)
