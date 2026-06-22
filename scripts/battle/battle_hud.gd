extends Control
## 比赛HUD - 底部球员面板 + 顶部计分板 + 对方体力条

# === 底部球员面板（玩家方） ===
# [球员栏1] [球员栏2] [球员栏3]    [计时器] [比分]
# 每个球员栏：技能图标x3 | 体力条 | 元灵能量条 | 头像
# === 顶部计分板下方（对方体力） ===
# 队B球员1体力  队B球员2体力  队B球员3体力

var player_panels: Array[Control] = []
var player_stamina_bars: Array[ProgressBar] = []
var player_energy_bars: Array[ProgressBar] = []
var player_name_labels: Array[Label] = []
# 每个球员的技能图标容器：player_skill_boxes[i] = [ColorRect, ColorRect, ColorRect]
var player_skill_boxes: Array = []
var player_skill_labels: Array = []  # 技能首字标签 [i]=[Label,Label,Label]
var player_skill_cd_overlays: Array = []  # 技能圆形冷却遮罩 [i]=[TextureProgressBar x3]

var enemy_stamina_bars: Array[ProgressBar] = []
var enemy_name_labels: Array[Label] = []

var timer_label: Label
var score_label: Label
var quick_msg_buttons: Array[Button] = []
var comm_system: Node = null  # AI通信系统引用

# 技能提示弹窗
var skill_toast: Label = null
var skill_toast_timer: float = 0.0

# 球员引用
var team_players: Array[CharacterBody2D] = []  # 玩家方3个球员
var enemy_players: Array[CharacterBody2D] = []  # 对方3个球员


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1440, 810)

	_create_score_panel()
	_create_enemy_stamina_panel()
	_create_player_panels()
	_create_quick_message_bar()


func _process(_delta: float) -> void:
	_update_bars()
	# 技能提示弹窗计时淡出
	if skill_toast and skill_toast.visible:
		skill_toast_timer -= _delta
		if skill_toast_timer <= 0.0:
			skill_toast.visible = false
		elif skill_toast_timer < 0.5:
			skill_toast.modulate.a = skill_toast_timer / 0.5


func setup_players(team: Array[CharacterBody2D], enemies: Array[CharacterBody2D]) -> void:
	"""由 battle_manager 调用，绑定球员引用"""
	team_players = team
	enemy_players = enemies

	# 更新底部面板名称 + 技能图标
	for i in range(min(3, team.size())):
		if team[i] and team[i].char_data.has("name"):
			player_name_labels[i].text = team[i].char_data["name"]
		_update_player_skill_icons(i)

	# 更新对方名称
	for i in range(min(3, enemies.size())):
		if enemies[i] and enemies[i].char_data.has("name"):
			enemy_name_labels[i].text = enemies[i].char_data["name"]

	# 创建技能提示弹窗（延迟一帧，确保已进入场景树）
	call_deferred("_create_skill_toast")


## 根据球员装备的元灵技能，填充技能栏图标（图片/色块+首字）
func _update_player_skill_icons(player_index: int) -> void:
	if player_index >= player_skill_boxes.size():
		return
	var player: CharacterBody2D = team_players[player_index] if player_index < team_players.size() else null
	if not player:
		return
	var skill_ids: Array[String] = player.get_equipped_skills()
	var boxes: Array = player_skill_boxes[player_index]
	var labels: Array = player_skill_labels[player_index]
	for slot in range(3):
		var box: ColorRect = boxes[slot]
		var lbl: Label = labels[slot]
		if slot >= skill_ids.size():
			# 该位置无技能
			box.color = Color(0.2, 0.2, 0.2)
			lbl.text = ""
			continue
		var skill_data: Dictionary = DataManager.get_skill_by_id(skill_ids[slot])
		if skill_data.is_empty():
			# 留白技能（无数据）
			box.color = Color(0.15, 0.15, 0.15)
			lbl.text = "?"
			continue
		# 色块：优先 icon_color，为白色时用元素色兜底
		var color_str := str(skill_data.get("icon_color", "#FFFFFF"))
		var icon_color := Color.from_string(color_str, Color(0.6, 0.6, 0.6))
		if color_str == "#FFFFFF" or color_str == "":
			icon_color = _get_element_color(str(skill_data.get("element", "")))
		box.color = icon_color
		# 首字
		var skill_name := str(skill_data.get("name", ""))
		if skill_name.length() > 0:
			lbl.text = skill_name.substr(0, 1)
		else:
			lbl.text = ""


