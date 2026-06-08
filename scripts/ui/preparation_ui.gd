extends Control
## 备战界面 - 比赛前和中场休息时使用
## 功能：球员替补、元灵切换、战术策略配置

const AIProfile = preload("res://scripts/battle/ai_profile.gd")

signal strategy_changed(player_strategy: int, team_strategy: int)
signal player_substituted(index: int, new_char_id: String)
signal spirit_changed(index: int, spirit_id: String)
signal match_started_from_prep()

# 策略枚举
enum PlayerStrategy {
	BREAKTHROUGH,
	DEFENSE,
	PASSING
}

enum TeamStrategy {
	OFFENSIVE,
	DEFENSIVE,
	BALANCED
}

# 当前策略
var current_player_strategy: int = PlayerStrategy.PASSING
var current_team_strategy: int = TeamStrategy.BALANCED

# AI Profile 映射
var current_role: String = "supporter"
var current_team_strategy_str: String = "balanced"
var current_difficulty: String = "normal"

# 战斗数据引用
var team_a_players: Array[CharacterBody2D] = []
var available_characters: Array[Dictionary] = []

# AI管理器引用
var ai_manager: Node = null

# UI元素引用
var player_widgets: Array[Dictionary] = []
var spirit_widgets: Array[Dictionary] = []
var strategy_buttons: Array[Button] = []

# 开始按钮引用
var start_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	"""构建整个备战界面"""
	# 全屏半透明背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.15, 0.92)
	add_child(bg)
	
	# 标题
	var title := Label.new()
	title.text = "⚔ 备战界面 ⚔"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 15)
	title.size = Vector2(1200, 35)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	add_child(title)
	
	# === 第一行：球员状态（3个独立卡片，横向排列）===
	_build_player_row()
	
	# === 第二行：元灵选择（3个独立卡片，横向排列）===
	_build_spirit_row()
	
	# === 第三行：战术策略 ===
	_build_strategy_panel()
	
	# === 底部：开始比赛按钮 ===
	start_btn = Button.new()
	start_btn.text = "开始比赛!"
	start_btn.position = Vector2(475, 620)
	start_btn.size = Vector2(250, 50)
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(_on_start_match)
	add_child(start_btn)


# ===== 第一行：球员状态 =====

func _build_player_row() -> void:
	"""构建球员状态行（3个独立卡片）"""
	var section_title := Label.new()
	section_title.text = "— 球员状态 —"
	section_title.position = Vector2(0, 60)
	section_title.size = Vector2(1200, 25)
	section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_title.add_theme_font_size_override("font_size", 18)
	section_title.add_theme_color_override("font_color", Color.YELLOW)
	add_child(section_title)
	
	# 3个卡片横向排列
	for i in range(3):
		var x_pos: float = 50 + i * 390  # 每卡片370px宽，间隔20px
		_build_player_card(i, x_pos, 95)


