extends Control
## 比赛结算界面
## 4个Tab: 战报 / 数据面板 / 消耗与奖励 / 确认

# 结算数据
var _score_a: int = 0
var _score_b: int = 0
var _result: String = "draw"  # "win" / "lose" / "draw"
var _duration_s: float = 0.0
var _rewards: Dictionary = {}
var _player_stats: Dictionary = {}  # MatchPlayerStats.PlayerStats 数组

# UI元素
var _tab_buttons: Array = []
var _tab_container: Control = null
var _current_tab: int = 0
var _tab_names: Array = ["战报", "数据", "奖励", "确认"]

# 颜色方案
const BG_COLOR := Color(0.06, 0.08, 0.12, 0.98)
const WIN_COLOR := Color(0.2, 0.8, 0.3)
const LOSE_COLOR := Color(0.8, 0.2, 0.2)
const DRAW_COLOR := Color(0.8, 0.8, 0.2)
const CARD_BG := Color(0.1, 0.12, 0.18, 0.95)
const TEXT_COLOR := Color(0.85, 0.88, 0.92)
const ACCENT_COLOR := Color(0.3, 0.6, 1.0)

signal result_confirmed()


func _ready() -> void:
	# 全屏覆盖
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[ResultUI] _ready 开始, size=", size)
	
	# 背景（不拦截鼠标）
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	
	# 主容器
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_vbox)
	
	# 顶部留白
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	main_vbox.add_child(top_spacer)
	
	# 结果标题
	_add_result_header(main_vbox)
	
	# 比分行
	_add_score_display(main_vbox)
	
	# Tab按钮栏
	_add_tab_bar(main_vbox)
	
	# Tab内容区（用VBoxContainer确保子节点自动撑满宽度）
	_tab_container = VBoxContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.custom_minimum_size = Vector2(0, 400)
	_tab_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_container.add_theme_constant_override("separation", 0)
	main_vbox.add_child(_tab_container)
	
	# 默认显示第一个Tab（延迟到布局完成后）
	call_deferred("_show_tab", 0)
	print("[ResultUI] _ready 完成, tab_buttons=", _tab_buttons.size())


## 初始化结算数据（由battle_manager调用）
func setup(score_a: int, score_b: int, duration_s: float, result: String, rewards: Dictionary, stats_data: Dictionary) -> void:
	_score_a = score_a
	_score_b = score_b
	_duration_s = duration_s
	_result = result
	_rewards = rewards
	_player_stats = stats_data


# ===== UI构建 =====

func _add_result_header(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 36)
	
	match _result:
		"win":
			header.text = "★ 胜利！★"
			header.add_theme_color_override("font_color", WIN_COLOR)
		"lose":
			header.text = "惋惜败北"
			header.add_theme_color_override("font_color", LOSE_COLOR)
		_:
			header.text = "平局"
			header.add_theme_color_override("font_color", DRAW_COLOR)
	
	parent.add_child(header)


func _add_score_display(parent: VBoxContainer) -> void:
	var score_box := HBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.add_theme_constant_override("separation", 20)
	
	var label_a := Label.new()
	label_a.text = "队A  %d" % _score_a
	label_a.add_theme_font_size_override("font_size", 28)
	label_a.add_theme_color_override("font_color", ACCENT_COLOR)
	score_box.add_child(label_a)
	
	var vs := Label.new()
	vs.text = "vs"
	vs.add_theme_font_size_override("font_size", 22)
	vs.add_theme_color_override("font_color", Color.GRAY)
	score_box.add_child(vs)
	
	var label_b := Label.new()
	label_b.text = "%d  队B" % _score_b
	label_b.add_theme_font_size_override("font_size", 28)
	label_b.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	score_box.add_child(label_b)
	
	parent.add_child(score_box)
	
	# 比赛时长
	var time_label := Label.new()
	var minutes: int = int(_duration_s) / 60
	var seconds: int = int(_duration_s) % 60
	time_label.text = "比赛时长: %02d:%02d" % [minutes, seconds]
	time_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 16)
	time_label.add_theme_color_override("font_color", Color.GRAY)
	parent.add_child(time_label)