## 元素颜色映射（与 handler 一致）
func _get_element_color(element: String) -> Color:
	var colors: Dictionary = {
		"金刚": Color(0.85, 0.75, 0.3),
		"大地": Color(0.7, 0.55, 0.35),
		"雷火": Color(1.0, 0.4, 0.2),
		"冰雪": Color(0.4, 0.8, 1.0),
		"草木": Color(0.3, 0.8, 0.3),
		"梦幻": Color(0.7, 0.5, 0.9),
	}
	return colors.get(element, Color(0.6, 0.6, 0.6))


## 创建技能提示弹窗（中上方，1.5秒淡出）
func _create_skill_toast() -> void:
	if skill_toast != null and is_instance_valid(skill_toast):
		return
	skill_toast = Label.new()
	skill_toast.text = ""
	skill_toast.position = Vector2(520, 130)
	skill_toast.size = Vector2(400, 32)
	skill_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_toast.add_theme_font_size_override("font_size", 18)
	skill_toast.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	skill_toast.visible = false
	add_child(skill_toast)


## 显示技能提示（由 input_manager 调用）
## state: "激活" / "释放" / "取消"
func show_skill_toast(skill_id: String, state: String) -> void:
	if skill_toast == null:
		return
	var skill_data: Dictionary = DataManager.get_skill_by_id(skill_id)
	var skill_name: String = skill_data.get("name", skill_id) if not skill_data.is_empty() else skill_id
	skill_toast.text = "【%s】 %s" % [state, skill_name]
	skill_toast.visible = true
	skill_toast.modulate.a = 1.0
	skill_toast_timer = 1.5


func _update_bars() -> void:
	"""每帧更新所有条"""
	# 底部面板：玩家方
	for i in range(min(3, team_players.size())):
		var p: CharacterBody2D = team_players[i]
		if not p or not is_instance_valid(p):
			continue
		player_stamina_bars[i].max_value = p.max_stamina
		player_stamina_bars[i].value = p.stamina
		player_energy_bars[i].max_value = p.max_spirit_energy
		player_energy_bars[i].value = p.spirit_energy
		# 技能圆形冷却遮罩更新（0=可用，1=满冷却）
		if i < player_skill_cd_overlays.size():
			var skills: Array[String] = p.get_equipped_skills()
			var overlays: Array = player_skill_cd_overlays[i]
			for slot in range(3):
				if slot >= overlays.size():
					continue
				if slot < skills.size():
					overlays[slot].value = p.get_skill_cooldown_ratio(skills[slot])
				else:
					overlays[slot].value = 0.0

	# 顶部：对方体力
	for i in range(min(3, enemy_players.size())):
		var p: CharacterBody2D = enemy_players[i]
		if not p or not is_instance_valid(p):
			continue
		enemy_stamina_bars[i].max_value = p.max_stamina
		enemy_stamina_bars[i].value = p.stamina


# ============================================================
# 顶部计分板
# ============================================================

func _create_score_panel() -> void:
	"""顶部计分板和计时器"""
	var top_bar := ColorRect.new()
	top_bar.size = Vector2(1440, 45)
	top_bar.color = Color(0, 0, 0, 0.7)
	add_child(top_bar)

	# 比分
	score_label = Label.new()
	score_label.text = "队A 0 : 0 队B"
	score_label.position = Vector2(620, 7)
	score_label.size = Vector2(200, 32)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(score_label)

	# 计时器
	timer_label = Label.new()
	timer_label.text = "05:00"
	timer_label.position = Vector2(50, 7)
	timer_label.size = Vector2(120, 32)
	timer_label.add_theme_color_override("font_color", Color.YELLOW)
	add_child(timer_label)

	# 连接信号
	if GameManager:
		GameManager.match_time_updated.connect(_on_time_updated)
		GameManager.score_updated.connect(_on_score_updated)


func _create_enemy_stamina_panel() -> void:
	"""顶部计分板下方：对方球员体力条"""
	var panel_y: float = 48.0  # 紧贴计分板下方
	var bar_width: float = 120.0
	var bar_height: float = 14.0
	var total_width: float = 3 * bar_width + 2 * 20.0  # 3个条+间距
	var start_x: float = (1440.0 - total_width) / 2.0

	# 半透明背景
	var bg := ColorRect.new()
	bg.position = Vector2(start_x - 10.0, panel_y - 2.0)
	bg.size = Vector2(total_width + 20.0, bar_height + 18.0)
	bg.color = Color(0, 0, 0, 0.4)
	add_child(bg)

	for i in range(3):
		var x: float = start_x + i * (bar_width + 20.0)

		# 名称
		var name_label := Label.new()
		name_label.text = "?"
		name_label.position = Vector2(x, panel_y)
		name_label.size = Vector2(bar_width, 14)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
		add_child(name_label)
		enemy_name_labels.append(name_label)

		# 体力条
		var bar := ProgressBar.new()
		bar.position = Vector2(x, panel_y + 15.0)
		bar.size = Vector2(bar_width, bar_height)
		bar.max_value = 100
		bar.value = 100
		bar.show_percentage = false

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background", style)

		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(1.0, 0.3, 0.3)  # 红色=对方
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)

		add_child(bar)
		enemy_stamina_bars.append(bar)