func _build_player_card(index: int, x: float, y: float) -> void:
	"""创建单个球员状态卡片"""
	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size = Vector2(370, 160)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.15, 0.15, 0.22, 0.95)
	card_style.border_color = Color(0.3, 0.7, 1.0, 0.5)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)
	
	# 位置标签
	var pos_label := Label.new()
	pos_label.text = "位置 %d" % (index + 1)
	pos_label.position = Vector2(10, 8)
	pos_label.add_theme_font_size_override("font_size", 16)
	pos_label.add_theme_color_override("font_color", Color.CYAN)
	card.add_child(pos_label)
	
	# 球员名称
	var name_label := Label.new()
	name_label.text = "未选择"
	name_label.position = Vector2(80, 8)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	card.add_child(name_label)
	
	# 体力条
	var stamina_label := Label.new()
	stamina_label.text = "体力:"
	stamina_label.position = Vector2(10, 38)
	stamina_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(stamina_label)
	
	var stamina_bar := ProgressBar.new()
	stamina_bar.position = Vector2(60, 38)
	stamina_bar.size = Vector2(200, 18)
	stamina_bar.value = 100.0
	stamina_bar.show_percentage = false
	card.add_child(stamina_bar)
	
	var stamina_val := Label.new()
	stamina_val.text = "100"
	stamina_val.position = Vector2(270, 38)
	stamina_val.add_theme_color_override("font_color", Color.GREEN)
	card.add_child(stamina_val)
	
	# 速度
	var speed_label := Label.new()
	speed_label.text = "速度: --"
	speed_label.position = Vector2(10, 65)
	speed_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(speed_label)
	
	# 攻击力
	var attack_label := Label.new()
	attack_label.text = "攻击: --"
	attack_label.position = Vector2(140, 65)
	attack_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(attack_label)
	
	# 防御
	var defense_label := Label.new()
	defense_label.text = "防御: --"
	defense_label.position = Vector2(260, 65)
	defense_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(defense_label)
	
	# 替补按钮
	var sub_btn := Button.new()
	sub_btn.text = "替补"
	sub_btn.position = Vector2(10, 100)
	sub_btn.size = Vector2(80, 30)
	sub_btn.pressed.connect(_on_substitute_player.bind(index))
	card.add_child(sub_btn)
	
	# 状态标签
	var state_label := Label.new()
	state_label.text = "状态: 正常"
	state_label.position = Vector2(110, 105)
	state_label.add_theme_color_override("font_color", Color.GREEN)
	card.add_child(state_label)
	
	player_widgets.append({
		"card": card,
		"name_label": name_label,
		"stamina_bar": stamina_bar,
		"stamina_val": stamina_val,
		"speed_label": speed_label,
		"attack_label": attack_label,
		"defense_label": defense_label,
		"sub_btn": sub_btn,
		"state_label": state_label
	})


# ===== 第二行：元灵选择 =====

func _build_spirit_row() -> void:
	"""构建元灵选择行（3个独立卡片）"""
	var section_title := Label.new()
	section_title.text = "— 元灵选择 —"
	section_title.position = Vector2(0, 270)
	section_title.size = Vector2(1200, 25)
	section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_title.add_theme_font_size_override("font_size", 18)
	section_title.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
	add_child(section_title)
	
	for i in range(3):
		var x_pos: float = 50 + i * 390
		_build_spirit_card(i, x_pos, 305)


func _build_spirit_card(index: int, x: float, y: float) -> void:
	"""创建单个元灵选择卡片"""
	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size = Vector2(370, 140)
	# 卡片样式：深色背景+亮边框
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.15, 0.15, 0.22, 0.95)
	card_style.border_color = Color(1.0, 0.6, 0.2, 0.6)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)
	
	# 位置标签
	var pos_label := Label.new()
	pos_label.text = "位置 %d 元灵" % (index + 1)
	pos_label.position = Vector2(10, 8)
	pos_label.add_theme_font_size_override("font_size", 15)
	pos_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
	card.add_child(pos_label)
	
	# 当前元灵名称
	var current_label := Label.new()
	current_label.text = "当前: 未装备"
	current_label.position = Vector2(10, 35)
	current_label.add_theme_font_size_override("font_size", 14)
	current_label.add_theme_color_override("font_color", Color.WHITE)
	card.add_child(current_label)
	
	# 元灵属性
	var attr_label := Label.new()
	attr_label.text = "加成: 无"
	attr_label.position = Vector2(10, 58)
	attr_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	card.add_child(attr_label)
	
	# 更换按钮（加大尺寸和高亮）
	var change_btn := Button.new()
	change_btn.text = "更换元灵"
	change_btn.position = Vector2(10, 88)
	change_btn.size = Vector2(140, 38)
	change_btn.add_theme_font_size_override("font_size", 16)
	change_btn.pressed.connect(_on_change_spirit.bind(index))
	card.add_child(change_btn)
	
	# 元灵图标（用Panel显示元素颜色圆形）
	var icon_panel := Panel.new()
	icon_panel.position = Vector2(280, 15)
	icon_panel.size = Vector2(70, 70)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.3, 0.3, 0.4)
	icon_style.set_corner_radius_all(35)
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	card.add_child(icon_panel)
	
	var icon_label := Label.new()
	icon_label.text = "未\n装备"
	icon_label.position = Vector2(285, 28)
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	card.add_child(icon_label)
	
	spirit_widgets.append({
		"card": card,
		"current_label": current_label,
		"attr_label": attr_label,
		"change_btn": change_btn,
		"icon_panel": icon_panel,
		"icon_label": icon_label
	})