func _add_tab_bar(parent: VBoxContainer) -> void:
	var tab_bar := HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 5)
	tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for i in range(_tab_names.size()):
		var btn := Button.new()
		btn.text = _tab_names[i]
		btn.custom_minimum_size = Vector2(100, 36)
		btn.add_theme_font_size_override("font_size", 16)
		var tab_index: int = i
		btn.pressed.connect(func(): print("[ResultUI] 按钮", tab_index, "被点击"); _show_tab(tab_index))
		tab_bar.add_child(btn)
		_tab_buttons.append(btn)
	
	parent.add_child(tab_bar)


# ===== Tab内容 =====

func _show_tab(index: int) -> void:
	_current_tab = index
	print("[ResultUI] _show_tab(", index, ") called, tab_container=", is_instance_valid(_tab_container))
	
	# 清除旧内容（立即释放，避免与新内容叠加）
	for child in _tab_container.get_children():
		child.free()
	
	# 更新按钮高亮
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		if i == index:
			btn.modulate = Color(1.0, 1.0, 0.7)
		else:
			btn.modulate = Color.WHITE
	
	# 显示对应Tab内容
	match index:
		0: _show_battle_report()
		1: _show_data_panel()
		2: _show_rewards_panel()
		3: _show_confirm_panel()
	
	print("[ResultUI] _show_tab(", index, ") 完成, tab_container子节点数=", _tab_container.get_child_count())


## Tab 1: 战报
func _show_battle_report() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	
	# 我方阵容
	_add_section_title(vbox, "── 我方阵容 ──")
	_add_team_stats(vbox, "a")
	
	# 对方阵容
	_add_section_title(vbox, "── 对方阵容 ──")
	_add_team_stats(vbox, "b")


## Tab 2: 数据面板
func _show_data_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)
	
	# 每位球员的数据卡片
	var all_stats: Array = _player_stats.get("players", [])
	for ps in all_stats:
		_add_player_data_card(vbox, ps)


## Tab 3: 消耗与奖励
func _show_rewards_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	
	# 食物消耗
	_add_section_title(vbox, "── 食物消耗 ──")
	var food_label := Label.new()
	var active_food: String = NutritionManager.get_active_food_id()
	if active_food != "":
		var food_data: Dictionary = NutritionManager.get_food(active_food)
		var food_name: String = food_data.get("name", active_food)
		food_label.text = "  %s x1 已消耗" % food_name
	else:
		food_label.text = "  未食用食物"
	food_label.add_theme_color_override("font_color", TEXT_COLOR)
	food_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(food_label)
	
	# 比赛奖励
	_add_section_title(vbox, "── 比赛奖励 ──")
	var reward_card := _create_card()
	var reward_vbox := VBoxContainer.new()
	reward_vbox.add_theme_constant_override("separation", 4)
	reward_card.add_child(reward_vbox)
	
	# 奖励结果
	var result_text: String = ""
	match _result:
		"win": result_text = "胜利奖励"
		"lose": result_text = "败北奖励"
		_: result_text = "平局奖励"
	
	_add_reward_row(reward_vbox, result_text, "")
	_add_reward_row(reward_vbox, "童话币", "+%d" % _rewards.get("fairy_coin", 0))
	_add_reward_row(reward_vbox, "元灵矿石", "+%d" % _rewards.get("spirit_ore", 0))
	_add_reward_row(reward_vbox, "水晶", "+%d" % _rewards.get("crystal", 0))
	
	# 连胜提示
	var streak: int = RewardSystem.get_win_streak()
	if streak > 1 and _result == "win":
		_add_reward_row(reward_vbox, "连胜x%d加成" % streak, "")
	
	vbox.add_child(reward_card)
	
	# 奖励未开启提示
	if not RewardSystem.reward_config.get("reward_enabled", false):
		var warn := Label.new()
		warn.text = "（奖励开关未开启，货币未实际发放）"
		warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		warn.add_theme_font_size_override("font_size", 12)
		vbox.add_child(warn)