# ============================================================
# 底部球员面板（玩家方）
# ============================================================

func _create_player_panels() -> void:
	"""底部三个球员面板"""
	var panel_width: float = 380.0
	var panel_height: float = 90.0
	var start_x: float = (1440.0 - panel_width * 3 - 20) / 2.0
	var start_y: float = 810.0 - panel_height - 12.0

	for i in range(3):
		var panel := _create_single_panel(i, Vector2(start_x + i * (panel_width + 10), start_y), panel_width, panel_height)
		player_panels.append(panel)
		add_child(panel)


func _create_single_panel(index: int, pos: Vector2, width: float, height: float) -> Panel:
	"""创建单个球员面板"""
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(width, height)

	# 背景
	var bg := ColorRect.new()
	bg.size = Vector2(width, height)
	bg.color = Color(0.1, 0.1, 0.3, 0.8)
	panel.add_child(bg)

	# 球员头像区域（左侧）
	var avatar_box := ColorRect.new()
	avatar_box.size = Vector2(50, 50)
	avatar_box.position = Vector2(10, 15)
	avatar_box.color = Color.BLUE
	panel.add_child(avatar_box)

	# 编号
	var num_label := Label.new()
	num_label.text = str(index + 1)
	num_label.position = Vector2(25, 25)
	num_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(num_label)

	# 球员名称
	var name_label := Label.new()
	name_label.text = "?"
	name_label.position = Vector2(70, 2)
	name_label.size = Vector2(150, 14)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	panel.add_child(name_label)
	player_name_labels.append(name_label)

	# 体力条
	var stamina := ProgressBar.new()
	stamina.position = Vector2(70, 18)
	stamina.size = Vector2(150, 12)
	stamina.max_value = 100
	stamina.value = 100
	stamina.show_percentage = false

	var stam_bg := StyleBoxFlat.new()
	stam_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	stam_bg.set_corner_radius_all(2)
	stamina.add_theme_stylebox_override("background", stam_bg)

	var stam_fill := StyleBoxFlat.new()
	stam_fill.bg_color = Color(0.2, 0.9, 0.3)
	stam_fill.set_corner_radius_all(2)
	stamina.add_theme_stylebox_override("fill", stam_fill)

	panel.add_child(stamina)
	player_stamina_bars.append(stamina)

	# 元灵能量条
	var energy := ProgressBar.new()
	energy.position = Vector2(70, 34)
	energy.size = Vector2(150, 8)
	energy.max_value = 100
	energy.value = 0
	energy.show_percentage = false

	var eng_bg := StyleBoxFlat.new()
	eng_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	eng_bg.set_corner_radius_all(2)
	energy.add_theme_stylebox_override("background", eng_bg)

	var eng_fill := StyleBoxFlat.new()
	eng_fill.bg_color = Color(0.3, 0.6, 1.0)
	eng_fill.set_corner_radius_all(2)
	energy.add_theme_stylebox_override("fill", eng_fill)

	panel.add_child(energy)
	player_energy_bars.append(energy)

	# 技能图标占位 x3
	var this_player_skill_boxes: Array = []
	var this_player_skill_labels: Array = []
	var this_player_skill_cd_overlays: Array = []
	for s in range(3):
		var skill_box := ColorRect.new()
		skill_box.size = Vector2(30, 30)
		skill_box.position = Vector2(70 + s * 35, 48)
		skill_box.color = Color(0.25, 0.25, 0.25)  # 默认深灰（无技能）
		panel.add_child(skill_box)
		this_player_skill_boxes.append(skill_box)

		# 圆形冷却遮罩（叠在色块上，半透明黑灰钟表扫过式）
		# 2026-06-19：修复冷却钟不显示——radial 模式需方形居中贴图 + 正确的 fill_mode
		var cd_overlay := TextureProgressBar.new()
		cd_overlay.size = Vector2(30, 30)
		cd_overlay.position = Vector2(70 + s * 35, 48)
		cd_overlay.min_value = 0
		cd_overlay.max_value = 1
		cd_overlay.value = 0  # 0=不遮罩(可用)，1=全遮罩(满冷却)
		# 顺时针填充：value=1 时全灰盖住图标，冷却中 value 从1→0，灰色扇形顺时针退去
		cd_overlay.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		cd_overlay.radial_center_offset = Vector2.ZERO
		cd_overlay.radial_fill_degrees = 360
		# 生成以中心为圆心的实心圆贴图（radial 模式按贴图区域扫描）
		var cd_img := Image.create(30, 30, false, Image.FORMAT_RGBA8)
		cd_img.fill(Color(0, 0, 0, 0))  # 先全透明
		var center := Vector2i(15, 15)
		var radius := 14
		for y in range(30):
			for x in range(30):
				var dx := x - center.x
				var dy := y - center.y
				if dx * dx + dy * dy <= radius * radius:
					cd_img.set_pixel(x, y, Color(0.05, 0.05, 0.05, 0.78))
		cd_overlay.texture_progress = ImageTexture.create_from_image(cd_img)
		panel.add_child(cd_overlay)
		this_player_skill_cd_overlays.append(cd_overlay)

		# 技能首字标签（叠在色块上）
		var skill_char_label := Label.new()
		skill_char_label.text = ""
		skill_char_label.position = Vector2(70 + s * 35 + 8, 54)
		skill_char_label.size = Vector2(14, 18)
		skill_char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_char_label.add_theme_font_size_override("font_size", 14)
		skill_char_label.add_theme_color_override("font_color", Color.WHITE)
		panel.add_child(skill_char_label)
		this_player_skill_labels.append(skill_char_label)

		var skill_num := Label.new()
		skill_num.text = str(s + 4)  # 快捷键 4,5,6
		skill_num.position = Vector2(80 + s * 35, 75)
		skill_num.add_theme_font_size_override("font_size", 11)
		skill_num.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		panel.add_child(skill_num)

	player_skill_boxes.append(this_player_skill_boxes)
	player_skill_labels.append(this_player_skill_labels)
	player_skill_cd_overlays.append(this_player_skill_cd_overlays)

	# 快捷键提示
	var key_label := Label.new()
	key_label.text = "[%d]" % (index + 1)
	key_label.position = Vector2(10, height - 20)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(key_label)

	return panel