# ===== 第三行：战术策略 =====

func _build_strategy_panel() -> void:
	"""构建战术策略面板"""
	var section_title := Label.new()
	section_title.text = "— 战术策略 —"
	section_title.position = Vector2(0, 460)
	section_title.size = Vector2(1200, 25)
	section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_title.add_theme_font_size_override("font_size", 18)
	section_title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	add_child(section_title)
	
	# 个人策略
	var personal_label := Label.new()
	personal_label.text = "个人策略:"
	personal_label.position = Vector2(80, 495)
	personal_label.add_theme_font_size_override("font_size", 15)
	personal_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	add_child(personal_label)
	
	_create_strategy_btn("突破进攻", PlayerStrategy.BREAKTHROUGH, 200, 492, 0)
	_create_strategy_btn("防守反击", PlayerStrategy.DEFENSE, 310, 492, 1)
	_create_strategy_btn("传球配合", PlayerStrategy.PASSING, 420, 492, 2)
	
	# 团队策略
	var team_label := Label.new()
	team_label.text = "团队策略:"
	team_label.position = Vector2(560, 495)
	team_label.add_theme_font_size_override("font_size", 15)
	team_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	add_child(team_label)
	
	_create_strategy_btn("全力进攻", TeamStrategy.OFFENSIVE + 3, 680, 492, 3)
	_create_strategy_btn("全力防守", TeamStrategy.DEFENSIVE + 3, 790, 492, 4)
	_create_strategy_btn("攻守平衡", TeamStrategy.BALANCED + 3, 900, 492, 5)
	
	# 策略说明
	var desc := Label.new()
	desc.text = "策略影响AI队友的行为模式，可随时切换"
	desc.position = Vector2(350, 535)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_child(desc)


func _create_strategy_btn(text: String, strategy: int, x: float, y: float, btn_index: int) -> void:
	"""创建策略按钮"""
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(x, y)
	btn.size = Vector2(100, 35)
	btn.pressed.connect(_on_strategy_selected.bind(strategy))
	btn.toggle_mode = true
	add_child(btn)
	strategy_buttons.append(btn)


# ===== 数据加载 =====

func load_battle_data(players: Array[CharacterBody2D]) -> void:
	"""加载比赛数据并更新显示"""
	team_a_players = players
	for i in range(min(3, players.size())):
		var player: CharacterBody2D = players[i]
		if player and i < player_widgets.size():
			_update_player_widget(i, player)


func _update_player_widget(index: int, player: CharacterBody2D) -> void:
	"""更新单个球员卡片"""
	var w: Dictionary = player_widgets[index]
	
	if player.char_data and player.char_data.has("name"):
		w.name_label.text = str(player.char_data.name)
	
	if player.char_data:
		var speed_val: float = player.char_data.get("speed", 100.0)
		var attack_val: float = player.char_data.get("attack", 100.0)
		var defense_val: float = player.char_data.get("defense", 100.0)
		w.speed_label.text = "速度: %.0f" % speed_val
		w.attack_label.text = "攻击: %.0f" % attack_val
		w.defense_label.text = "防御: %.0f" % defense_val
	
	w.stamina_bar.value = 100.0
	w.stamina_val.text = "100"


# ===== 信号处理 =====

func _on_strategy_selected(strategy: int) -> void:
	"""策略选择 → 映射到 AIProfile 参数"""
	if strategy < 3:
		current_player_strategy = strategy
		match strategy:
			0: current_role = "attacker"
			1: current_role = "defender"
			2: current_role = "supporter"
	else:
		current_team_strategy = strategy - 3
		match strategy - 3:
			0: current_team_strategy_str = "offensive"
			1: current_team_strategy_str = "defensive"
			2: current_team_strategy_str = "balanced"
	
	# 更新所有AI队友的profile（保持各自角色，只更新团队策略）
	_rebuild_team_a_profiles()
	_update_strategy_button_styles()
	strategy_changed.emit(current_player_strategy, current_team_strategy)
	print("[备战] 策略: 个人=%s 团队=%s" % [current_role, current_team_strategy_str])