## Tab 4: 确认返回
func _show_confirm_panel() -> void:
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(center)
	
	# 状态提示
	var lines: Array = ["奖励已结算", "食物状态已清除"]
	for text in lines:
		var lbl := Label.new()
		lbl.text = text
		lbl.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		center.add_child(lbl)
	
	# 间距
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	center.add_child(spacer)
	
	# 确认按钮
	var confirm_btn := Button.new()
	confirm_btn.text = "确认返回主菜单"
	confirm_btn.custom_minimum_size = Vector2(220, 48)
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.pressed.connect(_on_confirm_pressed)
	center.add_child(confirm_btn)


# ===== 辅助UI方法 =====

func _add_section_title(parent: VBoxContainer, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	parent.add_child(lbl)


func _add_team_stats(parent: VBoxContainer, team: String) -> void:
	var all_stats: Array = _player_stats.get("players", [])
	for ps in all_stats:
		if ps.get("team", "") != team:
			continue
		var status: String = "存活" if ps.get("survived", true) else "被罚下"
		var line := "  %s  击杀:%d  死亡:%d  伤害:%.0f  [%s]" % [
			ps.get("player_name", "?"),
			ps.get("kills", 0),
			ps.get("deaths", 0),
			ps.get("damage_dealt", 0.0),
			status
		]
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		parent.add_child(lbl)


func _add_player_data_card(parent: VBoxContainer, ps: Dictionary) -> void:
	var card := _create_card()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	card.add_child(grid)
	
	# 标题行
	var name_lbl := Label.new()
	name_lbl.text = ps.get("player_name", "?")
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	grid.add_child(name_lbl)
	
	var team_lbl := Label.new()
	team_lbl.text = "队%s" % ps.get("team", "?")
	team_lbl.add_theme_font_size_override("font_size", 14)
	grid.add_child(team_lbl)
	
	var status_lbl := Label.new()
	status_lbl.text = "存活" if ps.get("survived", true) else "被罚下"
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", WIN_COLOR if ps.get("survived", true) else LOSE_COLOR)
	grid.add_child(status_lbl)
	
	# 数据行
	_add_stat_row(grid, "击杀", "%d" % ps.get("kills", 0))
	_add_stat_row(grid, "死亡", "%d" % ps.get("deaths", 0))
	_add_stat_row(grid, "伤害", "%.0f" % ps.get("damage_dealt", 0.0))
	_add_stat_row(grid, "接球", "%d" % ps.get("balls_caught", 0))
	_add_stat_row(grid, "截球", "%d" % ps.get("balls_intercepted", 0))
	_add_stat_row(grid, "技能", "%d" % ps.get("skills_used", 0))
	
	parent.add_child(card)


func _add_stat_row(grid: GridContainer, label: String, value: String) -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.GRAY)
	grid.add_child(lbl)
	
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(val)
	
	# 占位保持3列
	var spacer := Label.new()
	spacer.text = ""
	grid.add_child(spacer)


func _add_reward_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	var lbl := Label.new()
	lbl.text = "  " + label
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(lbl)
	
	if value != "":
		var val := Label.new()
		val.text = value
		val.add_theme_font_size_override("font_size", 14)
		val.add_theme_color_override("font_color", WIN_COLOR)
		row.add_child(val)
	
	parent.add_child(row)


func _create_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.content_margin_left = 10
	style.content_margin_right = 10
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card


func _on_confirm_pressed() -> void:
	print("[MatchResultUI] 确认返回主菜单")
	result_confirmed.emit()