# ============================================================
# 信号回调
# ============================================================

func _on_time_updated(time: float) -> void:
	var total_seconds: int = int(time)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


func _on_score_updated(_team: String, _new_score: int) -> void:
	score_label.text = "队A %d : %d 队B" % [GameManager.score_team_a, GameManager.score_team_b]


# ============================================================
# 快捷消息栏
# ============================================================

func _create_quick_message_bar() -> void:
	"""在球员面板左侧创建快捷消息栏"""
	var bar_width: float = 70.0
	var bar_height: float = 90.0
	var bar_x: float = 10.0
	var bar_y: float = 810.0 - bar_height - 12.0

	var bg := Panel.new()
	bg.position = Vector2(bar_x, bar_y)
	bg.size = Vector2(bar_width, bar_height)
	add_child(bg)

	var inner_bg := ColorRect.new()
	inner_bg.size = Vector2(bar_width, bar_height)
	inner_bg.color = Color(0.1, 0.15, 0.25, 0.85)
	bg.add_child(inner_bg)

	var title := Label.new()
	title.text = "信号"
	title.position = Vector2(18, 3)
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	bg.add_child(title)

	var labels := ["防守[7]", "传我[8]", "别传[9]"]
	var colors := [
		Color(1.0, 0.7, 0.3),
		Color(0.3, 1.0, 0.5),
		Color(1.0, 0.4, 0.4),
	]

	for i in range(3):
		var btn := Button.new()
		btn.text = labels[i]
		btn.position = Vector2(3, 18 + i * 24)
		btn.size = Vector2(64, 21)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", colors[i])
		btn.add_theme_color_override("font_hover_color", colors[i].lightened(0.3))
		var msg_index: int = i
		btn.pressed.connect(_on_quick_msg_pressed.bind(msg_index))
		bg.add_child(btn)
		quick_msg_buttons.append(btn)


func _on_quick_msg_pressed(msg_index: int) -> void:
	"""快捷消息按钮点击"""
	if comm_system:
		var player: CharacterBody2D = null
		if GameManager and not GameManager.team_a.is_empty():
			for p in GameManager.team_a:
				if p and p.is_player_controlled:
					player = p
					break
		if player:
			comm_system.try_send_message(player, msg_index)


func set_comm_system(sys: Node) -> void:
	comm_system = sys