func _rebuild_team_a_profiles() -> void:
	"""重建队A所有AI队友的profile（保持各自角色分工，只更新团队策略）"""
	if not ai_manager:
		return
	# 3个队友保持各自角色，不统一改成同一角色
	var roles := ["attacker", "defender", "supporter"]
	for i in range(3):
		var profile: AIProfile = AIProfile.get_role_preset(roles[i])
		AIProfile.apply_team_strategy(profile, current_team_strategy_str)
		AIProfile.apply_difficulty(profile, current_difficulty)
		ai_manager.update_player_profile(i, profile)


func _update_strategy_button_styles() -> void:
	for i in range(strategy_buttons.size()):
		var btn: Button = strategy_buttons[i]
		if i < 3:
			btn.button_pressed = (i == current_player_strategy)
		else:
			btn.button_pressed = ((i - 3) == current_team_strategy)


func _on_substitute_player(index: int) -> void:
	"""替补球员"""
	print("[备战] 位置%d替补" % (index + 1))
	player_substituted.emit(index, "")


func _on_change_spirit(index: int) -> void:
	"""更换元灵：弹出元灵选择弹窗"""
	print("[备战] 位置%d更换元灵" % (index + 1))
	_open_spirit_select_popup(index)


var _spirit_popup_player_index: int = -1
var _spirit_popup: Control = null


func _open_spirit_select_popup(player_index: int) -> void:
	"""打开元灵选择弹窗"""
	_close_spirit_popup()
	_spirit_popup_player_index = player_index

	# 先加载元灵数据
	var spirits: Array = []
	if DataManager:
		spirits = DataManager.spirits

	var popup := Control.new()
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.name = "SpiritSelectPopup"
	add_child(popup)
	_spirit_popup = popup

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(_on_spirit_popup_bg_input)
	popup.add_child(overlay)

	# 弹窗面板（根据元灵数量调整高度）
	var popup_h: float = 160.0 + spirits.size() * 120.0 + 60.0
	var panel := Panel.new()
	panel.offset_left = 150
	panel.offset_top = 50
	panel.offset_right = 1050
	panel.offset_bottom = min(popup_h + 50, 700)
	popup.add_child(panel)

	# 滚动容器
	var scroll := ScrollContainer.new()
	scroll.offset_left = 160
	scroll.offset_top = 90
	scroll.offset_right = 1040
	scroll.offset_bottom = min(popup_h + 40, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(860, 0)
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# 元灵卡片列表（spirits已在上部加载）

	var element_colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}

	for i in range(spirits.size()):
		var s: Dictionary = spirits[i]
		var s_name: String = str(s.get("name", "?"))
		var s_elem: String = str(s.get("element", "?"))
		var s_desc: String = str(s.get("description", ""))
		var s_skills: Array = s.get("skills", [])
		var elem_color: Color = element_colors.get(s_elem, Color(0.6, 0.6, 0.6))

		# 卡片容器
		var card := Panel.new()
		card.custom_minimum_size = Vector2(850, 100)
		vbox.add_child(card)

		# 左侧：元素颜色圆形头像
		var avatar := Panel.new()
		avatar.size = Vector2(60, 60)
		avatar.position = Vector2(10, 20)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = elem_color
		avatar_style.set_corner_radius_all(30)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		card.add_child(avatar)

		var avatar_text := Label.new()
		avatar_text.text = s_elem
		avatar_text.position = Vector2(14, 35)
		avatar_text.add_theme_font_size_override("font_size", 13)
		avatar_text.add_theme_color_override("font_color", Color.WHITE)
		card.add_child(avatar_text)

		# 中间：名称 + 描述 + 技能列表
		var name_lbl := Label.new()
		name_lbl.text = s_name + "  [" + s_elem + "]"
		name_lbl.position = Vector2(80, 8)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", elem_color)
		card.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = s_desc
		desc_lbl.position = Vector2(80, 30)
		desc_lbl.size = Vector2(500, 20)
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		card.add_child(desc_lbl)

		# 技能列表
		var skill_names: String = ""
		for sid in s_skills:
			var sd: Dictionary = DataManager.get_skill_by_id(str(sid))
			if not sd.is_empty():
				if skill_names != "":
					skill_names += " | "
				skill_names += str(sd.get("name", str(sid)))
			else:
				if skill_names != "":
					skill_names += " | "
				skill_names += str(sid)
		var skills_lbl := Label.new()
		skills_lbl.text = "技能: " + (skill_names if skill_names != "" else "无")
		skills_lbl.position = Vector2(80, 52)
		skills_lbl.size = Vector2(500, 18)
		skills_lbl.add_theme_font_size_override("font_size", 12)
		skills_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		card.add_child(skills_lbl)

		# 右侧：选择按钮
		var sel_btn := Button.new()
		sel_btn.text = "选择"
		sel_btn.position = Vector2(760, 35)
		sel_btn.size = Vector2(80, 32)
		sel_btn.add_theme_font_size_override("font_size", 14)
		sel_btn.pressed.connect(_on_spirit_selected.bind(s))
		card.add_child(sel_btn)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.position = Vector2(560, min(popup_h + 30, 670))
	close_btn.size = Vector2(80, 30)
	close_btn.pressed.connect(_close_spirit_popup)
	popup.add_child(close_btn)


func _on_spirit_selected(spirit_data: Dictionary) -> void:
	"""选中元灵：更新球员并刷新UI"""
	var idx: int = _spirit_popup_player_index
	if idx < 0 or idx >= team_a_players.size():
		_close_spirit_popup()
		return

	var player: CharacterBody2D = team_a_players[idx]
	if not player or not is_instance_valid(player):
		_close_spirit_popup()
		return

	player.equip_spirit(spirit_data)
	_update_spirit_widget(idx, spirit_data)
	spirit_changed.emit(idx, str(spirit_data.get("id", "")))
	print("[备战] 位置%d 装备元灵: %s" % [idx + 1, spirit_data.get("name", "?")])
	_close_spirit_popup()


func _update_spirit_widget(index: int, spirit_data: Dictionary) -> void:
	"""更新元灵卡片显示"""
	if index >= spirit_widgets.size():
		return
	var w: Dictionary = spirit_widgets[index]
	w.current_label.text = "当前: " + str(spirit_data.get("name", "?")) + " [" + str(spirit_data.get("element", "?")) + "]"
	var skills: Array = spirit_data.get("skills", [])
	var skill_names: String = ""
	for sid in skills:
		var sd: Dictionary = DataManager.get_skill_by_id(str(sid))
		if not sd.is_empty():
			if skill_names != "":
				skill_names += ", "
			skill_names += str(sd.get("name", str(sid)))
	w.attr_label.text = "技能: " + (skill_names if skill_names != "" else "无")

	# 更新图标颜色和文字
	var s_elem: String = str(spirit_data.get("element", "?"))
	var element_colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	var elem_color: Color = element_colors.get(s_elem, Color(0.6, 0.6, 0.6))
	if w.icon_panel:
		var new_style := StyleBoxFlat.new()
		new_style.bg_color = elem_color
		new_style.set_corner_radius_all(35)
		w.icon_panel.add_theme_stylebox_override("panel", new_style)
	if w.icon_label:
		w.icon_label.text = s_elem + "\n元灵"
		w.icon_label.position = Vector2(287, 28)


func _on_spirit_popup_bg_input(event: InputEvent) -> void:
	"""点击遮罩关闭弹窗"""
	if event is InputEventMouseButton and event.pressed:
		_close_spirit_popup()


func _close_spirit_popup() -> void:
	"""关闭元灵选择弹窗"""
	if _spirit_popup and is_instance_valid(_spirit_popup):
		_spirit_popup.queue_free()
	_spirit_popup = null
	_spirit_popup_player_index = -1


func _on_start_match() -> void:
	"""开始比赛"""
	print("[备战] 开始比赛!")
	visible = false
	match_started_from_prep.emit()


# ===== 公开方法 =====

func set_ai_manager(ai_mgr: Node) -> void:
	ai_manager = ai_mgr

func get_player_strategy() -> int:
	return current_player_strategy

func get_team_strategy() -> int:
	return current_team_strategy
